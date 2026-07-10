import type { Request, Response, Router } from 'express';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';

export interface ApplicationRoutes {
  users: Router;
  friends: Router;
  avatar: Router;
  activityImages: Router;
  activities: Router;
  comments: Router;
  likes: Router;
}

/**
 * Constructs the HTTP application without loading configuration, creating
 * infrastructure clients, starting timers, or opening a network listener.
 */
export function createApp(routes: ApplicationRoutes) {
  const app = express();

  app.use(express.json());
  app.use(cors());
  app.use(helmet());

  app.use('/api/users', routes.users);
  app.use('/api/friends', routes.friends);
  app.use('/api/avatar', routes.avatar);
  app.use('/api/activities/:activityId/images', routes.activityImages);
  app.use('/api/activities', routes.activities);
  app.use('/api/activities/:activityId/comments', routes.comments);
  app.use('/api/activities/:activityId/likes', routes.likes);

  app.get('/health', (_req: Request, res: Response) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  });

  return app;
}
