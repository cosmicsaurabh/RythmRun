import { injectable, inject } from 'tsyringe';
import type { ActivityImage, PrismaClient } from '../generated/prisma/client.js';
import {
  activityImageLimitExceededError,
  activityNotFoundError,
  imageTooLargeError,
  invalidChecksumError,
  invalidClientImageIdError,
  invalidImageKeyError,
  tooManyPendingUploadsError,
  unsupportedContentTypeError,
  uploadedSizeMismatchError,
  userImageQuotaExceededError,
} from '../errors/activity-image.error.js';
import {
  ConfirmActivityImageUploadDto,
  RequestActivityImageUploadUrlDto,
} from '../models/dto/activity-image.dto.js';
import s3Service from './s3.service.js';

const ALLOWED_CONTENT_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);

const EXT_BY_CONTENT_TYPE: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024;
const MAX_IMAGES_PER_ACTIVITY = 10;
const MAX_IMAGES_PER_USER = 100;
const MAX_STORAGE_BYTES_PER_USER = 250 * 1024 * 1024; // 250MB
const MAX_PENDING_UPLOADS_PER_USER = 5;
const PENDING_UPLOAD_TTL_MS = 15 * 60 * 1000; // 15 minutes

@injectable()
export class ActivityImageService {
  constructor(@inject('PrismaClient') private prisma: PrismaClient) {}

  async requestUploadUrl(
    userId: number,
    activityId: number,
    dto: RequestActivityImageUploadUrlDto,
  ) {
    await this.assertOwnedActivity(userId, activityId);
    this.validateImageMetadata(dto);
    await this.cleanupAbandonedUploads(userId);

    const existing = await this.prisma.activityImage.findUnique({
      where: {
        activityId_clientImageId: {
          activityId,
          clientImageId: dto.clientImageId,
        },
      },
    });

    if (existing?.status === 'UPLOADED') {
      const response = await this.toResponse(existing);
      return {
        ...response,
        imageId: existing.id,
        alreadyUploaded: true,
      };
    }

    if (!existing) {
      // Check activity image count limit
      const activityImageCount = await this.prisma.activityImage.count({
        where: {
          activityId,
          status: 'UPLOADED',
          deletedAt: null,
        },
      });
      if (activityImageCount >= MAX_IMAGES_PER_ACTIVITY) {
        throw activityImageLimitExceededError();
      }

      // Check user image count and storage byte quota
      const userStats = await this.prisma.activityImage.aggregate({
        where: {
          userId,
          status: 'UPLOADED',
          deletedAt: null,
        },
        _count: { id: true },
        _sum: { sizeBytes: true },
      });

      if ((userStats._count.id ?? 0) >= MAX_IMAGES_PER_USER) {
        throw userImageQuotaExceededError();
      }

      if ((userStats._sum.sizeBytes ?? 0) + dto.sizeBytes > MAX_STORAGE_BYTES_PER_USER) {
        throw userImageQuotaExceededError();
      }

      // Check active pending uploads quota
      const pendingCount = await this.prisma.activityImage.count({
        where: {
          userId,
          status: 'PENDING_UPLOAD',
          createdAt: {
            gte: new Date(Date.now() - PENDING_UPLOAD_TTL_MS),
          },
        },
      });

      if (pendingCount >= MAX_PENDING_UPLOADS_PER_USER) {
        throw tooManyPendingUploadsError();
      }
    }

    const ext = EXT_BY_CONTENT_TYPE[dto.contentType];
    const key =
      existing?.s3Key ??
      `activity-images/${userId}/${activityId}/${dto.clientImageId}.${ext}`;

    const image =
      existing ??
      (await this.prisma.activityImage.create({
        data: {
          activityId,
          userId,
          clientImageId: dto.clientImageId,
          s3Key: key,
          contentType: dto.contentType,
          sizeBytes: dto.sizeBytes,
          checksumSha256: dto.checksumSha256,
          width: dto.width,
          height: dto.height,
          sortOrder: dto.sortOrder ?? 0,
          caption: dto.caption,
          status: 'PENDING_UPLOAD',
        },
      }));

    const signed = await s3Service.getPresignedPutUrl({
      key: image.s3Key,
      contentType: dto.contentType,
      sizeBytes: dto.sizeBytes,
    });

    return {
      imageId: image.id,
      clientImageId: image.clientImageId,
      key: image.s3Key,
      uploadUrl: signed.uploadUrl,
      expiresAt: new Date(Date.now() + 300 * 1000).toISOString(),
      requiredHeaders: {
        'Content-Type': dto.contentType,
        'Content-Length': dto.sizeBytes.toString(),
      },
    };
  }

  async confirmUpload(
    userId: number,
    activityId: number,
    dto: ConfirmActivityImageUploadDto,
  ) {
    await this.assertOwnedActivity(userId, activityId);
    this.validateImageMetadata(dto);
    this.assertKeyBelongsToActivity(
      dto.key,
      userId,
      activityId,
      dto.clientImageId,
    );

    const head = await s3Service.headObject(dto.key);

    if (head.ContentType && head.ContentType !== dto.contentType) {
      await this.tryDeleteObjectAndMarkDeleted(0, dto.key).catch(() => undefined);
      throw unsupportedContentTypeError();
    }

    if (head.ContentLength !== undefined && head.ContentLength !== dto.sizeBytes) {
      await this.tryDeleteObjectAndMarkDeleted(0, dto.key).catch(() => undefined);
      throw uploadedSizeMismatchError();
    }

    if (head.ContentLength !== undefined && head.ContentLength > MAX_IMAGE_SIZE_BYTES) {
      await this.tryDeleteObjectAndMarkDeleted(0, dto.key).catch(() => undefined);
      throw imageTooLargeError();
    }

    if (dto.checksumSha256) {
      const s3Checksum = (head as any).ChecksumSHA256 ?? (head.ETag ? head.ETag.replace(/"/g, '') : null);
      if (s3Checksum && s3Checksum.length === 64 && s3Checksum.toLowerCase() !== dto.checksumSha256.toLowerCase()) {
        await this.tryDeleteObjectAndMarkDeleted(0, dto.key).catch(() => undefined);
        throw invalidChecksumError();
      }
    }

    const image = await this.prisma.activityImage.upsert({
      where: {
        activityId_clientImageId: {
          activityId,
          clientImageId: dto.clientImageId,
        },
      },
      create: {
        activityId,
        userId,
        clientImageId: dto.clientImageId,
        s3Key: dto.key,
        contentType: dto.contentType,
        sizeBytes: dto.sizeBytes,
        checksumSha256: dto.checksumSha256,
        width: dto.width,
        height: dto.height,
        sortOrder: dto.sortOrder ?? 0,
        caption: dto.caption,
        status: 'UPLOADED',
        uploadedAt: new Date(),
      },
      update: {
        contentType: dto.contentType,
        sizeBytes: dto.sizeBytes,
        checksumSha256: dto.checksumSha256,
        width: dto.width,
        height: dto.height,
        sortOrder: dto.sortOrder ?? 0,
        caption: dto.caption,
        status: 'UPLOADED',
        uploadedAt: new Date(),
        deletedAt: null,
      },
    });

    return await this.toResponse(image);
  }

  async listImages(userId: number, activityId: number) {
    await this.assertOwnedActivity(userId, activityId);

    const images = await this.prisma.activityImage.findMany({
      where: {
        activityId,
        userId,
        status: 'UPLOADED',
        deletedAt: null,
      },
      orderBy: {
        sortOrder: 'asc',
      },
    });

    return Promise.all(images.map((image) => this.toResponse(image)));
  }

  async deleteImage(userId: number, activityId: number, imageId: number) {
    await this.assertOwnedActivity(userId, activityId);

    const image = await this.prisma.activityImage.findFirst({
      where: { id: imageId, activityId, userId },
    });

    if (!image || image.status === 'DELETED') {
      return { message: 'Image deleted successfully' };
    }

    await this.prisma.activityImage.update({
      where: { id: image.id },
      data: {
        status: 'DELETE_PENDING',
        deletedAt: new Date(),
      },
    });

    await this.tryDeleteObjectAndMarkDeleted(image.id, image.s3Key);

    return { message: 'Image deleted successfully' };
  }

  async retryPendingDeletes(limit = 25) {
    const pendingDeletes = await this.prisma.activityImage.findMany({
      where: { status: 'DELETE_PENDING' },
      orderBy: { updatedAt: 'asc' },
      take: limit,
    });

    for (const image of pendingDeletes) {
      await this.tryDeleteObjectAndMarkDeleted(image.id, image.s3Key);
    }
  }

  async cleanupAbandonedUploads(userId?: number) {
    const cutoff = new Date(Date.now() - PENDING_UPLOAD_TTL_MS);
    const stalePending = await this.prisma.activityImage.findMany({
      where: {
        status: 'PENDING_UPLOAD',
        createdAt: { lt: cutoff },
        ...(userId !== undefined ? { userId } : {}),
      },
      take: 50,
    });

    for (const image of stalePending) {
      await this.tryDeleteObjectAndMarkDeleted(image.id, image.s3Key);
    }
  }

  private async assertOwnedActivity(userId: number, activityId: number) {
    const activity = await this.prisma.activity.findFirst({
      where: { id: activityId, userId },
    });

    if (!activity) {
      throw activityNotFoundError();
    }

    return activity;
  }

  private validateImageMetadata(dto: RequestActivityImageUploadUrlDto) {
    if (!ALLOWED_CONTENT_TYPES.has(dto.contentType)) {
      throw unsupportedContentTypeError();
    }

    if (dto.sizeBytes > MAX_IMAGE_SIZE_BYTES) {
      throw imageTooLargeError();
    }

    if (!/^[A-Za-z0-9_-]{8,160}$/.test(dto.clientImageId)) {
      throw invalidClientImageIdError();
    }

    if (
      dto.checksumSha256 &&
      !/^[a-fA-F0-9]{64}$/.test(dto.checksumSha256)
    ) {
      throw invalidChecksumError();
    }
  }

  private assertKeyBelongsToActivity(
    key: string,
    userId: number,
    activityId: number,
    clientImageId: string,
  ) {
    const allowedExtensions = Object.values(EXT_BY_CONTENT_TYPE).join('|');
    const pattern = new RegExp(
      `^activity-images/${userId}/${activityId}/${clientImageId}\\.(${allowedExtensions})$`,
    );

    if (!pattern.test(key)) {
      throw invalidImageKeyError();
    }
  }

  private async tryDeleteObjectAndMarkDeleted(imageId: number, s3Key: string) {
    try {
      await s3Service.deleteObject(s3Key);
      if (imageId > 0) {
        await this.prisma.activityImage.update({
          where: { id: imageId },
          data: {
            status: 'DELETED',
            deletedAt: new Date(),
          },
        });
      }
    } catch (error) {
      console.error('Failed to delete activity image object:', error);
      if (imageId > 0) {
        await this.prisma.activityImage.update({
          where: { id: imageId },
          data: {
            status: 'DELETE_PENDING',
          },
        });
      }
    }
  }

  private async toResponse(image: ActivityImage) {
    const readUrl = await s3Service.getActivityImageReadUrl(image.s3Key);

    return {
      id: image.id,
      activityId: image.activityId,
      clientImageId: image.clientImageId,
      key: image.s3Key,
      url: readUrl.url,
      urlExpiresAt: readUrl.urlExpiresAt,
      contentType: image.contentType,
      sizeBytes: image.sizeBytes,
      checksumSha256: image.checksumSha256,
      width: image.width,
      height: image.height,
      sortOrder: image.sortOrder,
      caption: image.caption,
      status: image.status,
      uploadedAt: image.uploadedAt,
      createdAt: image.createdAt,
    };
  }
}

