import 'reflect-metadata';
import type { Request, Response } from 'express';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import os from 'os';
import { container } from './config/container';
import userRoutes from './routes/user.routes';
import activityRoutes from './routes/activity.routes';
import commentRoutes from './routes/comment.routes';
import likeRoutes from './routes/like.routes';
import friendRoutes from './routes/friend.routes';
import avatarRoutes from './routes/avatar.routes';

dotenv.config();

const app = express();

// Middleware
app.use(express.json());
app.use(cors());
app.use(helmet());

// Routes
app.use('/api/users', userRoutes);
app.use('/api/friends', friendRoutes);
app.use('/api/avatar', avatarRoutes);

// Simple direct routes instead of nested router
app.use('/api/activities', activityRoutes);
app.use('/api/activities/:activityId/comments', commentRoutes);
app.use('/api/activities/:activityId/likes', likeRoutes);

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 8080;
const isDevelopment = process.env.NODE_ENV !== 'production';

app.listen(PORT, () => {
  console.log(`\n🚀 Server running on port ${PORT}`);
  
  // Only show detailed network info in development mode
  // In production, this could expose internal network topology
  if (isDevelopment) {
    // Get network interfaces for debug mode
    const networkInterfaces = os.networkInterfaces();
    const externalAddresses: string[] = [];
    const localhostAddresses: string[] = [];
    
    // Collect all IPv4 addresses
    Object.keys(networkInterfaces).forEach((interfaceName) => {
      const interfaces = networkInterfaces[interfaceName];
      if (interfaces) {
        interfaces.forEach((iface) => {
          // Handle both string ('IPv4') and number (4) family formats
          // TypeScript types may vary, so we check both
          const family = iface.family as string | number;
          const isIPv4 = family === 'IPv4' || family === 4;
          
          if (isIPv4) {
            const address = `http://${iface.address}:${PORT}`;
            if (iface.internal || iface.address === '127.0.0.1' || iface.address === '::1') {
              localhostAddresses.push(address);
            } else {
              externalAddresses.push(address);
            }
          }
        });
      }
    });
    
    // Print available addresses
    console.log('\n📍 Server accessible at:');
    
    // Show external addresses first (most useful for mobile devices)
    if (externalAddresses.length > 0) {
      externalAddresses.forEach((addr) => {
        console.log(`   • ${addr} (external)`);
      });
    }
    
    // Then show localhost addresses
    localhostAddresses.forEach((addr) => {
      console.log(`   • ${addr}`);
    });
    console.log(`   • http://localhost:${PORT}`);
    
    // Suggest the first external address for Flutter, or localhost if none available
    const suggestedAddress = externalAddresses.length > 0 
      ? externalAddresses[0] 
      : `http://localhost:${PORT}`;
    
    console.log(`\n💡 For Flutter app, use: ${suggestedAddress}/api`);
    console.log(`   Update app_config.dart with: 'dev': '${suggestedAddress}/api'\n`);
  } else {
    // Production mode - minimal logging for security
    console.log(`📍 Server is ready and listening on port ${PORT}\n`);
  }
});