-- Existing refresh JWTs do not contain session or token identifiers, so they
-- cannot be migrated into the revocable session model safely. Dropping the
-- legacy table deliberately forces all existing clients to authenticate once.
DROP TABLE "RefreshToken";

CREATE TYPE "AuthSessionStatus" AS ENUM ('ACTIVE', 'REVOKED');

CREATE TABLE "AuthSession" (
    "id" UUID NOT NULL,
    "userId" INTEGER NOT NULL,
    "familyId" UUID NOT NULL,
    "status" "AuthSessionStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastUsedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "AuthSession_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "AuthSession_expiry_check" CHECK ("expiresAt" > "createdAt"),
    CONSTRAINT "AuthSession_revocation_check" CHECK (
        ("status" = 'ACTIVE' AND "revokedAt" IS NULL)
        OR ("status" = 'REVOKED' AND "revokedAt" IS NOT NULL)
    )
);

CREATE TABLE "RefreshTokenRecord" (
    "jti" UUID NOT NULL,
    "sessionId" UUID NOT NULL,
    "tokenDigest" CHAR(64) NOT NULL,
    "issuedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "replacedByJti" UUID,

    CONSTRAINT "RefreshTokenRecord_pkey" PRIMARY KEY ("jti"),
    CONSTRAINT "RefreshTokenRecord_expiry_check" CHECK ("expiresAt" > "issuedAt"),
    CONSTRAINT "RefreshTokenRecord_replacement_check" CHECK (
        "replacedByJti" IS NULL OR "usedAt" IS NOT NULL
    )
);

CREATE UNIQUE INDEX "AuthSession_familyId_key" ON "AuthSession"("familyId");
CREATE INDEX "AuthSession_userId_status_expiresAt_idx" ON "AuthSession"("userId", "status", "expiresAt");
CREATE INDEX "AuthSession_familyId_status_idx" ON "AuthSession"("familyId", "status");
CREATE INDEX "AuthSession_status_expiresAt_idx" ON "AuthSession"("status", "expiresAt");
CREATE INDEX "AuthSession_expiresAt_idx" ON "AuthSession"("expiresAt");

CREATE UNIQUE INDEX "RefreshTokenRecord_tokenDigest_key" ON "RefreshTokenRecord"("tokenDigest");
CREATE UNIQUE INDEX "RefreshTokenRecord_replacedByJti_key" ON "RefreshTokenRecord"("replacedByJti");
CREATE INDEX "RefreshTokenRecord_sessionId_usedAt_revokedAt_idx" ON "RefreshTokenRecord"("sessionId", "usedAt", "revokedAt");
CREATE INDEX "RefreshTokenRecord_expiresAt_idx" ON "RefreshTokenRecord"("expiresAt");

ALTER TABLE "AuthSession"
ADD CONSTRAINT "AuthSession_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "RefreshTokenRecord"
ADD CONSTRAINT "RefreshTokenRecord_sessionId_fkey"
FOREIGN KEY ("sessionId") REFERENCES "AuthSession"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "RefreshTokenRecord"
ADD CONSTRAINT "RefreshTokenRecord_replacedByJti_fkey"
FOREIGN KEY ("replacedByJti") REFERENCES "RefreshTokenRecord"("jti") ON DELETE SET NULL ON UPDATE CASCADE;
