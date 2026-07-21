import type { Request, Response, Router } from 'express';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';

export const DEFAULT_JSON_LIMIT_BYTES = 100 * 1024;

export interface ApplicationRoutes {
  users: Router;
  friends: Router;
  avatar: Router;
  activityImages: Router;
  activities: Router;
  comments: Router;
  likes: Router;
}

function usesActivityMutationParser(req: Request): boolean {
  if (req.method === 'POST') {
    return /^\/api\/activities\/?$/i.test(req.path);
  }

  return req.method === 'PATCH' &&
    /^\/api\/activities\/[^/]+\/?$/i.test(req.path);
}

/**
 * Constructs the HTTP application without loading configuration, creating
 * infrastructure clients, starting timers, or opening a network listener.
 */
export function createApp(routes: ApplicationRoutes) {
  const app = express();

  app.use(cors());
  app.use(helmet());

  const ordinaryJsonParser = express.json({ limit: DEFAULT_JSON_LIMIT_BYTES });
  app.use((req: Request, res: Response, next) => {
    // These two mutation shapes authenticate and parse inside the activity
    // router. Every other method/path retains the ordinary 100 KiB parser.
    if (usesActivityMutationParser(req)) {
      next();
      return;
    }

    ordinaryJsonParser(req, res, next);
  });

  app.use('/api/users', routes.users);
  app.use('/api/avatar', routes.avatar);
  app.use('/api/activities/:activityId/images', routes.activityImages);
  app.use('/api/activities', routes.activities);

  // IP-2.5 / D-007: the friend, comment, and like routers are intentionally
  // NOT mounted. Social features stay disabled (requests fall through to 404)
  // until authentication, privacy, route visibility, moderation, and
  // blocking/reporting exist. The routers/services remain in the tree
  // (`routes.friends`, `routes.comments`, `routes.likes`) for future re-enable;
  // do not remount them merely to expose an unsupported product journey.

  app.get('/health', (_req: Request, res: Response) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  });

  return app;
}
