import 'reflect-metadata';
import type { Server } from 'http';
import type { ActivityImageService } from './services/activity-image.service';
import type { AvatarService } from './services/avatar.service';
import os from 'os';
import { loadAndValidateEnvironment } from './config/env';

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

function getPort(): number {
  const rawPort = process.env.PORT ?? '8080';
  const port = Number(rawPort);

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535');
  }

  return port;
}

/**
 * Validates configuration before importing any module that constructs Prisma
 * or S3 consumers, then starts the HTTP listener and background retry timer.
 */
export async function startServer(): Promise<Server> {
  loadAndValidateEnvironment();
  const port = getPort();

  const [
    { createApp },
    { container },
    { default: userRoutes },
    { default: friendRoutes },
    { default: avatarRoutes },
    { default: activityImageRoutes },
    { default: activityRoutes },
    { default: commentRoutes },
    { default: likeRoutes },
  ] = await Promise.all([
    import('./app'),
    import('./config/container'),
    import('./routes/user.routes'),
    import('./routes/friend.routes'),
    import('./routes/avatar.routes'),
    import('./routes/activity-image.routes'),
    import('./routes/activity.routes'),
    import('./routes/comment.routes'),
    import('./routes/like.routes'),
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

  const retryTimer = setInterval(() => {
    runRetry('Activity image delete', () =>
      container
        .resolve<ActivityImageService>('ActivityImageService')
        .retryPendingDeletes(),
    );
    runRetry('Avatar cleanup', () =>
      container.resolve<AvatarService>('AvatarService').retryPendingCleanup(),
    );
  }, 15 * 60 * 1000);
  retryTimer.unref();

  const server = app.listen(port, () => logListeningAddresses(port));
  server.on('close', () => clearInterval(retryTimer));
  return server;
}

if (require.main === module) {
  startServer().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : 'Unknown startup error';
    console.error(`Server startup failed: ${message}`);
    process.exitCode = 1;
  });
}
