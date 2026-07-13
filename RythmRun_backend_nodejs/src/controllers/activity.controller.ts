import type { Request, Response } from 'express';
import {
    ActivityDomainValidationError,
    ActivityNotFoundError,
    ActivityService,
} from '../services/activity.service.js';
import { GetActivitiesQueryDto } from '../models/dto/activity.dto.js';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';
import { injectable, inject } from "tsyringe";
import {
    DtoValidationError,
    type DtoValidationIssue,
    MAX_DTO_ISSUE_MESSAGE_LENGTH,
    MAX_DTO_ISSUE_PATH_LENGTH,
} from '../middleware/validation.middleware.js';
import {
    validateCreateActivityDto,
    validateUpdateActivityDto,
} from '../middleware/activity-validation.middleware.js';

function activityRequestIssueCode(issue: DtoValidationIssue): string {
    if (issue.constraintCodes.includes('arrayMaxSize')) {
        if (issue.property === 'locations') {
            return 'ACTIVITY_LOCATION_LIMIT_EXCEEDED';
        }

        if (issue.property === 'statusChanges') {
            return 'ACTIVITY_STATUS_CHANGE_LIMIT_EXCEEDED';
        }
    }

    if (issue.constraintCodes.includes('whitelistValidation')) {
        return 'ACTIVITY_FIELD_NOT_ALLOWED';
    }

    if (issue.constraintCodes.includes('isIn')) {
        return 'ACTIVITY_VALUE_NOT_ALLOWED';
    }

    return 'ACTIVITY_FIELD_INVALID';
}

function boundedIssueText(value: string, maximumLength: number): string {
    if (value.length <= maximumLength) {
        return value;
    }

    return `${value.slice(0, maximumLength - 1)}…`;
}

function sendActivityError(res: Response, error: unknown): Response | undefined {
    if (error instanceof DtoValidationError) {
        return res.status(400).json({
            status: 'error',
            code: 'ACTIVITY_REQUEST_INVALID',
            message: 'Activity payload is invalid',
            retryable: false,
            issuesTruncated: error.issuesTruncated,
            issues: error.issues.map(issue => ({
                code: activityRequestIssueCode(issue),
                path: boundedIssueText(
                    issue.property,
                    MAX_DTO_ISSUE_PATH_LENGTH
                ),
                message: boundedIssueText(
                    issue.constraints.join('; '),
                    MAX_DTO_ISSUE_MESSAGE_LENGTH
                ),
            })),
        });
    }

    if (error instanceof ActivityDomainValidationError) {
        return res.status(error.statusCode).json({
            status: 'error',
            code: error.code,
            message: error.message,
            retryable: error.retryable,
            issuesTruncated: error.issuesTruncated,
            issues: error.issues.map(issue => ({
                code: issue.code,
                path: boundedIssueText(
                    issue.property,
                    MAX_DTO_ISSUE_PATH_LENGTH
                ),
                message: boundedIssueText(
                    issue.message,
                    MAX_DTO_ISSUE_MESSAGE_LENGTH
                ),
            })),
        });
    }

    if (error instanceof ActivityNotFoundError) {
        return res.status(error.statusCode).json({
            status: 'error',
            code: error.code,
            message: error.message,
            retryable: error.retryable,
        });
    }

    return undefined;
}

function safeErrorName(error: unknown): string {
    return error instanceof Error ? error.name : 'UnknownError';
}

function parseActivityId(value: string): number | null {
    if (!/^[1-9]\d*$/.test(value)) {
        return null;
    }

    const activityId = Number(value);
    return Number.isSafeInteger(activityId) ? activityId : null;
}

@injectable()
export class ActivityController {
    constructor(
        @inject("ActivityService") private activityService: ActivityService
    ) {}

    listActivities = async (req: Request, res: Response) => {
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

    getActivity = async (req: Request, res: Response) => {
        try {
            const activityId = parseActivityId(req.params.activityId as string);
            if (activityId === null) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            const result = await this.activityService.getActivityById(req.user!.id, activityId);

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

            console.error('Get activity error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    createActivity = async (req: Request, res: Response) => {
        try {
            const createDto = await validateCreateActivityDto(req.body);

            // Create activity
            const result = await this.activityService.createActivity(req.user!.id, createDto);

            return res.status(201).json({
                status: 'success',
                data: result
            });

        } catch (error) {
            const validationResponse = sendActivityError(res, error);
            if (validationResponse) {
                return validationResponse;
            }

            console.error(`Create activity error (${safeErrorName(error)})`);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    updateActivity = async (req: Request, res: Response) => {
        try {
            const activityId = parseActivityId(req.params.activityId as string);
            if (activityId === null) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            const updateDto = await validateUpdateActivityDto(req.body);

            // Update activity
            const result = await this.activityService.updateActivity(req.user!.id, activityId, updateDto);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            const validationResponse = sendActivityError(res, error);
            if (validationResponse) {
                return validationResponse;
            }

            console.error(`Update activity error (${safeErrorName(error)})`);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    deleteActivity = async (req: Request, res: Response) => {
        try {
            const activityId = parseActivityId(req.params.activityId as string);
            if (activityId === null) {
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
