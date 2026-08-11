import 'reflect-metadata';
import { container as rootContainer } from 'tsyringe';
import { createDatabase } from './database.js';
import type { DatabaseRuntime } from './database.js';
import { UserService } from '../services/user.service.js';
import { ActivityService } from '../services/activity.service.js';
import { ActivityImageService } from '../services/activity-image.service.js';
import { CommentService } from '../services/comment.service.js';
import { LikeService } from '../services/like.service.js';
import { FriendService } from '../services/friend.service.js';
import { AvatarService } from '../services/avatar.service.js';
import { AuthSessionService } from '../services/auth-session.service.js';
import { GoogleAuthService } from '../services/google-auth.service.js';
import { createEmailSender } from '../services/email.service.js';
import type { AuthTimingEnvironment, EmailEnvironment } from './env.js';
import s3Service from '../services/s3.service.js';

export const container = rootContainer.createChildContainer();
let configured = false;

export function configureContainer(
  databaseUrl: string,
  googleServerClientId: string,
  authTiming: AuthTimingEnvironment,
  emailConfig: EmailEnvironment | null = null,
): DatabaseRuntime {
  if (configured) {
    throw new Error('Dependency container is already configured');
  }

  const database = createDatabase(databaseUrl);
  container.registerInstance('PrismaClient', database.client);
  container.registerInstance('AuthTiming', authTiming);
  container.registerInstance('S3Service', s3Service);
  container.registerInstance(
    'GoogleIdentityVerifier',
    new GoogleAuthService(googleServerClientId),
  );
  // Always registered so the DI token resolves even when email is disabled;
  // createEmailSender returns a no-op sender for a null config.
  container.registerInstance('EmailSender', createEmailSender(emailConfig));

  container.register('AuthSessionService', { useClass: AuthSessionService });
  container.register('UserService', { useClass: UserService });
  container.register('ActivityService', { useClass: ActivityService });
  container.register('ActivityImageService', {
    useClass: ActivityImageService,
  });
  container.register('CommentService', { useClass: CommentService });
  container.register('LikeService', { useClass: LikeService });
  container.register('FriendService', { useClass: FriendService });
  container.register('AvatarService', { useClass: AvatarService });

  configured = true;
  return database;
}
