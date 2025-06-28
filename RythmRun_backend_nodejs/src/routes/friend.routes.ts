import { Router } from 'express';
import { container } from '../config/container';
import { FriendController } from '../controllers/friend.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();
const friendController = container.resolve(FriendController);

/**
 * Friend Request Routes
 * @route POST /api/friends/requests
 * @description Send a friend request to another user
 * @auth Required
 * @body {SendFriendRequestDto} targetUserId - ID of user to send request to
 * @returns {Object} Created friend request data
 */
router.post('/requests', authMiddleware, friendController.createFriendRequest);

/**
 * @route DELETE /api/friends/requests/:requestId
 * @description Cancel a sent friend request
 * @auth Required
 * @param {number} requestId - Friend request ID
 * @returns {Object} Success message
 */
router.delete('/requests/:requestId', authMiddleware, friendController.deleteFriendRequest);

/**
 * @route POST /api/friends/requests/:requestId/accept
 * @description Accept a received friend request
 * @auth Required
 * @param {number} requestId - Friend request ID
 * @returns {Object} Updated friend request data
 */
router.post('/requests/:requestId/accept', authMiddleware, friendController.acceptFriendRequest);

/**
 * @route POST /api/friends/requests/:requestId/reject
 * @description Reject a received friend request
 * @auth Required
 * @param {number} requestId - Friend request ID
 * @returns {Object} Success message
 */
router.post('/requests/:requestId/reject', authMiddleware, friendController.rejectFriendRequest);

/**
 * @route GET /api/friends/requests/pending
 * @description Get list of pending friend requests
 * @auth Required
 * @returns {Object[]} List of pending friend requests
 */
router.get('/requests/pending', authMiddleware, friendController.getPendingFriendRequests);

/**
 * @route GET /api/friends/status/:userId
 * @description Get friendship status with another user
 * @auth Required
 * @param {number} userId - User ID to check status with
 * @returns {Object} Friendship status and details
 */
router.get('/status/:userId', authMiddleware, friendController.getFriendshipStatus);

export default router; 