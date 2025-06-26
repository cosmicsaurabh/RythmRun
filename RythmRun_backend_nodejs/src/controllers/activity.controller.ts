import { Request, Response } from 'express';
import { ActivityService } from '../services/activity.service';
import { GetActivitiesQueryDto, CreateActivityDto, UpdateActivityDto } from '../models/dto/activity.dto';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';

export class ActivityController {
    private activityService: ActivityService;

    constructor() {
        this.activityService = new ActivityService();
    }

    createActivity = async (req: Request, res: Response) => {
        try {
            // Transform and validate request body
            const createDto = plainToClass(CreateActivityDto, req.body);
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

            // Validate timestamps
            const startTime = new Date(createDto.startTime);
            const endTime = new Date(createDto.endTime);
            
            if (isNaN(startTime.getTime()) || isNaN(endTime.getTime())) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid date format'
                });
            }

            if (endTime <= startTime) {
                return res.status(400).json({
                    status: 'error',
                    message: 'End time must be after start time'
                });
            }

            // Create activity
            const result = await this.activityService.createActivity(req.user!.id, createDto);

            return res.status(201).json({
                status: 'success',
                data: result
            });

        } catch (error) {
            console.error('Create activity error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    getActivities = async (req: Request, res: Response) => {
        try {
            // Convert string query parameters to numbers where needed
            const query = {
                ...req.query,
                page: req.query.page ? parseInt(req.query.page as string) : undefined,
                limit: req.query.limit ? parseInt(req.query.limit as string) : undefined
            };

            // Transform and validate query parameters
            const queryDto = plainToClass(GetActivitiesQueryDto, query);
            const errors = await validate(queryDto, { 
                forbidUnknownValues: true,
                whitelist: true 
            });
            
            if (errors.length > 0) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid query parameters',
                    errors: errors.map(error => ({
                        property: error.property,
                        constraints: error.constraints
                    }))
                });
            }

            // Get activities
            const result = await this.activityService.getActivities(req.user!.id, queryDto);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error) {
            console.error('Get activities error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    updateActivity = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.id);
            if (isNaN(activityId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            // Transform and validate request body
            const updateDto = plainToClass(UpdateActivityDto, req.body);
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

            // Validate timestamps if provided
            if (updateDto.startTime && updateDto.endTime) {
                const startTime = new Date(updateDto.startTime);
                const endTime = new Date(updateDto.endTime);
                
                if (isNaN(startTime.getTime()) || isNaN(endTime.getTime())) {
                    return res.status(400).json({
                        status: 'error',
                        message: 'Invalid date format'
                    });
                }

                if (endTime <= startTime) {
                    return res.status(400).json({
                        status: 'error',
                        message: 'End time must be after start time'
                    });
                }
            }

            // Update activity
            const result = await this.activityService.updateActivity(req.user!.id, activityId, updateDto);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Activity not found or unauthorized') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Update activity error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    deleteActivity = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.id);
            if (isNaN(activityId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            // Delete activity
            const result = await this.activityService.deleteActivity(req.user!.id, activityId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Activity not found or unauthorized') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Delete activity error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };
} 