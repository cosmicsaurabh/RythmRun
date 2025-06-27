import { PrismaClient } from '../../generated/prisma';
import { GetActivitiesQueryDto, CreateActivityDto, UpdateActivityDto } from '../models/dto/activity.dto';
import { injectable, inject } from "tsyringe";

@injectable()
export class ActivityService {
    private readonly DEFAULT_PAGE = 1;
    private readonly DEFAULT_LIMIT = 10;
    private readonly MAX_LIMIT = 50; // Add maximum limit to prevent large queries

    constructor(
        @inject("PrismaClient") private prisma: PrismaClient
    ) {}

    async createActivity(userId: number, dto: CreateActivityDto) {
        // Create activity with its locations in a transaction
        return await this.prisma.$transaction(async (tx) => {
            // Create the activity
            const activity = await tx.activity.create({
                data: {
                    userId,
                    type: dto.type,
                    startTime: new Date(dto.startTime),
                    endTime: new Date(dto.endTime),
                    distance: dto.distance,
                    duration: dto.duration,
                    avgSpeed: dto.avgSpeed,
                    maxSpeed: dto.maxSpeed,
                    calories: dto.calories,
                    description: dto.description,
                    isPublic: dto.isPublic ?? true, // Default to true if not provided
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
                        speed: loc.speed
                    }))
                });
            }

            // Return activity with its locations
            return await tx.activity.findUnique({
                where: { id: activity.id },
                include: {
                    locations: true,
                    _count: {
                        select: {
                            comments: true,
                            likes: true
                        }
                    }
                }
            });
        });
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
                include: {
                    locations: true,
                    _count: {
                        select: {
                            comments: true,
                            likes: true
                        }
                    }
                },
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
            activities,
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
        // First check if activity exists and belongs to user
        const existingActivity = await this.prisma.activity.findFirst({
            where: {
                id: activityId,
                userId
            }
        });

        if (!existingActivity) {
            throw new Error('Activity not found or unauthorized');
        }

        // Update activity with its locations in a transaction
        return await this.prisma.$transaction(async (tx) => {
            // Update the activity
            const activity = await tx.activity.update({
                where: { id: activityId },
                data: {
                    type: dto.type,
                    startTime: dto.startTime ? new Date(dto.startTime) : undefined,
                    endTime: dto.endTime ? new Date(dto.endTime) : undefined,
                    distance: dto.distance,
                    duration: dto.duration,
                    avgSpeed: dto.avgSpeed,
                    maxSpeed: dto.maxSpeed,
                    calories: dto.calories,
                    description: dto.description,
                    isPublic: dto.isPublic
                }
            });

            // If locations are provided, update them
            if (dto.locations && dto.locations.length > 0) {
                // Delete existing locations
                await tx.location.deleteMany({
                    where: { activityId }
                });

                // Create new locations
                await tx.location.createMany({
                    data: dto.locations.map(loc => ({
                        activityId,
                        latitude: loc.latitude,
                        longitude: loc.longitude,
                        altitude: loc.altitude,
                        timestamp: new Date(loc.timestamp),
                        accuracy: loc.accuracy,
                        speed: loc.speed
                    }))
                });
            }

            // Return updated activity with its locations
            return await tx.activity.findUnique({
                where: { id: activityId },
                include: {
                    locations: true,
                    _count: {
                        select: {
                            comments: true,
                            likes: true
                        }
                    }
                }
            });
        });
    }

    async deleteActivity(userId: number, activityId: number) {
        // Check if activity exists and belongs to user
        const activity = await this.prisma.activity.findFirst({
            where: {
                id: activityId,
                userId
            }
        });

        if (!activity) {
            throw new Error('Activity not found or unauthorized');
        }

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
                user: {
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicture: true,
                        profilePictureType: true
                    }
                },
                locations: true,
                _count: {
                    select: {
                        comments: true,
                        likes: true
                    }
                }
            }
        });

        if (!activity) {
            throw new Error('Activity not found or access denied');
        }

        return activity;
    }
} 