-- AlterTable
ALTER TABLE "Activity" ADD COLUMN "pausedDuration" INTEGER,
ADD COLUMN "name" TEXT,
ADD COLUMN "elevationGain" DOUBLE PRECISION,
ADD COLUMN "elevationLoss" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "Location" ADD COLUMN "heading" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "StatusChange" (
    "id" SERIAL NOT NULL,
    "activityId" INTEGER NOT NULL,
    "status" VARCHAR(20) NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StatusChange_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "StatusChange" ADD CONSTRAINT "StatusChange_activityId_fkey" FOREIGN KEY ("activityId") REFERENCES "Activity"("id") ON DELETE CASCADE ON UPDATE CASCADE;
