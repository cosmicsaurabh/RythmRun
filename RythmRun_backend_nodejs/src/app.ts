import 'reflect-metadata';
import type { Request, Response } from 'express';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { container } from './config/container';
import userRoutes from './routes/user.routes';
import activityRoutes from './routes/activity.routes';
import commentRoutes from './routes/comment.routes';
import likeRoutes from './routes/like.routes';
import friendRoutes from './routes/friend.routes';

dotenv.config();

const app = express();

// Middleware
app.use(express.json());
app.use(cors());
app.use(helmet());

// Routes
app.use('/api/users', userRoutes);
app.use('/api/friends', friendRoutes);

// Simple direct routes instead of nested router
app.use('/api/activities', activityRoutes);
app.use('/api/activities/:activityId/comments', commentRoutes);
app.use('/api/activities/:activityId/likes', likeRoutes);

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});