import 'reflect-metadata';
import type { Request, Response } from 'express';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { ActivityController } from './controllers/activity.controller';
import { CommentController } from './controllers/comment.controller';
import { LikeController } from './controllers/like.controller';
import { FriendController } from './controllers/friend.controller';
import { authMiddleware } from './middleware/auth.middleware';
import { container } from './config/container';
import userRoutes from './routes/user.routes';

dotenv.config();

const app = express();

// Middleware
app.use(express.json());
app.use(cors());
app.use(helmet());

// Controllers
const activityController = container.resolve(ActivityController);
const commentController = container.resolve(CommentController);
const likeController = container.resolve(LikeController);
const friendController = container.resolve(FriendController);

// Routes
app.use('/api/users', userRoutes);

// Activity routes
app.get('/api/activities', authMiddleware, activityController.listActivities);
app.get('/api/activities/:activityId', authMiddleware, activityController.getActivity);
app.post('/api/activities', authMiddleware, activityController.createActivity);
app.patch('/api/activities/:activityId', authMiddleware, activityController.updateActivity);
app.delete('/api/activities/:activityId', authMiddleware, activityController.deleteActivity);

// Like routes
app.get('/api/activities/:activityId/like', authMiddleware, likeController.getLikeStatus);
app.post('/api/activities/:activityId/like', authMiddleware, likeController.likeActivity);
app.delete('/api/activities/:activityId/like', authMiddleware, likeController.unlikeActivity);

// Comment routes
app.get('/api/activities/:activityId/comments', authMiddleware, commentController.getComments);
app.get('/api/activities/:activityId/comments/:commentId', authMiddleware, commentController.getComment);
app.post('/api/activities/:activityId/comments', authMiddleware, commentController.createComment);
app.patch('/api/activities/:activityId/comments/:commentId', authMiddleware, commentController.updateComment);
app.delete('/api/activities/:activityId/comments/:commentId', authMiddleware, commentController.deleteComment);

// Friend routes
app.post('/api/friends/requests', authMiddleware, friendController.createFriendRequest);
app.delete('/api/friends/requests/:requestId', authMiddleware, friendController.deleteFriendRequest);
app.post('/api/friends/requests/:requestId/accept', authMiddleware, friendController.acceptFriendRequest);
app.post('/api/friends/requests/:requestId/reject', authMiddleware, friendController.rejectFriendRequest);
app.get('/api/friends/requests/pending', authMiddleware, friendController.getPendingFriendRequests);
app.get('/api/friends/status/:userId', authMiddleware, friendController.getFriendshipStatus);

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});