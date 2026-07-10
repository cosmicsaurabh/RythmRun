-- CreateTable
CREATE TABLE "AvatarUploadIntent" (
    "id" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "key" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "cleanupKey" TEXT,
    "cleanupCompletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AvatarUploadIntent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "AvatarUploadIntent_key_key" ON "AvatarUploadIntent"("key");

-- CreateIndex
CREATE INDEX "AvatarUploadIntent_userId_createdAt_idx" ON "AvatarUploadIntent"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "AvatarUploadIntent_userId_consumedAt_expiresAt_idx" ON "AvatarUploadIntent"("userId", "consumedAt", "expiresAt");

-- CreateIndex
CREATE INDEX "AvatarUploadIntent_consumedAt_expiresAt_idx" ON "AvatarUploadIntent"("consumedAt", "expiresAt");

-- CreateIndex
CREATE INDEX "AvatarUploadIntent_cleanupCompletedAt_consumedAt_idx" ON "AvatarUploadIntent"("cleanupCompletedAt", "consumedAt");

-- AddForeignKey
ALTER TABLE "AvatarUploadIntent" ADD CONSTRAINT "AvatarUploadIntent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
