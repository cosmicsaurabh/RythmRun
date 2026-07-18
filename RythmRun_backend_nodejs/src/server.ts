import 'reflect-metadata';
import type { Server } from 'node:http';
import os from 'node:os';

import {
  loadAndValidateEnvironment,
  validateEmailEnvironment,
} from './config/env.js';
import type { DatabaseRuntime } from './config/database.js';
import type { ActivityImageService } from './services/activity-image.service.js';
import type { AvatarService } from './services/avatar.service.js';
import type { AuthSessionService } from './services/auth-session.service.js';

export interface StartServerOptions {
  host?: string;
  port?: number;
  retryIntervalMs?: number;
}

const cleanupByServer = new WeakMap<Server, () => Promise<void>>();

function runRetry(operation: string, retry: () => Promise<void>): void {
  try {
    void retry().catch((error: unknown) => {
      const category = error instanceof Error ? error.name : 'UnknownError';
      console.error(`${operation} retry failed (${category})`);
    });
  } catch (error: unknown) {
    const category = error instanceof Error ? error.name : 'UnknownError';
    console.error(`${operation} retry failed (${category})`);
  }
}

function logListeningAddresses(port: number): void {
  if (process.env.NODE_ENV === 'production') {
    console.log(`Server is ready and listening on port ${port}`);
    return;
  }

  const networkInterfaces = os.networkInterfaces();
  const externalAddresses: string[] = [];
  const localhostAddresses: string[] = [];

  Object.values(networkInterfaces).forEach((interfaces) => {
    interfaces?.forEach((networkInterface) => {
      const family = networkInterface.family as string | number;
      if (family !== 'IPv4' && family !== 4) {
        return;
      }

      const address = `http://${networkInterface.address}:${port}`;
      if (networkInterface.internal || networkInterface.address === '127.0.0.1') {
        localhostAddresses.push(address);
      } else {
        externalAddresses.push(address);
      }
    });
  });

  console.log(`Server running on port ${port}`);
  console.log('Server accessible at:');
  externalAddresses.forEach((address) => console.log(`  ${address} (external)`));
  localhostAddresses.forEach((address) => console.log(`  ${address}`));
  console.log(`  http://localhost:${port}`);

  const suggestedAddress = externalAddresses[0] ?? `http://localhost:${port}`;
  console.log(`For Flutter, use: ${suggestedAddress}/api`);
}

function getConfiguredPort(): number {
  const rawPort = process.env.PORT ?? '8080';
  const port = Number(rawPort);

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535');
  }

  return port;
}

function getPort(override: number | undefined): number {
  if (override === undefined) {
    return getConfiguredPort();
  }
  if (!Number.isInteger(override) || override < 0 || override > 65535) {
    throw new Error('Explicit port must be an integer between 0 and 65535');
  }
  return override;
}

function createRuntimeCleanup(
  retryTimer: NodeJS.Timeout,
  database: DatabaseRuntime,
): () => Promise<void> {
  let cleanup: Promise<void> | undefined;
  return () => {
    cleanup ??= (async () => {
      clearInterval(retryTimer);
      await database.disconnect();
    })();
    return cleanup;
  };
}

/**
 * Validates configuration before importing any module that constructs Prisma
 * or S3 consumers, then starts the HTTP listener and background retry timer.
 */
export async function startServer(
  options: StartServerOptions = {},
): Promise<Server> {
  const environment = loadAndValidateEnvironment();
  // Optional feature config; null disables email delivery without blocking boot.
  const emailConfig = validateEmailEnvironment(process.env);
  const port = getPort(options.port);
  let database: DatabaseRuntime | undefined;

  try {
    const { configureContainer, container } = await import(
      './config/container.js'
    );
    database = configureContainer(
      environment.DATABASE_URL,
      environment.GOOGLE_SERVER_CLIENT_ID,
      emailConfig,
    );

    const [
      { createApp },
      { default: userRoutes },
      { default: friendRoutes },
      { default: avatarRoutes },
      { default: activityImageRoutes },
      { default: activityRoutes },
      { default: commentRoutes },
      { default: likeRoutes },
    ] = await Promise.all([
      import('./app.js'),
      import('./routes/user.routes.js'),
      import('./routes/friend.routes.js'),
      import('./routes/avatar.routes.js'),
      import('./routes/activity-image.routes.js'),
      import('./routes/activity.routes.js'),
      import('./routes/comment.routes.js'),
      import('./routes/like.routes.js'),
    ]);

    const app = createApp({
      users: userRoutes,
      friends: friendRoutes,
      avatar: avatarRoutes,
      activityImages: activityImageRoutes,
      activities: activityRoutes,
      comments: commentRoutes,
      likes: likeRoutes,
    });

    let server!: Server;
    await new Promise<void>((resolve, reject) => {
      const onListening = (error?: Error): void => {
        if (error !== undefined) {
          reject(error);
          return;
        }
        resolve();
      };

      server =
        options.host === undefined
          ? app.listen(port, onListening)
          : app.listen(port, options.host, onListening);
    });

    const retryTimer = setInterval(() => {
      runRetry('Activity image delete', () =>
        container
          .resolve<ActivityImageService>('ActivityImageService')
          .retryPendingDeletes(),
      );
      runRetry('Avatar cleanup', () =>
        container.resolve<AvatarService>('AvatarService').retryPendingCleanup(),
      );
      runRetry('Expired auth session cleanup', () =>
        container
          .resolve<AuthSessionService>('AuthSessionService')
          .purgeExpiredSessions()
          .then(() => undefined),
      );
    }, options.retryIntervalMs ?? 15 * 60 * 1000);
    retryTimer.unref();

    const cleanup = createRuntimeCleanup(retryTimer, database);
    cleanupByServer.set(server, cleanup);
    server.once('close', () => {
      void cleanup().catch((error: unknown) => {
        const category = error instanceof Error ? error.name : 'UnknownError';
        console.error(`Server cleanup failed (${category})`);
      });
    });
    server.once('error', () => {
      void cleanup().catch(() => undefined);
    });
    const address = server.address();
    const listeningPort =
      address !== null && typeof address === 'object' ? address.port : port;
    logListeningAddresses(listeningPort);
    return server;
  } catch (error: unknown) {
    await database?.disconnect();
    throw error;
  }
}

export async function stopServer(server: Server): Promise<void> {
  const cleanup = cleanupByServer.get(server);
  try {
    if (server.listening) {
      await new Promise<void>((resolve, reject) => {
        server.close(error => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    }
  } finally {
    await cleanup?.();
  }
}
