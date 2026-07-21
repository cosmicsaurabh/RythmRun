-- IP-2.5: activities are private by default.
--
-- The column default flips from true to false. Existing rows created under the
-- old default-public schema are backfilled to private: the previous default is
-- not evidence of a user's consent to publish an exact route, so every
-- currently-public row is made private. This is one-way safe — a rollback
-- keeps activities private (the audit's public default is never restored).
ALTER TABLE "Activity" ALTER COLUMN "isPublic" SET DEFAULT false;

UPDATE "Activity" SET "isPublic" = false WHERE "isPublic" = true;
