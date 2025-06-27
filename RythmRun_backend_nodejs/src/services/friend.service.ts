import { PrismaClient } from '../../generated/prisma';
import { SendFriendRequestDto } from '../models/dto/friend.dto';

export class FriendService {
    private prisma: PrismaClient;

    constructor() {
        this.prisma = new PrismaClient();
    }

    async sendFriendRequest(userId: number, dto: SendFriendRequestDto) {
        // Check if target user exists
        const targetUser = await this.prisma.user.findUnique({
            where: { id: dto.targetUserId }
        });

        if (!targetUser) {
            throw new Error('Target user not found');
        }

        // Check if user is trying to send request to themselves
        if (userId === dto.targetUserId) {
            throw new Error('Cannot send friend request to yourself');
        }

        // Check if friend request already exists in either direction
        const existingRequest = await this.prisma.friend.findFirst({
            where: {
                OR: [
                    {
                        user1Id: userId,
                        user2Id: dto.targetUserId
                    },
                    {
                        user1Id: dto.targetUserId,
                        user2Id: userId
                    }
                ]
            }
        });

        if (existingRequest) {
            if (existingRequest.status === 'PENDING') {
                throw new Error('Friend request already pending');
            } else if (existingRequest.status === 'ACCEPTED') {
                throw new Error('Already friends with this user');
            }
        }

        // Create friend request
        const friendRequest = await this.prisma.friend.create({
            data: {
                user1Id: userId,          // sender
                user2Id: dto.targetUserId, // receiver
                status: 'PENDING'
            },
            include: {
                user1: {
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicture: true,
                        profilePictureType: true
                    }
                },
                user2: {
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

        return friendRequest;
    }

    async cancelFriendRequest(userId: number, requestId: number) {
        // Find pending friend request sent by the user
        const pendingRequest = await this.prisma.friend.findFirst({
            where: {
                id: requestId,
                user1Id: userId,          // user must be the sender
                status: 'PENDING'
            }
        });

        if (!pendingRequest) {
            throw new Error('No pending friend request found');
        }

        // Delete the friend request
        await this.prisma.friend.delete({
            where: {
                id: pendingRequest.id
            }
        });

        return {
            message: 'Friend request cancelled successfully'
        };
    }

    async acceptFriendRequest(userId: number, requestId: number) {
        // Find pending friend request where user is the receiver
        const pendingRequest = await this.prisma.friend.findFirst({
            where: {
                id: requestId,
                user2Id: userId,    // user must be the receiver
                status: 'PENDING'
            },
            include: {
                user1: {
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicture: true,
                        profilePictureType: true
                    }
                },
                user2: {
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

        if (!pendingRequest) {
            throw new Error('No pending friend request found');
        }

        // Update the friend request status to ACCEPTED
        const acceptedRequest = await this.prisma.friend.update({
            where: {
                id: requestId
            },
            data: {
                status: 'ACCEPTED',
                updatedAt: new Date()
            },
            include: {
                user1: {
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicture: true,
                        profilePictureType: true
                    }
                },
                user2: {
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

        return acceptedRequest;
    }

    async rejectFriendRequest(userId: number, requestId: number) {
        // Find pending friend request where user is the receiver
        const pendingRequest = await this.prisma.friend.findFirst({
            where: {
                id: requestId,
                user2Id: userId,    // user must be the receiver
                status: 'PENDING'
            }
        });

        if (!pendingRequest) {
            throw new Error('No pending friend request found');
        }

        // Update the friend request status to REJECTED
        const rejectedRequest = await this.prisma.friend.update({
            where: {
                id: requestId
            },
            data: {
                status: 'REJECTED',
                updatedAt: new Date()
            }
        });

        return {
            message: 'Friend request rejected successfully'
        };
    }

    async getPendingFriendRequests(userId: number) {
        // Get all pending friend requests where user is the receiver
        const pendingRequests = await this.prisma.friend.findMany({
            where: {
                user2Id: userId,    // user is the receiver
                status: 'PENDING'
            },
            include: {
                user1: {
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicture: true,
                        profilePictureType: true
                    }
                }
            },
            orderBy: {
                createdAt: 'desc'
            }
        });

        return pendingRequests;
    }

    async getFriendRequestStatus(userId: number, otherUserId: number) {
        // Check if friend request exists in either direction
        const friendRequest = await this.prisma.friend.findFirst({
            where: {
                OR: [
                    {
                        user1Id: userId,
                        user2Id: otherUserId
                    },
                    {
                        user1Id: otherUserId,
                        user2Id: userId
                    }
                ]
            },
            include: {
                user1: {
                    select: {
                        id: true,
                        username: true,
                        firstname: true,
                        lastname: true,
                        profilePicture: true,
                        profilePictureType: true
                    }
                },
                user2: {
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

        if (!friendRequest) {
            return {
                status: 'NONE',
                message: 'No friend request exists'
            };
        }

        // Determine the direction and status of the request
        let requestDirection = '';
        if (friendRequest.status === 'PENDING') {
            requestDirection = friendRequest.user1Id === userId ? 'SENT' : 'RECEIVED';
        }

        return {
            status: friendRequest.status,
            direction: requestDirection,
            request: friendRequest
        };
    }
} 