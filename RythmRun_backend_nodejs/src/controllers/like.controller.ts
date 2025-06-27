import { Request, Response } from 'express';
import { LikeService } from '../services/like.service';

export class LikeController {
    private likeService: LikeService;

    constructor() {
        this.likeService = new LikeService();
    }

    likeActivity = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.id);
            if (isNaN(activityId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            const result = await this.likeService.likeActivity(req.user!.id, activityId);

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

            if (error?.message === 'Activity already liked') {
                return res.status(400).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Like activity error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    unlikeActivity = async (req: Request, res: Response) => {
        try {
            const activityId = parseInt(req.params.id);
            if (isNaN(activityId)) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid activity ID'
                });
            }

            const result = await this.likeService.unlikeActivity(req.user!.id, activityId);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Like not found') {
                return res.status(404).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Unlike activity error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };
} 