import { PrismaClient } from '../../generated/prisma';

export class LikeService {
    private prisma: PrismaClient;

    constructor() {
        this.prisma = new PrismaClient();
    }

    async likeActivity(userId: number, activityId: number) {
        // Check if activity exists and is accessible to the user
        const activity = await this.prisma.activity.findFirst({
            where: {
                id: activityId,
                OR: [
                    { userId },        // User's own activity
                    { isPublic: true } // Public activity
                ]
            }
        });

        if (!activity) {
            throw new Error('Activity not found or access denied');
        }

        // Check if user has already liked the activity
        const existingLike = await this.prisma.like.findUnique({
            where: {
                activityId_userId: {
                    activityId,
                    userId
                }
            }
        });

        if (existingLike) {
            throw new Error('Activity already liked');
        }

        // Create the like
        await this.prisma.like.create({
            data: {
                activityId,
                userId
            }
        });

        // Return updated like count
        const likeCount = await this.prisma.like.count({
            where: { activityId }
        });

        return {
            message: 'Activity liked successfully',
            likeCount
        };
    }

    async unlikeActivity(userId: number, activityId: number) {
        // Check if like exists
        const existingLike = await this.prisma.like.findUnique({
            where: {
                activityId_userId: {
                    activityId,
                    userId
                }
            }
        });

        if (!existingLike) {
            throw new Error('Like not found');
        }

        // Delete the like
        await this.prisma.like.delete({
            where: {
                activityId_userId: {
                    activityId,
                    userId
                }
            }
        });

        // Return updated like count
        const likeCount = await this.prisma.like.count({
            where: { activityId }
        });

        return {
            message: 'Activity unliked successfully',
            likeCount
        };
    }
} 