import { Router } from 'express';
import { container } from '../config/container';
import { UserController } from '../controllers/user.controller';
import { authMiddleware } from '../middleware/auth.middleware';
import { uploadSingleFile } from '../middleware/file-upload.middleware';

const router = Router();
const userController = container.resolve(UserController);

/**
 * Authentication Routes
 * @route POST /api/users/register
 * @description Register a new user
 * @body {RegisterUserDto} - username, password, firstname (optional), lastname (optional)
 * @returns {Object} User data with access and refresh tokens
 */
router.post('/register', userController.register);

/**
 * @route POST /api/users/login
 * @description Authenticate user and get tokens
 * @body {LoginUserDto} - username, password
 * @returns {Object} User data with access and refresh tokens
 */
router.post('/login', userController.login);

/**
 * @route POST /api/users/logout
 * @description Logout user and invalidate refresh token
 * @auth Required
 * @returns {Object} Success message
 */
router.post('/logout', authMiddleware, userController.logout);

/**
 * @route POST /api/users/refresh-token
 * @description Get new access token using refresh token
 * @auth Required
 * @body {string} refreshToken
 * @returns {Object} New access and refresh tokens
 */
router.post('/refresh-token', authMiddleware, userController.refreshToken);

/**
 * Profile Management Routes
 * @route PUT /api/users/profile
 * @description Update user profile information
 * @auth Required
 * @body {UpdateProfileDto} - firstname, lastname
 * @returns {Object} Updated user data
 */
router.put('/profile', authMiddleware, userController.updateProfile);

/**
 * @route PUT /api/users/change-password
 * @description Change user password
 * @auth Required
 * @body {ChangePasswordDto} - currentPassword, newPassword
 * @returns {Object} Success message
 */
router.put('/change-password', authMiddleware, userController.changePassword);

/**
 * Profile Picture Routes
 * @route POST /api/users/profile-picture
 * @description Upload or update user profile picture
 * @auth Required
 * @body {FormData} profilePicture - Image file (JPEG, PNG, GIF, max 10MB)
 * @returns {Object} Success message with filename
 */
router.post(
    '/profile-picture',
    authMiddleware,
    uploadSingleFile('profilePicture'),
    userController.uploadProfilePicture
);

/**
 * @route GET /api/users/profile-picture/:id
 * @description Get user's profile picture
 * @param {number} id - User ID
 * @returns {File} Profile picture file
 */
router.get('/profile-picture/:id', userController.getProfilePicture);

export default router; 