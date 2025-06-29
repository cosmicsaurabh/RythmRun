import { Router } from 'express';
import { container } from '../config/container';
import { CommentController } from '../controllers/comment.controller';
import { authMiddleware } from '../middleware/auth.middleware';

// Simple router without mergeParams
const router = Router();
const commentController = container.resolve(CommentController);

/**
 * Comment Routes
 * @route GET /api/activities/:activityId/comments
 * @description Get all comments for an activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @returns {Object[]} List of comments with user info
 */
router.get('/', authMiddleware, commentController.getComments);

/**
 * @route GET /api/activities/:activityId/comments/:commentId
 * @description Get a specific comment
 * @auth Required
 * @param {number} activityId - Activity ID
 * @param {number} commentId - Comment ID
 * @returns {Object} Comment details with user info
 */
router.get('/:commentId', authMiddleware, commentController.getComment);

/**
 * @route POST /api/activities/:activityId/comments
 * @description Create a new comment on an activity
 * @auth Required
 * @param {number} activityId - Activity ID
 * @body {CreateCommentDto} Comment data
 * @returns {Object} Created comment data
 */
router.post('/', authMiddleware, commentController.createComment);

/**
 * @route PATCH /api/activities/:activityId/comments/:commentId
 * @description Update an existing comment
 * @auth Required
 * @param {number} activityId - Activity ID
 * @param {number} commentId - Comment ID
 * @body {CreateCommentDto} Updated comment data
 * @returns {Object} Updated comment data
 */
router.patch('/:commentId', authMiddleware, commentController.updateComment);

/**
 * @route DELETE /api/activities/:activityId/comments/:commentId
 * @description Delete a comment
 * @auth Required
 * @param {number} activityId - Activity ID
 * @param {number} commentId - Comment ID
 * @returns {Object} Success message
 */
router.delete('/:commentId', authMiddleware, commentController.deleteComment);

export default router; 