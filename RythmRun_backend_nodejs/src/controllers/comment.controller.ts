import { Request, Response } from 'express';
import { CommentService } from '../services/comment.service';
import { CreateCommentDto } from '../models/dto/comment.dto';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';

export class CommentController {
    private commentService: CommentService;

    constructor() {
        this.commentService = new CommentService();
    }

    createComment = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.id);
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
} 