import { injectable, inject } from 'tsyringe';
import { ActivityImage, PrismaClient } from '../../generated/prisma';
import {
  ConfirmActivityImageUploadDto,
  RequestActivityImageUploadUrlDto,
} from '../models/dto/activity-image.dto';
import s3Service from './s3.service';

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
    });

    return {
      imageId: image.id,
      clientImageId: image.clientImageId,
      key: image.s3Key,
      uploadUrl: signed.uploadUrl,
      expiresAt: new Date(Date.now() + 300 * 1000).toISOString(),
      requiredHeaders: { 'Content-Type': dto.contentType },
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
    if (head.ContentLength && head.ContentLength !== dto.sizeBytes) {
      throw new Error('Uploaded image size mismatch');
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

  private async assertOwnedActivity(userId: number, activityId: number) {
    const activity = await this.prisma.activity.findFirst({
      where: { id: activityId, userId },
    });

    if (!activity) {
      throw new Error('Activity not found or unauthorized');
    }

    return activity;
  }

  private validateImageMetadata(dto: RequestActivityImageUploadUrlDto) {
    if (!ALLOWED_CONTENT_TYPES.has(dto.contentType)) {
      throw new Error('Unsupported image content type');
    }

    if (dto.sizeBytes > MAX_IMAGE_SIZE_BYTES) {
      throw new Error('Image file too large');
    }

    if (!/^[A-Za-z0-9_-]{8,160}$/.test(dto.clientImageId)) {
      throw new Error('Invalid client image ID');
    }

    if (
      dto.checksumSha256 &&
      !/^[a-fA-F0-9]{64}$/.test(dto.checksumSha256)
    ) {
      throw new Error('Invalid checksum');
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
      throw new Error('Invalid image key');
    }
  }

  private async tryDeleteObjectAndMarkDeleted(imageId: number, s3Key: string) {
    try {
      await s3Service.deleteObject(s3Key);
      await this.prisma.activityImage.update({
        where: { id: imageId },
        data: {
          status: 'DELETED',
          deletedAt: new Date(),
        },
      });
    } catch (error) {
      console.error('Failed to delete activity image object:', error);
      await this.prisma.activityImage.update({
        where: { id: imageId },
        data: {
          status: 'DELETE_PENDING',
        },
      });
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
