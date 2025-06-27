import { Request, Response } from 'express';
import { FriendService } from '../services/friend.service';
import { SendFriendRequestDto } from '../models/dto/friend.dto';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';

export class FriendController {
    private friendService: FriendService;

    constructor() {
        this.friendService = new FriendService();
    }

    sendFriendRequest = async (req: Request, res: Response) => {
        try {
            // Transform and validate request body
            const sendRequestDto = plainToClass(SendFriendRequestDto, req.body);
            const errors = await validate(sendRequestDto, {
                forbidUnknownValues: true,
                whitelist: true
            });

            if (errors.length > 0) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid input',
                    errors: errors.map(error => ({
                        property: error.property,
                        constraints: error.constraints
                    }))
                });
            }

            // Send friend request
            const result = await this.friendService.sendFriendRequest(req.user!.id, sendRequestDto);

            return res.status(201).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Target user not found') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            if (error?.message === 'Cannot send friend request to yourself' ||
                error?.message === 'Friend request already pending' ||
                error?.message === 'Already friends with this user') {
                return res.status(400).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Send friend request error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    cancelFriendRequest = async (req: Request, res: Response) => {
        try {
            const targetUserId = parseInt(req.params.userId);
            if (isNaN(targetUserId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid target user ID'
                });
            }

            const result = await this.friendService.cancelFriendRequest(req.user!.id, targetUserId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'No pending friend request found') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Cancel friend request error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    acceptFriendRequest = async (req: Request, res: Response) => {
        try {
            const requestId = parseInt(req.params.id);
            if (isNaN(requestId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid friend request ID'
                });
            }

            const result = await this.friendService.acceptFriendRequest(req.user!.id, requestId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'No pending friend request found') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Accept friend request error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    rejectFriendRequest = async (req: Request, res: Response) => {
        try {
            const requestId = parseInt(req.params.id);
            if (isNaN(requestId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid friend request ID'
                });
            }

            const result = await this.friendService.rejectFriendRequest(req.user!.id, requestId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'No pending friend request found') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Reject friend request error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };
} 