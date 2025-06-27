import type { Request, Response } from 'express';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { UserController } from './controllers/user.controller';
import { ActivityController } from './controllers/activity.controller';
import { CommentController } from './controllers/comment.controller';
import { authMiddleware, refreshTokenMiddleware } from './middleware/auth.middleware';

dotenv.config();

const app = express();

// Middleware
app.use(express.json());
app.use(cors());
app.use(helmet());

// Controllers
const userController = new UserController();
const activityController = new ActivityController();
const commentController = new CommentController();

// Public routes
app.post('/api/users/register', userController.register);
app.post('/api/users/login', userController.login);
app.post('/api/users/refresh-token', refreshTokenMiddleware, userController.refreshToken);

// Protected routes (require authentication)
app.post('/api/users/logout', authMiddleware, userController.logout);
app.post('/api/users/change-password', authMiddleware, userController.changePassword);
app.patch('/api/users/profile', authMiddleware, userController.updateProfile);

// Activity routes
app.get('/api/get-activities', authMiddleware, activityController.getActivities);
app.get('/api/get-activity/:id', authMiddleware, activityController.getActivityById);
app.post('/api/add-new-activity', authMiddleware, activityController.createActivity);
app.patch('/api/update-activity/:id', authMiddleware, activityController.updateActivity);
app.delete('/api/delete-activity/:id', authMiddleware, activityController.deleteActivity);

// Like/Unlike routes
app.post('/api/activities/:id/like', authMiddleware, activityController.likeActivity);
app.delete('/api/activities/:id/like', authMiddleware, activityController.unlikeActivity);

// Comment routes
app.post('/api/activities/:id/comments', authMiddleware, commentController.createComment);

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});