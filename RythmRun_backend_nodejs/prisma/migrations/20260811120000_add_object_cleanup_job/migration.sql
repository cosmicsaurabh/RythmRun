-- CreateEnum
CREATE TYPE "ObjectCleanupBucket" AS ENUM ('AVATARS', 'ACTIVITY_IMAGES');

-- CreateEnum
CREATE TYPE "ObjectCleanupStatus" AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED');

-- CreateTable
CREATE TABLE "ObjectCleanupJob" (
    "id" TEXT NOT NULL,
    "bucket" "ObjectCleanupBucket" NOT NULL,
    "s3Key" TEXT NOT NULL,
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "status" "ObjectCleanupStatus" NOT NULL DEFAULT 'PENDING',
    "nextAttemptAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ObjectCleanupJob_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ObjectCleanupJob_status_nextAttemptAt_idx" ON "ObjectCleanupJob"("status", "nextAttemptAt");
