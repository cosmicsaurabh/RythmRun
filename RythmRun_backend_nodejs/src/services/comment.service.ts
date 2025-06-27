import { PrismaClient } from '../../generated/prisma';
import { CreateCommentDto } from '../models/dto/comment.dto';

export class CommentService {
    private prisma: PrismaClient;

    constructor() {
        this.prisma = new PrismaClient();
    }

    async createComment(userId: number, activityId: number, dto: CreateCommentDto) {
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

        // Create the comment
        const comment = await this.prisma.comment.create({
            data: {
                content: dto.content,
                userId,
                activityId
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
                }
            }
        });

        return comment;
    }

    async updateComment(userId: number, commentId: number, dto: CreateCommentDto) {
        // Check if comment exists and belongs to the user
        const existingComment = await this.prisma.comment.findFirst({
            where: {
                id: commentId,
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
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicture: true,
                        profilePictureType: true
                    }
                }
            }
        });

        return updatedComment;
    }

    async deleteComment(userId: number, commentId: number) {
        // Check if comment exists and belongs to the user
        const existingComment = await this.prisma.comment.findFirst({
            where: {
                id: commentId,
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