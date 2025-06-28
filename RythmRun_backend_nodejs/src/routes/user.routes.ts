import { Router } from 'express';
import { container } from '../config/container';
import { UserController } from '../controllers/user.controller';
import { authMiddleware } from '../middleware/auth.middleware';
import { uploadSingleFile } from '../middleware/file-upload.middleware';

const router = Router();
const userController = container.resolve(UserController);

// Auth routes
router.post('/register', userController.register);
router.post('/login', userController.login);
router.post('/logout', authMiddleware, userController.logout);
router.post('/refresh-token', authMiddleware, userController.refreshToken);

// Profile routes
router.put('/profile', authMiddleware, userController.updateProfile);
router.put('/change-password', authMiddleware, userController.changePassword);

// Profile picture routes
router.post(
    '/profile-picture',
    authMiddleware,
    uploadSingleFile('profilePicture'),
    userController.uploadProfilePicture
);
router.get('/profile-picture/:id', userController.getProfilePicture);

export default router; 