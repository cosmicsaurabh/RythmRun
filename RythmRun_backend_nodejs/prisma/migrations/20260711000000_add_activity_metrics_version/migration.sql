-- Existing activities and writes from older clients use the legacy metric
-- interpretation until a client explicitly opts into the canonical contract.
-- Prisma cannot represent this check in schema.prisma, so keep it as an
-- intentional database-level guard in this migration. Add both pieces in one
-- statement so PostgreSQL cannot commit only the column if the guard fails.
ALTER TABLE "Activity"
ADD COLUMN "metricsVersion" INTEGER NOT NULL DEFAULT 1,
ADD CONSTRAINT "Activity_metricsVersion_supported_check"
CHECK ("metricsVersion" IN (1, 2));
