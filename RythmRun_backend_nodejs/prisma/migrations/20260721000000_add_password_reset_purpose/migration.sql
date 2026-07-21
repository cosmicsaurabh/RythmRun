-- Add the PASSWORD_RESET purpose so the existing single-use, hash-at-rest
-- VerificationToken table can also carry password-reset tokens. The
-- @@unique([userId, purpose]) constraint keeps a user's email-verification and
-- password-reset tokens independent (one outstanding token per purpose).
--
-- Adding a value to an existing enum type is additive and rollback-safe (no
-- row uses PASSWORD_RESET until the reset flow issues one). It is idempotent so
-- a re-run is harmless.
ALTER TYPE "VerificationTokenPurpose" ADD VALUE IF NOT EXISTS 'PASSWORD_RESET';
