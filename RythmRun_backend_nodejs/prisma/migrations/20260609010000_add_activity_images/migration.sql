-- CreateEnum
CREATE TYPE "ActivityImageStatus" AS ENUM ('PENDING_UPLOAD', 'UPLOADED', 'DELETE_PENDING', 'DELETED', 'FAILED');

-- CreateTable
CREATE TABLE "ActivityImage" (
    "id" SERIAL NOT NULL,
    "activityId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "clientImageId" TEXT NOT NULL,
    "s3Key" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "checksumSha256" TEXT,
    "width" INTEGER,
    "height" INTEGER,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "caption" TEXT,
    "status" "ActivityImageStatus" NOT NULL DEFAULT 'PENDING_UPLOAD',
    "uploadedAt" TIMESTAMP(3),
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ActivityImage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ActivityImage_s3Key_key" ON "ActivityImage"("s3Key");

-- CreateIndex
CREATE UNIQUE INDEX "ActivityImage_activityId_clientImageId_key" ON "ActivityImage"("activityId", "clientImageId");

-- CreateIndex
CREATE INDEX "ActivityImage_activityId_sortOrder_idx" ON "ActivityImage"("activityId", "sortOrder");

-- CreateIndex
CREATE INDEX "ActivityImage_userId_idx" ON "ActivityImage"("userId");

-- CreateIndex
CREATE INDEX "ActivityImage_status_idx" ON "ActivityImage"("status");

-- AddForeignKey
ALTER TABLE "ActivityImage" ADD CONSTRAINT "ActivityImage_activityId_fkey" FOREIGN KEY ("activityId") REFERENCES "Activity"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ActivityImage" ADD CONSTRAINT "ActivityImage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
