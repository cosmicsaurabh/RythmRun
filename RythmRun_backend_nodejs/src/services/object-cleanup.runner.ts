import { inject, injectable } from 'tsyringe';
import type { PrismaClient } from '../generated/prisma/client.js';
import type { S3Service } from './s3.service.js';
import s3Service from './s3.service.js';

export const MAX_CLEANUP_ATTEMPTS = 5;

@injectable()
export class ObjectCleanupRunner {
  constructor(
    @inject('PrismaClient') private prisma: PrismaClient,
    @inject('S3Service') private s3: S3Service = s3Service,
  ) {}

  async processPendingJobs(limit = 25): Promise<number> {
    const now = new Date();
    const jobs = await this.prisma.objectCleanupJob.findMany({
      where: {
        status: { in: ['PENDING', 'FAILED'] },
        nextAttemptAt: { lte: now },
        attemptCount: { lt: MAX_CLEANUP_ATTEMPTS },
      },
      orderBy: { nextAttemptAt: 'asc' },
      take: limit,
    });

    let processedCount = 0;

    for (const job of jobs) {
      await this.prisma.objectCleanupJob.update({
        where: { id: job.id },
        data: { status: 'PROCESSING' },
      });

      try {
        const bucketEnvVar =
          job.bucket === 'AVATARS'
            ? 'R2_BUCKET_AVATARS'
            : 'R2_BUCKET_ACTIVITY_IMAGES';

        await this.s3.deleteObject(job.s3Key, bucketEnvVar);

        await this.prisma.objectCleanupJob.update({
          where: { id: job.id },
          data: {
            status: 'COMPLETED',
            lastError: null,
          },
        });
        processedCount++;
      } catch (error) {
        const nextAttemptCount = job.attemptCount + 1;
        const backoffMs = Math.pow(2, nextAttemptCount) * 10 * 1000;
        const nextAttemptAt = new Date(Date.now() + backoffMs);
        const errorMessage =
          error instanceof Error ? error.message : String(error);

        await this.prisma.objectCleanupJob.update({
          where: { id: job.id },
          data: {
            attemptCount: nextAttemptCount,
            status:
              nextAttemptCount >= MAX_CLEANUP_ATTEMPTS ? 'FAILED' : 'PENDING',
            nextAttemptAt,
            lastError: errorMessage,
          },
        });
      }
    }

    return processedCount;
  }
}
