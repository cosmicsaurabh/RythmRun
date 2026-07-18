-- Email verification state + single-use, hash-at-rest verification tokens.
-- This underpins safe automatic account linking: a Google sign-in may only
-- merge onto an existing local account once THAT account has independently
-- proven control of its email (emailVerified = true).
BEGIN;

-- Whether the local (password) account has proven control of its email by
-- clicking a verification link. Defaults false; register() never verifies.
ALTER TABLE "User"
ADD COLUMN "emailVerified" BOOLEAN NOT NULL DEFAULT false;

-- Backfill: existing Google-linked accounts had their email proven by Google
-- (google-auth enforces email_verified === true when they were created), so
-- grandfather them as verified. Password-only accounts intentionally stay
-- false -- their username was never verified, so leaving them unverified is
-- what closes the pre-existing account-takeover window for legacy rows.
-- NEVER blanket-set password accounts to true.
UPDATE "User"
SET "emailVerified" = true
WHERE "googleSubject" IS NOT NULL;

CREATE TYPE "VerificationTokenPurpose" AS ENUM ('EMAIL_VERIFICATION');

CREATE TABLE "VerificationToken" (
    "id" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "purpose" "VerificationTokenPurpose" NOT NULL DEFAULT 'EMAIL_VERIFICATION',
    "tokenDigest" CHAR(64) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "lastSentAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "VerificationToken_pkey" PRIMARY KEY ("id")
);

-- Lookups are by digest only (never by user-supplied id/email), so the DB
-- compares hashes and there is no raw-secret timing oracle.
CREATE UNIQUE INDEX "VerificationToken_tokenDigest_key" ON "VerificationToken"("tokenDigest");

-- Exactly one outstanding token per user per purpose: a resend replaces it.
CREATE UNIQUE INDEX "VerificationToken_userId_purpose_key" ON "VerificationToken"("userId", "purpose");

-- Supports the periodic purge of expired tokens on the existing sweep timer.
CREATE INDEX "VerificationToken_expiresAt_idx" ON "VerificationToken"("expiresAt");

ALTER TABLE "VerificationToken"
ADD CONSTRAINT "VerificationToken_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

COMMIT;
