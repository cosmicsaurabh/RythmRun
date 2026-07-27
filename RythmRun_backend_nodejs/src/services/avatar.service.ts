import { randomUUID } from 'crypto';
import { inject, injectable } from 'tsyringe';
import { Prisma, type PrismaClient } from '../generated/prisma/client.js';
import {
  AVATAR_CONTENT_TYPES,
  ConfirmAvatarUploadDto,
  MAX_AVATAR_SIZE_BYTES,
  RequestAvatarUploadDto,
} from '../models/dto/avatar.dto.js';
import { S3Service } from './s3.service.js';

export const AVATAR_UPLOAD_INTENT_TTL_MS = 5 * 60 * 1000;
export const AVATAR_UPLOAD_RATE_WINDOW_MS = 60 * 60 * 1000;
export const MAX_PENDING_AVATAR_UPLOADS = 2;
export const MAX_AVATAR_UPLOAD_REQUESTS_PER_WINDOW = 10;

const EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const ACCEPTED_INPUT_EXTENSIONS: Record<string, ReadonlySet<string>> = {
  'image/jpeg': new Set(['jpg', 'jpeg']),
  'image/png': new Set(['png']),
  'image/webp': new Set(['webp']),
};

const AVATAR_UUID_PATTERN =
  '[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}';

export class AvatarServiceError extends Error {
  constructor(
    message: string,
    readonly statusCode: number = 400,
  ) {
    super(message);
    this.name = 'AvatarServiceError';
    Object.setPrototypeOf(this, AvatarServiceError.prototype);
  }
}

class AvatarIntentUnavailableError extends Error {
  constructor() {
    super('Avatar upload intent is unavailable');
    this.name = 'AvatarIntentUnavailableError';
    Object.setPrototypeOf(this, AvatarIntentUnavailableError.prototype);
  }
}

@injectable()
export class AvatarService {
  constructor(
    @inject('PrismaClient') private prisma: PrismaClient,
    @inject('S3Service') private s3: S3Service,
  ) {}

  async requestUpload(userId: number, dto: RequestAvatarUploadDto) {
    this.validateUploadRequest(dto);
    await this.retryPendingCleanup(userId).catch(error => {
      this.logErrorCategory('Avatar cleanup retry query failed', error);
    });

    const now = new Date();
    const expiresAt = new Date(now.getTime() + AVATAR_UPLOAD_INTENT_TTL_MS);
    const extension = EXTENSION_BY_CONTENT_TYPE[dto.contentType];
    const key = `avatars/${userId}/${randomUUID()}.${extension}`;

    const intent = await this.createIntentWithinLimits({
      userId,
      key,
      contentType: dto.contentType,
      sizeBytes: dto.sizeBytes,
      expiresAt,
      now,
    });

    try {
      const authorization = await this.s3.getPresignedAvatarPutUrl({
        key: intent.key,
        contentType: intent.contentType,
        sizeBytes: intent.sizeBytes,
        expiresSeconds: AVATAR_UPLOAD_INTENT_TTL_MS / 1000,
      });

      return {
        uploadUrl: authorization.uploadUrl,
        uploadMethod: 'PUT' as const,
        requiredHeaders: {
          'Content-Type': intent.contentType,
          'Content-Length': intent.sizeBytes.toString(),
        },
        key: intent.key,
        expiresAt: intent.expiresAt.toISOString(),
      };
    } catch (error) {
      await this.prisma.avatarUploadIntent
        .delete({ where: { id: intent.id } })
        .catch(() => undefined);
      throw error;
    }
  }

  async confirmUpload(userId: number, dto: ConfirmAvatarUploadDto) {
    this.assertSupportedContentType(dto.contentType);
    this.assertKeyBelongsToUser(dto.key, userId, dto.contentType);

    const intent = await this.prisma.avatarUploadIntent.findUnique({
      where: { key: dto.key },
    });

    if (
      !intent ||
      intent.userId !== userId ||
      intent.contentType !== dto.contentType
    ) {
      throw new AvatarServiceError('Invalid avatar upload intent');
    }

    if (intent.consumedAt) {
      const idempotentResult = await this.getIdempotentConfirmation(
        userId,
        intent.key,
        intent.contentType,
      );

      if (idempotentResult) {
        return idempotentResult;
      }

      throw new AvatarServiceError(
        'Avatar upload intent has already been consumed',
        409,
      );
    }

    const now = new Date();
    if (intent.expiresAt <= now) {
      await this.queueIntentCleanup(intent.id, userId, intent.key, now);
      throw new AvatarServiceError('Avatar upload intent has expired', 410);
    }

    const uploadedObject = await this.getUploadedObjectMetadata(intent.key);
    if (
      uploadedObject.ContentType !== intent.contentType ||
      uploadedObject.ContentLength !== intent.sizeBytes
    ) {
      await this.queueIntentCleanup(intent.id, userId, intent.key, new Date());
      throw new AvatarServiceError('Uploaded avatar metadata does not match');
    }

    const commitNow = new Date();
    if (intent.expiresAt <= commitNow) {
      await this.queueIntentCleanup(intent.id, userId, intent.key, commitNow);
      throw new AvatarServiceError('Avatar upload intent has expired', 410);
    }

    let previousKey: string | null = null;

    try {
      previousKey = await this.prisma.$transaction(async transaction => {
        const currentUser = await transaction.user.findUnique({
          where: { id: userId },
          select: {
            profilePicturePath: true,
          },
        });

        if (!currentUser) {
          throw new AvatarServiceError('User not found', 404);
        }

        const cleanupKey =
          currentUser.profilePicturePath &&
          currentUser.profilePicturePath !== intent.key &&
          this.isKeyOwnedByUser(currentUser.profilePicturePath, userId)
            ? currentUser.profilePicturePath
            : null;

        const consumed = await transaction.avatarUploadIntent.updateMany({
          where: {
            id: intent.id,
            userId,
            key: intent.key,
            contentType: intent.contentType,
            sizeBytes: intent.sizeBytes,
            consumedAt: null,
            expiresAt: { gt: commitNow },
          },
          data: {
            consumedAt: commitNow,
            cleanupKey,
          },
        });

        if (consumed.count !== 1) {
          throw new AvatarIntentUnavailableError();
        }

        await transaction.user.update({
          where: { id: userId },
          data: {
            profilePicturePath: intent.key,
            profilePictureType: intent.contentType,
          },
        });

        return cleanupKey;
      });
    } catch (error) {
      if (error instanceof AvatarIntentUnavailableError) {
        const idempotentResult = await this.getIdempotentConfirmation(
          userId,
          intent.key,
          intent.contentType,
        );

        if (idempotentResult) {
          return idempotentResult;
        }

        throw new AvatarServiceError(
          'Avatar upload intent is no longer available',
          409,
        );
      }

      throw error;
    }

    if (previousKey) {
      await this.attemptIntentCleanup(intent.id, userId, previousKey);
    }

    return {
      key: intent.key,
      contentType: intent.contentType,
      alreadyConfirmed: false,
    };
  }

  async getReadUrl(userId: number) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { profilePicturePath: true },
    });
    const key = user?.profilePicturePath;

    if (!key || !this.isKeyOwnedByUser(key, userId)) {
      throw new AvatarServiceError('Avatar not found', 404);
    }

    try {
      const readUrl = await this.s3.getAvatarReadUrl(key);
      return {
        key,
        ...readUrl,
      };
    } catch {
      throw new AvatarServiceError(
        'Avatar storage is temporarily unavailable',
        503,
      );
    }
  }

  private async createIntentWithinLimits(input: {
    userId: number;
    key: string;
    contentType: string;
    sizeBytes: number;
    expiresAt: Date;
    now: Date;
  }) {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(
          async transaction => {
            const rateWindowStartedAt = new Date(
              input.now.getTime() - AVATAR_UPLOAD_RATE_WINDOW_MS,
            );
            const requestCount = await transaction.avatarUploadIntent.count({
              where: {
                userId: input.userId,
                createdAt: { gte: rateWindowStartedAt },
              },
            });

            if (requestCount >= MAX_AVATAR_UPLOAD_REQUESTS_PER_WINDOW) {
              throw new AvatarServiceError(
                'Avatar upload rate limit exceeded',
                429,
              );
            }

            const pendingCount = await transaction.avatarUploadIntent.count({
              where: {
                userId: input.userId,
                consumedAt: null,
                expiresAt: { gt: input.now },
              },
            });

            if (pendingCount >= MAX_PENDING_AVATAR_UPLOADS) {
              throw new AvatarServiceError(
                'Too many pending avatar uploads',
                429,
              );
            }

            return transaction.avatarUploadIntent.create({
              data: {
                userId: input.userId,
                key: input.key,
                contentType: input.contentType,
                sizeBytes: input.sizeBytes,
                expiresAt: input.expiresAt,
              },
            });
          },
          { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
        );
      } catch (error) {
        if (this.isSerializationFailure(error) && attempt < 2) {
          continue;
        }

        if (this.isSerializationFailure(error)) {
          throw new AvatarServiceError(
            'Avatar upload is temporarily unavailable',
            503,
          );
        }

        throw error;
      }
    }

    throw new AvatarServiceError('Avatar upload is temporarily unavailable', 503);
  }

  private validateUploadRequest(dto: RequestAvatarUploadDto) {
    this.assertSupportedContentType(dto.contentType);

    if (
      !Number.isInteger(dto.sizeBytes) ||
      dto.sizeBytes < 1 ||
      dto.sizeBytes > MAX_AVATAR_SIZE_BYTES
    ) {
      throw new AvatarServiceError('Invalid avatar size');
    }

    if (dto.ext !== undefined) {
      const acceptedExtensions = ACCEPTED_INPUT_EXTENSIONS[dto.contentType];
      if (!acceptedExtensions.has(dto.ext.toLowerCase())) {
        throw new AvatarServiceError(
          'Avatar extension does not match content type',
        );
      }
    }
  }

  private assertSupportedContentType(contentType: string) {
    if (!AVATAR_CONTENT_TYPES.includes(contentType as any)) {
      throw new AvatarServiceError('Unsupported avatar content type');
    }
  }

  private assertKeyBelongsToUser(
    key: string,
    userId: number,
    contentType?: string,
  ) {
    if (!this.isKeyOwnedByUser(key, userId, contentType)) {
      throw new AvatarServiceError('Invalid avatar key');
    }
  }

  private isKeyOwnedByUser(
    key: string,
    userId: number,
    contentType?: string,
  ): boolean {
    const extensions = contentType
      ? EXTENSION_BY_CONTENT_TYPE[contentType]
      : Object.values(EXTENSION_BY_CONTENT_TYPE).join('|');

    if (!extensions) {
      return false;
    }

    const pattern = new RegExp(
      `^avatars/${userId}/${AVATAR_UUID_PATTERN}\\.(${extensions})$`,
      'i',
    );
    return pattern.test(key);
  }

  private async getIdempotentConfirmation(
    userId: number,
    key: string,
    contentType: string,
  ) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        profilePicturePath: true,
        profilePictureType: true,
      },
    });

    if (
      user?.profilePicturePath === key &&
      user.profilePictureType === contentType
    ) {
      return {
        key,
        contentType,
        alreadyConfirmed: true,
      };
    }

    return null;
  }

  async retryPendingCleanup(userId?: number, limit = 25): Promise<void> {
    if (!Number.isInteger(limit) || limit < 1) {
      return;
    }

    const now = new Date();
    const expiredIntents = await this.prisma.avatarUploadIntent.findMany({
      where: {
        ...(userId === undefined ? {} : { userId }),
        consumedAt: null,
        expiresAt: { lte: now },
      },
      orderBy: { expiresAt: 'asc' },
      take: limit,
    });

    for (const intent of expiredIntents) {
      await this.queueIntentCleanup(intent.id, intent.userId, intent.key, now);
    }

    const remaining = limit - expiredIntents.length;
    if (remaining < 1) {
      return;
    }

    const queuedIntents = await this.prisma.avatarUploadIntent.findMany({
      where: {
        ...(userId === undefined ? {} : { userId }),
        cleanupKey: { not: null },
        cleanupCompletedAt: null,
      },
      orderBy: { consumedAt: 'asc' },
      take: remaining,
    });

    for (const intent of queuedIntents) {
      if (intent.cleanupKey) {
        await this.attemptIntentCleanup(
          intent.id,
          intent.userId,
          intent.cleanupKey,
        );
      }
    }
  }

  private async getUploadedObjectMetadata(key: string) {
    try {
      return await this.s3.headObject(key, 'R2_BUCKET_AVATARS');
    } catch (error) {
      if (this.isMissingObjectError(error)) {
        throw new AvatarServiceError('Uploaded avatar was not found', 400);
      }

      throw new AvatarServiceError(
        'Avatar storage verification is temporarily unavailable',
        503,
      );
    }
  }

  private async queueIntentCleanup(
    intentId: string,
    userId: number,
    key: string,
    consumedAt: Date,
  ) {
    if (!this.isKeyOwnedByUser(key, userId)) {
      return;
    }

    const queued = await this.prisma.avatarUploadIntent.updateMany({
      where: {
        id: intentId,
        userId,
        key,
        consumedAt: null,
        cleanupCompletedAt: null,
      },
      data: {
        consumedAt,
        cleanupKey: key,
      },
    });

    if (queued.count === 1) {
      await this.attemptIntentCleanup(intentId, userId, key);
    }
  }

  private async attemptIntentCleanup(
    intentId: string,
    userId: number,
    key: string,
  ) {
    if (!this.isKeyOwnedByUser(key, userId)) {
      return;
    }

    try {
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { profilePicturePath: true },
      });

      // Never delete the object currently selected by the user, even if stale
      // cleanup state is present.
      if (user?.profilePicturePath === key) {
        return;
      }

      await this.s3.deleteObject(key, 'R2_BUCKET_AVATARS');
      await this.prisma.avatarUploadIntent.updateMany({
        where: {
          id: intentId,
          userId,
          cleanupKey: key,
          cleanupCompletedAt: null,
        },
        data: { cleanupCompletedAt: new Date() },
      });
    } catch (error) {
      this.logErrorCategory('Owned avatar cleanup failed', error);
    }
  }

  private isMissingObjectError(error: unknown): boolean {
    if (typeof error !== 'object' || error === null) {
      return false;
    }

    const candidate = error as {
      name?: unknown;
      code?: unknown;
      statusCode?: unknown;
      $metadata?: { httpStatusCode?: unknown };
    };
    return (
      candidate.statusCode === 404 ||
      candidate.$metadata?.httpStatusCode === 404 ||
      candidate.name === 'NotFound' ||
      candidate.name === 'NoSuchKey' ||
      candidate.code === 'NotFound' ||
      candidate.code === 'NoSuchKey'
    );
  }

  private logErrorCategory(message: string, error: unknown) {
    console.error(
      message,
      error instanceof Error ? error.name : 'UnknownError',
    );
  }

  private isSerializationFailure(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 'P2034'
    );
  }
}
