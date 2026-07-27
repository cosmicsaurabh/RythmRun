import 'reflect-metadata';
import { jest } from '@jest/globals';
import type { ActivityImageService as ActivityImageServiceType } from '../services/activity-image.service.js';

jest.unstable_mockModule('../services/s3.service.js', () => ({
  __esModule: true,
  default: {
    getPresignedPutUrl: jest.fn(async ({ key }: { key: string }) => ({
      uploadUrl: `https://upload.example.com/${key}`,
      key,
    })),
    getActivityImageReadUrl: jest.fn((key: string) => ({
      url: `https://signed.example.com/${key}`,
      urlExpiresAt: '2026-06-09T10:15:00.000Z',
    })),
    headObject: jest.fn(async () => ({ ContentLength: 1024 })),
    deleteObject: jest.fn(async () => undefined),
  },
}));

const { ActivityImageService } = await import('../services/activity-image.service.js');
import {
  ConfirmActivityImageUploadDto,
  RequestActivityImageUploadUrlDto,
} from '../models/dto/activity-image.dto.js';
const { default: s3Service } = await import('../services/s3.service.js');

function createMockPrisma() {
  return {
    activity: {
      findFirst: jest.fn(),
    },
    activityImage: {
      findUnique: jest.fn(),
      create: jest.fn(),
      upsert: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      update: jest.fn(),
    },
  };
}

describe('ActivityImageService', () => {
  let prisma: ReturnType<typeof createMockPrisma>;
  let service: ActivityImageServiceType;

  const userId = 1;
  const activityId = 99;
  const clientImageId = 'img_client_123456';
  const s3Key = `activity-images/${userId}/${activityId}/${clientImageId}.jpg`;
  const createdAt = new Date('2026-06-09T10:00:00.000Z');

  const baseDto: RequestActivityImageUploadUrlDto = {
    clientImageId,
    contentType: 'image/jpeg',
    sizeBytes: 1024,
    checksumSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    width: 800,
    height: 600,
    sortOrder: 0,
    caption: 'Finish line',
  };

  const baseImage = {
    id: 10,
    activityId,
    userId,
    clientImageId,
    s3Key,
    contentType: 'image/jpeg',
    sizeBytes: 1024,
    checksumSha256: baseDto.checksumSha256,
    width: 800,
    height: 600,
    sortOrder: 0,
    caption: 'Finish line',
    status: 'UPLOADED',
    uploadedAt: createdAt,
    deletedAt: null,
    createdAt,
    updatedAt: createdAt,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    prisma = createMockPrisma();
    prisma.activity.findFirst.mockResolvedValue({ id: activityId, userId });
    service = new ActivityImageService(prisma as any);
  });

  describe('requestUploadUrl', () => {
    it('rejects unsupported image content types', async () => {
      await expect(
        service.requestUploadUrl(userId, activityId, {
          ...baseDto,
          contentType: 'image/gif',
        }),
      ).rejects.toThrow('Unsupported image content type');

      expect(prisma.activityImage.findUnique).not.toHaveBeenCalled();
      expect(s3Service.getPresignedPutUrl).not.toHaveBeenCalled();
    });

    it('rejects oversized images', async () => {
      await expect(
        service.requestUploadUrl(userId, activityId, {
          ...baseDto,
          sizeBytes: 10 * 1024 * 1024 + 1,
        }),
      ).rejects.toThrow('Image file too large');

      expect(prisma.activityImage.findUnique).not.toHaveBeenCalled();
      expect(s3Service.getPresignedPutUrl).not.toHaveBeenCalled();
    });

    it("rejects another user's activity", async () => {
      prisma.activity.findFirst.mockResolvedValue(null);

      await expect(
        service.requestUploadUrl(userId, activityId, baseDto),
      ).rejects.toThrow('Activity not found or unauthorized');

      expect(prisma.activity.findFirst).toHaveBeenCalledWith({
        where: { id: activityId, userId },
      });
      expect(prisma.activityImage.create).not.toHaveBeenCalled();
      expect(s3Service.getPresignedPutUrl).not.toHaveBeenCalled();
    });

    it('is idempotent for the same pending client image ID', async () => {
      const pendingImage = {
        ...baseImage,
        status: 'PENDING_UPLOAD',
        uploadedAt: null,
      };

      prisma.activityImage.findUnique.mockResolvedValue(pendingImage);

      const result = await service.requestUploadUrl(userId, activityId, baseDto);

      expect(prisma.activityImage.create).not.toHaveBeenCalled();
      expect(s3Service.getPresignedPutUrl).toHaveBeenCalledWith({
        key: s3Key,
        contentType: 'image/jpeg',
      });
      expect(result).toMatchObject({
        imageId: pendingImage.id,
        clientImageId,
        key: s3Key,
        uploadUrl: `https://upload.example.com/${s3Key}`,
        requiredHeaders: { 'Content-Type': 'image/jpeg' },
      });
    });

    it('returns the existing image when the client image ID is already uploaded', async () => {
      prisma.activityImage.findUnique.mockResolvedValue(baseImage);

      const result = await service.requestUploadUrl(userId, activityId, baseDto);

      expect(prisma.activityImage.create).not.toHaveBeenCalled();
      expect(s3Service.getPresignedPutUrl).not.toHaveBeenCalled();
      expect(result).toMatchObject({
        id: baseImage.id,
        imageId: baseImage.id,
        clientImageId,
        key: s3Key,
        alreadyUploaded: true,
        url: `https://signed.example.com/${s3Key}`,
      });
    });
  });

  describe('confirmUpload', () => {
    const confirmDto: ConfirmActivityImageUploadDto = {
      ...baseDto,
      key: s3Key,
    };

    it('rejects keys outside the owned activity image prefix', async () => {
      await expect(
        service.confirmUpload(userId, activityId, {
          ...confirmDto,
          key: `activity-images/2/${activityId}/${clientImageId}.jpg`,
        }),
      ).rejects.toThrow('Invalid image key');

      expect(s3Service.headObject).not.toHaveBeenCalled();
      expect(prisma.activityImage.upsert).not.toHaveBeenCalled();
    });

    it('confirms the same uploaded image idempotently', async () => {
      prisma.activityImage.upsert.mockResolvedValue(baseImage);

      const first = await service.confirmUpload(userId, activityId, confirmDto);
      const second = await service.confirmUpload(userId, activityId, confirmDto);

      expect(s3Service.headObject).toHaveBeenCalledTimes(2);
      expect(prisma.activityImage.upsert).toHaveBeenCalledTimes(2);
      expect(prisma.activityImage.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            activityId_clientImageId: {
              activityId,
              clientImageId,
            },
          },
          create: expect.objectContaining({
            activityId,
            userId,
            clientImageId,
            s3Key,
            status: 'UPLOADED',
          }),
          update: expect.objectContaining({
            status: 'UPLOADED',
            deletedAt: null,
          }),
        }),
      );
      expect(first.id).toBe(baseImage.id);
      expect(second.id).toBe(baseImage.id);
    });
  });

  describe('listImages', () => {
    it('only queries uploaded, non-deleted images in sort order', async () => {
      prisma.activityImage.findMany.mockResolvedValue([baseImage]);

      const result = await service.listImages(userId, activityId);

      expect(prisma.activityImage.findMany).toHaveBeenCalledWith({
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
      expect(result).toHaveLength(1);
      expect(result[0]).toMatchObject({
        id: baseImage.id,
        key: s3Key,
        url: `https://signed.example.com/${s3Key}`,
      });
    });
  });

  describe('deleteImage', () => {
    it('succeeds when deleting the same image twice', async () => {
      prisma.activityImage.findFirst
        .mockResolvedValueOnce(baseImage)
        .mockResolvedValueOnce({
          ...baseImage,
          status: 'DELETED',
          deletedAt: createdAt,
        });
      prisma.activityImage.update.mockResolvedValue({
        ...baseImage,
        status: 'DELETED',
        deletedAt: createdAt,
      });

      await expect(
        service.deleteImage(userId, activityId, baseImage.id),
      ).resolves.toEqual({ message: 'Image deleted successfully' });
      await expect(
        service.deleteImage(userId, activityId, baseImage.id),
      ).resolves.toEqual({ message: 'Image deleted successfully' });

      expect(prisma.activityImage.update).toHaveBeenCalledTimes(2);
      expect(prisma.activityImage.update).toHaveBeenNthCalledWith(1, {
        where: { id: baseImage.id },
        data: {
          status: 'DELETE_PENDING',
          deletedAt: expect.any(Date),
        },
      });
      expect(prisma.activityImage.update).toHaveBeenNthCalledWith(2, {
        where: { id: baseImage.id },
        data: {
          status: 'DELETED',
          deletedAt: expect.any(Date),
        },
      });
      expect(s3Service.deleteObject).toHaveBeenCalledTimes(1);
      expect(s3Service.deleteObject).toHaveBeenCalledWith(s3Key);
    });

    it('succeeds when the image is already missing', async () => {
      prisma.activityImage.findFirst.mockResolvedValue(null);

      await expect(
        service.deleteImage(userId, activityId, baseImage.id),
      ).resolves.toEqual({ message: 'Image deleted successfully' });

      expect(prisma.activityImage.update).not.toHaveBeenCalled();
      expect(s3Service.deleteObject).not.toHaveBeenCalled();
    });

    it('keeps DELETE_PENDING when S3 object deletion fails', async () => {
      const consoleErrorSpy = jest
        .spyOn(console, 'error')
        .mockImplementation(() => undefined);
      prisma.activityImage.findFirst.mockResolvedValue(baseImage);
      prisma.activityImage.update.mockResolvedValue({
        ...baseImage,
        status: 'DELETE_PENDING',
        deletedAt: createdAt,
      });
      (s3Service.deleteObject as jest.Mock).mockRejectedValueOnce(
        new Error('s3 timeout'),
      );

      await expect(
        service.deleteImage(userId, activityId, baseImage.id),
      ).resolves.toEqual({ message: 'Image deleted successfully' });

      expect(prisma.activityImage.update).toHaveBeenNthCalledWith(1, {
        where: { id: baseImage.id },
        data: {
          status: 'DELETE_PENDING',
          deletedAt: expect.any(Date),
        },
      });
      expect(prisma.activityImage.update).toHaveBeenNthCalledWith(2, {
        where: { id: baseImage.id },
        data: {
          status: 'DELETE_PENDING',
        },
      });
      consoleErrorSpy.mockRestore();
    });

    it('retries pending S3 deletes and marks them deleted', async () => {
      prisma.activityImage.findMany.mockResolvedValue([
        {
          ...baseImage,
          status: 'DELETE_PENDING',
          deletedAt: createdAt,
        },
      ]);
      prisma.activityImage.update.mockResolvedValue({
        ...baseImage,
        status: 'DELETED',
        deletedAt: createdAt,
      });

      await service.retryPendingDeletes();

      expect(prisma.activityImage.findMany).toHaveBeenCalledWith({
        where: { status: 'DELETE_PENDING' },
        orderBy: { updatedAt: 'asc' },
        take: 25,
      });
      expect(s3Service.deleteObject).toHaveBeenCalledWith(s3Key);
      expect(prisma.activityImage.update).toHaveBeenCalledWith({
        where: { id: baseImage.id },
        data: {
          status: 'DELETED',
          deletedAt: expect.any(Date),
        },
      });
    });
  });
});
