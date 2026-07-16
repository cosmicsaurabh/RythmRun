-- Google identities use the stable, issuer-provided subject claim. Email is
-- kept as the existing user-facing username and is not used as provider ID.
BEGIN;

-- Canonicalization must not merge accounts silently. Abort before changing
-- any row if trimming/lowercasing would make two usernames identical.
DO $migration$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "User"
    GROUP BY LOWER(BTRIM("username"))
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Cannot canonicalize User.username: case-insensitive or whitespace-normalized duplicates exist';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM "User"
    WHERE BTRIM("username") = ''
  ) THEN
    RAISE EXCEPTION
      'Cannot canonicalize User.username: a blank username exists';
  END IF;
END
$migration$;

UPDATE "User"
SET "username" = LOWER(BTRIM("username"))
WHERE "username" <> LOWER(BTRIM("username"));

ALTER TABLE "User"
ADD COLUMN "googleSubject" VARCHAR(255),
ALTER COLUMN "password" DROP NOT NULL;

CREATE UNIQUE INDEX "User_googleSubject_key" ON "User"("googleSubject");

-- Every account must retain at least one usable authentication method.
ALTER TABLE "User"
ADD CONSTRAINT "User_authentication_method_check"
CHECK ("password" IS NOT NULL OR "googleSubject" IS NOT NULL);

-- Together with User_username_key, this makes username uniqueness
-- case-insensitive because every stored value must be canonical.
ALTER TABLE "User"
ADD CONSTRAINT "User_username_canonical_check"
CHECK (
  "username" = LOWER(BTRIM("username"))
  AND CHAR_LENGTH("username") > 0
);

COMMIT;
