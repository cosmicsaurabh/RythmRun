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
} 