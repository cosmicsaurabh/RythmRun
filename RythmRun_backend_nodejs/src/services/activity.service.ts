import { PrismaClient } from '../../generated/prisma';
import { GetActivitiesQueryDto } from '../models/dto/activity.dto';

export class ActivityService {
    private prisma: PrismaClient;
    private readonly DEFAULT_PAGE = 1;
    private readonly DEFAULT_LIMIT = 10;
    private readonly MAX_LIMIT = 50; // Add maximum limit to prevent large queries

    constructor() {
        this.prisma = new PrismaClient();
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
} 