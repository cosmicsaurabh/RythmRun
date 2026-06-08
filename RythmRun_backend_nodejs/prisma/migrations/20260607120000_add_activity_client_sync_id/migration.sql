-- AlterTable
ALTER TABLE "Activity" ADD COLUMN "clientSyncId" TEXT;

-- Backfill any pre-existing rows before making the column required.
UPDATE "Activity"
SET "clientSyncId" = concat('legacy-', "userId", '-', "id")
WHERE "clientSyncId" IS NULL;

-- AlterTable
ALTER TABLE "Activity" ALTER COLUMN "clientSyncId" SET NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "Activity_userId_clientSyncId_key" ON "Activity"("userId", "clientSyncId");
