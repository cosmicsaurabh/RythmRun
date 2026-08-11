import 'reflect-metadata';
import { jest } from '@jest/globals';
import type { ObjectCleanupRunner as RunnerType } from '../services/object-cleanup.runner.js';

jest.unstable_mockModule('../services/s3.service.js', () => ({
  __esModule: true,
  default: {
    deleteObject: jest.fn(async () => undefined),
  },
}));

const { ObjectCleanupRunner } = await import('../services/object-cleanup.runner.js');
const { default: s3Service } = await import('../services/s3.service.js');

function createMockPrisma() {
  return {
    objectCleanupJob: {
      findMany: jest.fn(),
      update: jest.fn(),
      create: jest.fn(),
    },
    user: {
      findUnique: jest.fn(),
      delete: jest.fn(),
    },
    activityImage: {
      findMany: jest.fn(),
    },
    avatarUploadIntent: {
      findMany: jest.fn(),
    },
  };
}

describe('ObjectCleanupRunner', () => {
  let prisma: ReturnType<typeof createMockPrisma>;
  let runner: RunnerType;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma = createMockPrisma();
    runner = new ObjectCleanupRunner(prisma as any, s3Service as any);
  });

  it('processes pending avatar and activity image jobs and marks them completed', async () => {
    const job1 = {
      id: 'job-1',
      bucket: 'AVATARS',
      s3Key: 'avatars/1/uuid.jpg',
      attemptCount: 0,
      status: 'PENDING',
    };
    const job2 = {
      id: 'job-2',
      bucket: 'ACTIVITY_IMAGES',
      s3Key: 'activity-images/1/99/img.jpg',
      attemptCount: 0,
      status: 'PENDING',
    };

    prisma.objectCleanupJob.findMany.mockResolvedValue([job1, job2]);

    const count = await runner.processPendingJobs();

    expect(count).toBe(2);
    expect(s3Service.deleteObject).toHaveBeenCalledWith(
      'avatars/1/uuid.jpg',
      'R2_BUCKET_AVATARS',
    );
    expect(s3Service.deleteObject).toHaveBeenCalledWith(
      'activity-images/1/99/img.jpg',
      'R2_BUCKET_ACTIVITY_IMAGES',
    );
    expect(prisma.objectCleanupJob.update).toHaveBeenCalledWith({
      where: { id: 'job-1' },
      data: { status: 'COMPLETED', lastError: null },
    });
    expect(prisma.objectCleanupJob.update).toHaveBeenCalledWith({
      where: { id: 'job-2' },
      data: { status: 'COMPLETED', lastError: null },
    });
  });

  it('handles S3 delete failure by incrementing attempt count and setting backoff', async () => {
    const job = {
      id: 'job-1',
      bucket: 'AVATARS',
      s3Key: 'avatars/1/uuid.jpg',
      attemptCount: 0,
      status: 'PENDING',
    };

    prisma.objectCleanupJob.findMany.mockResolvedValue([job]);
    (s3Service.deleteObject as jest.Mock<any>).mockRejectedValueOnce(
      new Error('S3 error'),
    );

    const count = await runner.processPendingJobs();

    expect(count).toBe(0);
    expect(prisma.objectCleanupJob.update).toHaveBeenCalledWith({
      where: { id: 'job-1' },
      data: expect.objectContaining({
        attemptCount: 1,
        status: 'PENDING',
        lastError: 'S3 error',
      }),
    });
  });
});
