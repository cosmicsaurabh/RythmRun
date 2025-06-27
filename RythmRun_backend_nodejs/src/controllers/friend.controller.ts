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
} 