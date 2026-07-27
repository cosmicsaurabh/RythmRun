import type { CorsOptions } from 'cors';
import type { Request, Response, Router } from 'express';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';

import { requestContextMiddleware } from './middleware/request-context.middleware.js';

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

export interface ApplicationOptions {
  /**
   * Exact browser origins permitted to read responses. Empty means no
   * cross-origin browser access, which is the safe default — mobile clients
   * send no `Origin` and are unaffected either way.
   */
  allowedOrigins?: readonly string[];
  /** Proxy hops in front of this process; see TRUST_PROXY_HOPS. */
  trustProxyHops?: number;
}

/**
 * Builds the CORS policy from an exact-match allowlist (IP-2.6 item 1).
 *
 * Credentials stay off: the API authenticates with a bearer token rather than
 * a cookie, so no response ever needs `Access-Control-Allow-Credentials`, and
 * leaving it off makes the wildcard-with-credentials mistake unreachable.
 * CORS constrains browsers only — it is not an authentication substitute.
 */
export function createCorsOptions(
  allowedOrigins: readonly string[],
): CorsOptions {
  const allowlist = new Set(allowedOrigins);

  return {
    origin(origin, callback) {
      // No Origin header: a non-browser client (the mobile app, curl, a health
      // probe). CORS has nothing to decide, so reflect nothing and let the
      // request through to authentication.
      if (origin === undefined) {
        callback(null, false);
        return;
      }
      callback(null, allowlist.has(origin));
    },
    credentials: false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    maxAge: 600,
  };
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
export function createApp(
  routes: ApplicationRoutes,
  options: ApplicationOptions = {},
) {
  const app = express();

  // Must match the real deployment. Too high and a client can forge
  // X-Forwarded-For to pick its own rate-limit key; 0 ignores the header.
  app.set('trust proxy', options.trustProxyHops ?? 0);

  app.use(requestContextMiddleware);
  app.use(cors(createCorsOptions(options.allowedOrigins ?? [])));
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
