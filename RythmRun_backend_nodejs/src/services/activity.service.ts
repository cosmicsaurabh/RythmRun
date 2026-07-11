import { Prisma, PrismaClient } from '../../generated/prisma';
import {
    GetActivitiesQueryDto,
    CreateActivityDto,
    UpdateActivityDto,
    LEGACY_METRICS_VERSION,
} from '../models/dto/activity.dto';
import {
    ActivityDomainValidationError,
    validateActivityCreate,
    validateMergedActivityUpdate,
} from '../models/activity-domain-validation';
import { injectable, inject } from "tsyringe";
import s3Service from './s3.service';

type ActivityImageWithS3Key = {
    s3Key: string;
    [key: string]: unknown;
};

type ActivityWithImages = {
    images?: ActivityImageWithS3Key[] | null;
};

function isPrismaRecordNotFound(error: unknown): boolean {
    return (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === 'P2025'
    );
}

function isPrismaSerializationFailure(error: unknown): boolean {
    return (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === 'P2034'
    );
}

const MAX_ACTIVITY_TRANSACTION_ATTEMPTS = 3;

export { ActivityDomainValidationError };

export class ActivityNotFoundError extends Error {
    readonly code = 'ACTIVITY_NOT_FOUND';
    readonly statusCode = 404;
    readonly retryable = false;

    constructor() {
        super('Activity not found or unauthorized');
        this.name = 'ActivityNotFoundError';
        Object.setPrototypeOf(this, ActivityNotFoundError.prototype);
    }
}

@injectable()
export class ActivityService {
    private readonly DEFAULT_PAGE = 1;
    private readonly DEFAULT_LIMIT = 10;
    private readonly MAX_LIMIT = 50; // Add maximum limit to prevent large queries
    private readonly activityInclude = {
        locations: true,
        statusChanges: true,
        images: {
            where: {
                status: 'UPLOADED',
                deletedAt: null
            },
            orderBy: {
                sortOrder: 'asc'
            }
        },
        _count: {
            select: {
                comments: true,
                likes: true
            }
        }
    } as const;

    constructor(
        @inject("PrismaClient") private prisma: PrismaClient
    ) {}

    async createActivity(userId: number, dto: CreateActivityDto) {
        // Create activity with its locations in a transaction
        const activity = await this.prisma.$transaction(async (tx) => {
            const existingActivity = await tx.activity.findUnique({
                where: {
                    userId_clientSyncId: {
                        userId,
                        clientSyncId: dto.clientSyncId
                    }
                },
                include: this.activityInclude
            });

            if (existingActivity) {
                return existingActivity;
            }

            // Idempotent retries return above. A genuinely new activity must
            // pass the complete semantic contract before the first write.
            validateActivityCreate(dto);

            // Create the activity
            const activity = await tx.activity.create({
                data: {
                    userId,
                    clientSyncId: dto.clientSyncId,
                    metricsVersion: dto.metricsVersion ?? LEGACY_METRICS_VERSION,
                    type: dto.type,
                    startTime: new Date(dto.startTime),
                    endTime: new Date(dto.endTime),
                    distance: dto.distance,
                    duration: dto.duration,
                    avgSpeed: dto.avgSpeed,
                    maxSpeed: dto.maxSpeed,
                    calories: dto.calories,
                    description: dto.description,
                    isPublic: dto.isPublic ?? true,
                    pausedDuration: dto.pausedDuration,
                    name: dto.name,
                    elevationGain: dto.elevationGain,
                    elevationLoss: dto.elevationLoss,
                }
            });

            // Create all locations for this activity
            if (dto.locations && dto.locations.length > 0) {
                await tx.location.createMany({
                    data: dto.locations.map(loc => ({
                        activityId: activity.id,
                        latitude: loc.latitude,
                        longitude: loc.longitude,
                        altitude: loc.altitude,
                        timestamp: new Date(loc.timestamp),
                        accuracy: loc.accuracy,
                        speed: loc.speed,
                        heading: loc.heading,
                    }))
                });
            }

            // Create status changes
            if (dto.statusChanges && dto.statusChanges.length > 0) {
                await tx.statusChange.createMany({
                    data: dto.statusChanges.map(sc => ({
                        activityId: activity.id,
                        status: sc.status,
                        timestamp: new Date(sc.timestamp),
                    }))
                });
            }

            // Return activity with its locations and status changes. Treat an
            // impossible missing read as a transaction failure so no partial
            // activity can commit.
            const persistedActivity = await tx.activity.findUnique({
                where: { id: activity.id },
                include: this.activityInclude
            });

            if (!persistedActivity) {
                throw new Error('Created activity could not be reloaded');
            }

            return persistedActivity;
        });

        return this.addImageUrls(activity);
    }

    async getActivities(userId: number, query: GetActivitiesQueryDto) {
        // Ensure page and limit are positive numbers and within bounds
        const page = Math.max(1, Math.abs(query.page || this.DEFAULT_PAGE));
        const limit = Math.min(
            this.MAX_LIMIT,
            Math.max(1, Math.abs(query.limit || this.DEFAULT_LIMIT))
        );
        const skip = (page - 1) * limit;

        // Build where clause based on query parameters
        const where = {
            userId,
            ...(query.type && { type: query.type }),
            ...(query.startDate && query.endDate && {
                startTime: {
                    gte: new Date(query.startDate),
                    lte: new Date(query.endDate)
                }
            })
        };

        // Get activities with pagination
        const [activities, total] = await Promise.all([
            this.prisma.activity.findMany({
                where,
                include: this.activityInclude,
                orderBy: {
                    startTime: 'desc'
                },
                skip,
                take: limit
            }),
            this.prisma.activity.count({ where })
        ]);

        // Calculate pagination metadata
        const totalPages = Math.ceil(total / limit);
        const hasNextPage = page < totalPages;
        const hasPreviousPage = page > 1;

        return {
            activities: activities.map((activity) => this.addImageUrls(activity)),
            pagination: {
                total,
                totalPages,
                currentPage: page,
                limit,
                hasNextPage,
                hasPreviousPage,
                requestedPage: query.page || this.DEFAULT_PAGE, // Add this to show what was requested
                requestedLimit: query.limit || this.DEFAULT_LIMIT // Add this to show what was requested
            }
        };
    }

    async updateActivity(userId: number, activityId: number, dto: UpdateActivityDto) {
        const windowChanged =
            dto.startTime !== undefined || dto.endTime !== undefined;
        const routeMetricsChanged =
            dto.distance !== undefined ||
            dto.duration !== undefined ||
            dto.avgSpeed !== undefined ||
            dto.maxSpeed !== undefined;
        const needsExistingLocations =
            dto.locations === undefined &&
            (windowChanged ||
                dto.statusChanges !== undefined ||
                dto.type !== undefined ||
                routeMetricsChanged);
        const needsExistingStatusChanges =
            (dto.statusChanges === undefined &&
                (windowChanged ||
                    dto.locations !== undefined ||
                    dto.pausedDuration !== undefined ||
                    dto.type !== undefined ||
                    routeMetricsChanged)) ||
            (dto.statusChanges?.length === 0 && dto.locations === undefined);

        for (
            let attempt = 0;
            attempt < MAX_ACTIVITY_TRANSACTION_ATTEMPTS;
            attempt += 1
        ) {
            try {
                const activity = await this.prisma.$transaction(async (tx) => {
                // Read ownership and the state needed to validate a partial
                // update inside the same transaction as the replacement.
                const existingActivity = await tx.activity.findFirst({
                    where: {
                        id: activityId,
                        userId
                    },
                    include: {
                        locations: needsExistingLocations
                            ? {
                                select: {
                                    latitude: true,
                                    longitude: true,
                                    accuracy: true,
                                    speed: true,
                                    timestamp: true
                                },
                                orderBy: { id: 'asc' }
                            }
                            : false,
                        statusChanges: needsExistingStatusChanges
                            ? {
                                select: {
                                    status: true,
                                    timestamp: true
                                },
                                orderBy: { id: 'asc' }
                            }
                            : false
                    }
                });

                if (!existingActivity) {
                    throw new ActivityNotFoundError();
                }

                // This must complete before the single nested write below.
                // Unrelated legacy rows remain patchable unless their metric,
                // timeline, or collection is part of this update.
                validateMergedActivityUpdate(existingActivity, dto);

                const data: Prisma.ActivityUpdateInput = {
                    ...(dto.type !== undefined && { type: dto.type }),
                    ...(dto.startTime !== undefined && {
                        startTime: new Date(dto.startTime)
                    }),
                    ...(dto.endTime !== undefined && {
                        endTime: new Date(dto.endTime)
                    }),
                    ...(dto.distance !== undefined && { distance: dto.distance }),
                    ...(dto.duration !== undefined && { duration: dto.duration }),
                    ...(dto.avgSpeed !== undefined && { avgSpeed: dto.avgSpeed }),
                    ...(dto.maxSpeed !== undefined && { maxSpeed: dto.maxSpeed }),
                    ...(dto.calories !== undefined && { calories: dto.calories }),
                    ...(dto.description !== undefined && {
                        description: dto.description
                    }),
                    ...(dto.isPublic !== undefined && { isPublic: dto.isPublic }),
                    ...(dto.pausedDuration !== undefined && {
                        pausedDuration: dto.pausedDuration
                    }),
                    ...(dto.name !== undefined && { name: dto.name }),
                    ...(dto.elevationGain !== undefined && {
                        elevationGain: dto.elevationGain
                    }),
                    ...(dto.elevationLoss !== undefined && {
                        elevationLoss: dto.elevationLoss
                    }),
                    ...(dto.locations !== undefined && {
                        locations: {
                            deleteMany: {},
                            ...(dto.locations.length > 0 && {
                                createMany: {
                                    data: dto.locations.map(loc => ({
                                        latitude: loc.latitude,
                                        longitude: loc.longitude,
                                        altitude: loc.altitude,
                                        timestamp: new Date(loc.timestamp),
                                        accuracy: loc.accuracy,
                                        speed: loc.speed,
                                        heading: loc.heading,
                                    }))
                                }
                            })
                        }
                    }),
                    ...(dto.statusChanges !== undefined && {
                        statusChanges: {
                            deleteMany: {},
                            ...(dto.statusChanges.length > 0 && {
                                createMany: {
                                    data: dto.statusChanges.map(statusChange => ({
                                        status: statusChange.status,
                                        timestamp: new Date(statusChange.timestamp),
                                    }))
                                }
                            })
                        }
                    })
                };

                // Prisma executes both collection replacements as part of this
                // one nested write. A rejected create therefore rolls back the
                // scalar update and both deletes.
                return tx.activity.update({
                    where: {
                        id: activityId,
                        userId
                    },
                    data,
                    include: this.activityInclude
                });
                }, {
                    isolationLevel:
                        Prisma.TransactionIsolationLevel.Serializable
                });

                return this.addImageUrls(activity);
            } catch (error) {
                if (
                    isPrismaSerializationFailure(error) &&
                    attempt < MAX_ACTIVITY_TRANSACTION_ATTEMPTS - 1
                ) {
                    continue;
                }

                if (error instanceof ActivityNotFoundError) {
                    throw error;
                }

                if (isPrismaRecordNotFound(error)) {
                    throw new ActivityNotFoundError();
                }

                throw error;
            }
        }

        throw new Error('Activity update transaction could not complete');
    }

    async deleteActivity(userId: number, activityId: number) {
        // Check if activity exists and belongs to user
        const activity = await this.prisma.activity.findFirst({
            where: {
                id: activityId,
                userId
            },
            include: {
                images: {
                    select: {
                        s3Key: true
                    }
                }
            }
        });

        if (!activity) {
            throw new Error('Activity not found or unauthorized');
        }

        const imageKeys = [...new Set(activity.images.map((image) => image.s3Key))];
        await Promise.all(
            imageKeys.map((key) => s3Service.deleteObject(key))
        );

        // Delete activity (this will cascade delete locations due to our schema)
        await this.prisma.activity.delete({
            where: { id: activityId }
        });

        return { message: 'Activity deleted successfully' };
    }

    async getActivityById(userId: number, activityId: number) {
        // Find activity and check if it belongs to user or is public
        const activity = await this.prisma.activity.findFirst({
            where: {
                id: activityId,
                OR: [
                    { userId },        // User's own activity
                    { isPublic: true } // Public activity
                ]
            },
            include: {
                ...this.activityInclude,
                user: {
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicturePath: true,
                        profilePictureType: true
                    }
                }
            }
        });

        if (!activity) {
            throw new Error('Activity not found or access denied');
        }

        return this.addImageUrls(activity);
    }

    private addImageUrls<T extends ActivityWithImages | null>(activity: T): T {
        if (!activity || !Array.isArray(activity.images)) {
            return activity;
        }

        return {
            ...activity,
            images: activity.images.map(({ s3Key, ...image }) => ({
                ...image,
                ...s3Service.getActivityImageReadUrl(s3Key)
            }))
        } as T;
    }
}
