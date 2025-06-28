import { PrismaClient } from '../../generated/prisma';
import { CreateCommentDto } from '../models/dto/comment.dto';

export class CommentService {
    private prisma: PrismaClient;

    constructor() {
        this.prisma = new PrismaClient();
    }

    private readonly userSelect = {
        id: true,
        username: true,
        firstname: true,
        lastname: true,
        profilePicturePath: true,
        profilePictureType: true
    };

    private async verifyActivityAccess(userId: number, activityId: number) {
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

        return activity;
    }

    async getComments(userId: number, activityId: number) {
        // Verify activity access
        await this.verifyActivityAccess(userId, activityId);

        // Get all comments for the activity
        const comments = await this.prisma.comment.findMany({
            where: {
                activityId
            },
            orderBy: {
                createdAt: 'desc'
            },
            include: {
                user: {
                    select: this.userSelect
                }
            }
        });

        return comments;
    }

    async getComment(userId: number, activityId: number, commentId: number) {
        // Verify activity access
        await this.verifyActivityAccess(userId, activityId);

        // Get the specific comment
        const comment = await this.prisma.comment.findFirst({
            where: {
                id: commentId,
                activityId
            },
            include: {
                user: {
                    select: this.userSelect
                }
            }
        });

        if (!comment) {
            throw new Error('Comment not found');
        }

        return comment;
    }

    async createComment(userId: number, activityId: number, dto: CreateCommentDto) {
        // Verify activity access
        await this.verifyActivityAccess(userId, activityId);

        // Create the comment
        const comment = await this.prisma.comment.create({
            data: {
                content: dto.content,
                userId,
                activityId
            },
            include: {
                user: {
                    select: this.userSelect
                }
            }
        });

        return comment;
    }

    async updateComment(userId: number, activityId: number, commentId: number, dto: CreateCommentDto) {
        // Verify activity access
        await this.verifyActivityAccess(userId, activityId);

        // Check if comment exists and belongs to the user
        const existingComment = await this.prisma.comment.findFirst({
            where: {
                id: commentId,
                activityId,
                userId
            }
        });

        if (!existingComment) {
            throw new Error('Comment not found or unauthorized');
        }

        // Update the comment
        const updatedComment = await this.prisma.comment.update({
            where: {
                id: commentId
            },
            data: {
                content: dto.content
            },
            include: {
                user: {
                    select: this.userSelect
                }
            }
        });

        return updatedComment;
    }

    async deleteComment(userId: number, activityId: number, commentId: number) {
        // Verify activity access
        await this.verifyActivityAccess(userId, activityId);

        // Check if comment exists and belongs to the user
        const existingComment = await this.prisma.comment.findFirst({
            where: {
                id: commentId,
                activityId,
                userId
            }
        });

        if (!existingComment) {
            throw new Error('Comment not found or unauthorized');
        }

        // Delete the comment
        await this.prisma.comment.delete({
            where: {
                id: commentId
            }
        });

        return {
            message: 'Comment deleted successfully'
        };
    }
} 