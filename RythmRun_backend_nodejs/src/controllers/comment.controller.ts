import { Request, Response } from 'express';
import { CommentService } from '../services/comment.service';
import { CreateCommentDto } from '../models/dto/comment.dto';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';
import { injectable, inject } from "tsyringe";

@injectable()
export class CommentController {
    constructor(
        @inject("CommentService") private commentService: CommentService
    ) {}

    getComments = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.activityId);
            if (isNaN(activityId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            const result = await this.commentService.getComments(req.user!.id, activityId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Activity not found or access denied') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Get comments error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    getComment = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.activityId);
            const commentId = parseInt(req.params.commentId);
            if (isNaN(activityId) || isNaN(commentId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID or comment ID'
                });
            }

            const result = await this.commentService.getComment(req.user!.id, activityId, commentId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Activity not found or access denied') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            if (error?.message === 'Comment not found') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Get comment error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    createComment = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.activityId);
            if (isNaN(activityId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            // Transform and validate request body
            const createDto = plainToClass(CreateCommentDto, req.body);
            const errors = await validate(createDto, {
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

            // Create comment
            const result = await this.commentService.createComment(req.user!.id, activityId, createDto);

            return res.status(201).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Activity not found or access denied') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Create comment error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    updateComment = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.activityId);
            const commentId = parseInt(req.params.commentId);
            if (isNaN(activityId) || isNaN(commentId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID or comment ID'
                });
            }

            // Transform and validate request body
            const updateDto = plainToClass(CreateCommentDto, req.body);
            const errors = await validate(updateDto, {
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

            // Update comment
            const result = await this.commentService.updateComment(req.user!.id, activityId, commentId, updateDto);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Activity not found or access denied') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            if (error?.message === 'Comment not found or unauthorized') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Update comment error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    deleteComment = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.activityId);
            const commentId = parseInt(req.params.commentId);
            if (isNaN(activityId) || isNaN(commentId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID or comment ID'
                });
            }

            // Delete comment
            const result = await this.commentService.deleteComment(req.user!.id, activityId, commentId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Activity not found or access denied') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            if (error?.message === 'Comment not found or unauthorized') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Delete comment error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };
} 