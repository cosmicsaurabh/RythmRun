import { Router } from 'express';
import { container } from '../config/container';
import { ActivityController } from '../controllers/activity.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();
const activityController = container.resolve(ActivityController);

/**
 * Activity Routes
 * @route GET /api/activities
 * @description Get list of activities (paginated)
 * @auth Required
 * @query {number} page - Page number (default: 1)
 * @query {number} limit - Items per page (default: 10)
 * @query {boolean} public - Filter public/private activities
 * @returns {Object} List of activities with pagination info
 */
router.get('/', authMiddleware, activityController.listActivities);

/**
 * @route GET /api/activities/:activityId
 * @description Get detailed information about a specific activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @returns {Object} Activity details with user, location, and stats
 */
router.get('/:activityId', authMiddleware, activityController.getActivity);

/**
 * @route POST /api/activities
 * @description Create a new activity
 * @auth Required
 * @body {CreateActivityDto} Activity data (type, startTime, endTime, distance, etc.)
 * @returns {Object} Created activity data
 */
router.post('/', authMiddleware, activityController.createActivity);

/**
 * @route PATCH /api/activities/:activityId
 * @description Update an existing activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @body {UpdateActivityDto} Fields to update
 * @returns {Object} Updated activity data
 */
router.patch('/:activityId', authMiddleware, activityController.updateActivity);

/**
 * @route DELETE /api/activities/:activityId
 * @description Delete an activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @returns {Object} Success message
 */
router.delete('/:activityId', authMiddleware, activityController.deleteActivity);

export default router; 