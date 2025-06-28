import { Router } from 'express';
import { container } from '../config/container';
import { LikeController } from '../controllers/like.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();
const likeController = container.resolve(LikeController);

/**
 * Like Routes
 * @route GET /api/activities/:activityId/likes
 * @description Get like status for current user on an activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @returns {Object} Like status and count
 */
router.get('/:activityId', authMiddleware, likeController.getLikeStatus);

/**
 * @route POST /api/activities/:activityId/likes
 * @description Like an activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @returns {Object} Updated like status
 */
router.post('/:activityId', authMiddleware, likeController.likeActivity);

/**
 * @route DELETE /api/activities/:activityId/likes
 * @description Unlike an activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @returns {Object} Updated like status
 */
router.delete('/:activityId', authMiddleware, likeController.unlikeActivity);

export default router; 