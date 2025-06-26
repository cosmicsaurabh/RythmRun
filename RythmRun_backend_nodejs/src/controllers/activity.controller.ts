import { Request, Response } from 'express';
import { ActivityService } from '../services/activity.service';
import { GetActivitiesQueryDto } from '../models/dto/activity.dto';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';

export class ActivityController {
    private activityService: ActivityService;

    constructor() {
        this.activityService = new ActivityService();
    }

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
} 