import type { Request, Response } from 'express';
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const dotenv = require('dotenv');
const { UserController } = require('./controllers/user.controller');
const { ActivityController } = require('./controllers/activity.controller');
const { authMiddleware, refreshTokenMiddleware } = require('./middleware/auth.middleware');

dotenv.config();

const app = express();

// Middleware
app.use(express.json());
app.use(cors());
app.use(helmet());

// Controllers
const userController = new UserController();
const activityController = new ActivityController();

// Public routes
app.post('/api/users/register', userController.register);
app.post('/api/users/login', userController.login);
app.post('/api/users/refresh-token', refreshTokenMiddleware, userController.refreshToken);

// Protected routes (require authentication)
app.post('/api/users/logout', authMiddleware, userController.logout);
app.post('/api/users/change-password', authMiddleware, userController.changePassword);
app.patch('/api/users/profile', authMiddleware, userController.updateProfile);

// Activity routes
app.get('/api/activities', authMiddleware, activityController.getActivities);

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});