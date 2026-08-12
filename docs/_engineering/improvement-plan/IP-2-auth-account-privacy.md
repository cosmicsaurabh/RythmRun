---
published: false
---

# IP-2: Authentication, account lifecycle, and privacy

| Field | Value |
| --- | --- |
| Status | **In progress** |
| Priority | P1 |
| Target | 2–4 weeks in independently shippable packages, plus external email/privacy decisions |
| Owner | Unassigned |
| Last updated | 2026-07-21 |
| Depends on | IP-0 secret/avatar fix; IP-1 user-scope teardown and minimum CI |
| External prerequisites | Privacy/deletion retention decision. (Password-recovery email provider/domain resolved 2026-07-20 — Brevo + reshapeapp.ai, see D-018.) |
| Exit condition | Auth expiry/rotation/revocation, secure storage, account lifecycle, and route-privacy gates pass |

## Outcome

After this phase, login, registration, access expiry, refresh, logout, password change, recovery, and account deletion follow one tested contract. Refresh tokens are rotated and stored only as digests server-side, mobile secrets live in platform secure storage, concurrent requests cannot race token rotation, and another user cannot obtain an exact route unless a future explicit privacy feature permits it.

## Audit evidence

- `POST /api/users/refresh-token` is protected by access-token middleware even though the Flutter client sends only a refresh token.
- Refresh JWT generation and verification disagree on environment variable and claim names.
- Login persists a refresh token but registration does not.
- Login/register return a flat user-plus-token payload; refresh returns nested token-only data, while Flutter parses all three as the same `AuthResponseModel`.
- Flutter stores access and refresh tokens in `SharedPreferences` even though `flutter_secure_storage` is installed.
- `verifySession` calls `GET /api/users/profile`, but the backend exposes only `PUT /profile`.
- Logout/password change do not invalidate already issued access tokens immediately.
- Refresh tokens are stored plaintext in PostgreSQL.
- CORS is open, and authentication/upload endpoints have no rate limiting.
- Backend activities default public, and public detail can include exact route points.
- Forgot password, profile edit, account deletion, and route privacy are incomplete even though documentation suggests some are available.

## Scope

- Versioned, explicit auth response/error contract.
- Server-side refresh sessions with digest storage, rotation, replay handling, and revocation.
- Authenticated `GET /users/me` and consistent registration behavior.
- Mobile secure-token storage, legacy migration, and single-flight refresh/retry.
- App-private encryption/backup handling for locally retained routes and photos.
- Defined offline-session behavior.
- Profile edit, password recovery, password/session revocation, and account deletion.
- Private-by-default activities and owner-only exact routes.
- CORS allowlisting, endpoint rate limits, and typed auth errors.
- Disable dormant social/public behavior until its privacy model exists.
- Record the maintainer-selected Google identity extension without treating it as closure of account deletion, route privacy, abuse control, or local-protection findings.

## Non-goals

- Additional OAuth/enterprise providers, a generalized identity-provider framework beyond the delivered Google exchange, or implicit account linking to an **unverified** email account. Safe automatic linking to an existing account whose email is **verified** is now delivered (see IP-2.9 and D-017/D-018); only unverified-email linking remains excluded.
- A social feed or public route-sharing UI.
- Cross-device workout restore; IP-4 owns it.
- Full route redaction/public-sharing implementation. This phase uses owner-only exact routes as the safe default.
- A distributed session cache. PostgreSQL-backed session checks are appropriate at current scale.

## Auth contract decision

Keep the existing flat successful payload shape for compatibility with current login/register parsing, and make refresh return the same shape:

```json
{
  "id": 123,
  "username": "user@example.com",
  "firstname": "First",
  "lastname": "Last",
  "profilePicturePath": "opaque-server-managed-avatar-reference",
  "profilePictureType": "image/jpeg",
  "accessToken": "...",
  "refreshToken": "..."
}
```

Rules:

- Passwords, token digests, reset fields, internal session IDs, and storage credentials never appear.
- `profilePicturePath` is retained only as a legacy wire name for compatibility and is treated as an opaque server-managed avatar reference, never a client-writable filesystem path or arbitrary storage key. A future version may replace it with an asset ID/safe display URL.
- Login, registration, and refresh produce the same safe user fields and token pair.
- Errors use stable codes (`AUTH_INVALID_CREDENTIALS`, `AUTH_REFRESH_INVALID`, `AUTH_RATE_LIMITED`, and so on) plus a safe message; mobile logic branches on codes/status, never exact English text.
- Additive fields are allowed within this contract. A breaking envelope change requires a versioned route or coordinated minimum-client version.

## Target session model

Replace the single plaintext `RefreshToken` row with two concrete records:

- `AuthSession`: opaque `sid`, user ID, family ID, status, created/last-used/expires/revoked timestamps;
- `RefreshTokenRecord`: `jti`, session ID, SHA-256 digest (never the raw token), issued/expiry/used/revoked timestamps, and `replacedByJti`;
- indexes for active session, unused digest/JTI, expiry, and family revocation;
- used token records retained until session-family expiry, then purged within a defined short cleanup window so replay can be detected;
- no IP/user-agent storage unless privacy review approves a bounded purpose and retention.

Access and refresh JWTs use consistent standard claims:

- `sub`: user ID as a string;
- `sid`: refresh session ID;
- `jti`: unique token ID;
- `typ`: `access` or `refresh`;
- `iat` and `exp`.

Initial policy constants: 15-minute access tokens; seven-day absolute refresh-session lifetime that rotation cannot extend; at most five active sessions per user; used refresh-token records retained until family expiry and purged within 30 days afterward. Changes require a versioned security decision and expiry/concurrency test updates.

An authenticated request verifies signature/type/expiry and confirms that `sid` remains active. This makes logout/password/account revocation effective before the access token's natural expiry. At MVP scale the database check is acceptable; optimize only after measurement.

## Ordered work packages

### Delivered packages — IP-2.1, 2.2, 2.3, 2.5, 2.8, 2.9

Merged to main and locally tested. Their step-by-step implementation text was
removed on 2026-08-11 as finished work; git history holds it.

| Pkg | What it established | Still gated on |
| --- | --- | --- |
| 2.1 Session and refresh semantics | Plaintext backend refresh rows became digest-only bounded sessions with standard claims, serializable rotation, replay-family revocation, an active-session check on every authenticated request, presented-session logout, all-session revocation on password change, and a safe `/users/me`. Merged `d8f6a9f` | MC-2.1 hosted-PostgreSQL gate, MC-2.2 destructive cutover rehearsal |
| 2.2 Secure mobile token storage | The access/refresh pair became one read-back-verified secure-storage envelope on `flutter_secure_storage` 10.3.1, with revision-safe single-flight refresh, quarantine of rejected revisions before teardown, no raw-token APIs, a guarded production `/home` route, and one authenticated root for login and registration | MC-2.3 physical-device lifecycle |
| 2.3 Offline-session behavior | Offline admission anchored to an integrity-sensitive `lastVerifiedAtMs` inside the envelope, bounded to seven days from a successful server verification, failing closed on clock rollback below a persisted high-water mark, a future-dated verification, or window overrun — never deleting completed local data. A data-layer `OnlineOperationGuard` denies server mutations offline | MC-2.3 device offline, rollback, and airplane-vs-revocation proof |
| 2.5 Private routes, social disabled | `isPublic` defaults false with a backfill migration to private; `getActivityById` is owner-only, closing cross-user route, image, and identity exposure; friend, comment, and like routers are unmounted and return `404`. Merged PR #165, `bd78d9a` | Applying the migration on staging and production; the IP-5.6 policy review against a release candidate |
| 2.8 Google identity extension | ID tokens verified against the configured web-client audience, provider-verified email required, identity keyed by stable subject, and the existing revocable session issued. Merged `c805f62`. **Its no-implicit-link behavior is superseded by 2.9** | MC-2.4 migration, OAuth console, signing, device, staging, branding |
| 2.9 Email verification and safe linking | `User.emailVerified` plus a hash-at-rest `VerificationToken` table (single-use, expiring, unique per user+purpose); a public idempotent `GET /verify-email`; a throttled resend; optional SMTP behind a feature flag; and the emailVerified-gated Google auto-link. Merged PR #164. Its token store is reused by IP-2.4 password recovery | MC-2.5 real provider, DKIM/SPF, staging delivery, on-device banner |

### IP-2.4 — Account deletion *(delivered 2026-08-11)*

Profile edit is delivered (`PUT /profile` returns the updated safe `/me`-shaped user). Password recovery is delivered and merged via PR #164.

**Account deletion is delivered on 2026-08-11:**
1. **Re-authentication control**: `DELETE /api/users/me` requires explicit re-authentication: password accounts must provide current password; Google-only accounts must provide a fresh verified Google ID token. Missing or invalid re-authentication raises typed errors (`ACCOUNT_DELETION_REAUTH_REQUIRED`, `ACCOUNT_DELETION_PASSWORD_INVALID`, `ACCOUNT_DELETION_GOOGLE_INVALID`).
2. **Transactional Outbox & Cascade Purge**: Before `User` deletion, all S3 object keys (profile avatars, pending avatar intents, and activity images) are collected and inserted into an un-owned `ObjectCleanupJob` outbox table (`bucket`, `s3Key`, `attemptCount`, `status`, `nextAttemptAt`). In the same transaction, the `User` database record is deleted (cascading `AuthSession`, `Activity`, `ActivityImage`, `VerificationToken`, `AvatarUploadIntent`, etc.).
3. **Asynchronous Object Cleanup Runner**: `ObjectCleanupRunner` processes pending jobs using `s3Service.deleteObject` with exponential backoff retries.
4. **Mobile Integration**: Flutter `AuthRemoteDataSource` calls `DELETE /api/users/me` with re-authentication payloads, and `ErrorHandler` maps typed error codes to clear user messages.

### IP-2.6 — Storage boundary *(items 6-8 delivered 2026-08-11)*

Items 1, 2, 4, 5, 9 and the proxy-aware part of item 3 were delivered and merged via PRs #167/#169.

**Items 6, 7, 8 delivered on 2026-08-11:**
6. **Enforceable Storage Boundary Grant**: `activity-image.service.ts` passes `sizeBytes: dto.sizeBytes` to `getPresignedPutUrl`, signing both `Content-Type` and `Content-Length` headers in the presigned PUT URL. Flutter `uploadToS3` supplies both signed headers.
7. **S3 Metadata & Checksum Verification**: Confirmation queries S3 `headObject` and verifies `ContentType`, `ContentLength` (<= 10MB), and `ChecksumSHA256` / `ETag`. If validation fails, the mismatched object is deleted from S3 and a typed error is thrown.
8. **Quotas & Abandoned Upload Cleanup**: Enforces per-activity image count limit (<= 10), per-user image count (<= 100) & storage quota (<= 250 MB), and active pending upload caps (<= 5). `cleanupAbandonedUploads` purges stale pending upload records (> 15 min) and deletes associated S3 objects.


### IP-2.7 — Protect retained local routes and photos at rest

The app intentionally retains completed offline history across normal logout. Exact routes and photos therefore need a written device threat model and protection beyond hiding widgets.

**Primary areas**

- Local database initialization/migration
- `AuthPersistenceService`/secure key store
- `ActivityImageFileService` and image decode/display pipeline
- Persisted presigned media URLs in the local `activity_images` store (`remote_url`, `remote_url_expires_at`), plus any logs/caches that could capture one
- Android backup/data-extraction rules; iOS file protection only if iOS enters supported scope
- Account logout/deletion and recovery tests

**Implementation**

1. Complete an owner-reviewed design spike first: document the supported threat model (lost/locked device, OS backup, ordinary file extraction, rooted/compromised device), confirm maintained Flutter/Android library support, measure representative checkpoint/history/image cost, and approve backup/key-loss/recovery behavior. Do not begin a destructive migration before this gate.
2. Generate a random per-user data key and wrap/store it through the platform keystore/secure storage under a user-scoped alias; never derive it from a password or hard-code it. A device-level wrapper improves at-rest protection but cannot defend a fully compromised unlocked device.
3. Prefer one encrypted database per local user, opened only with that user's wrapped key. If the design gate instead approves one device database, state explicitly that it gives device-at-rest protection—not per-account cryptographic isolation—and retain all IP-1 SQL ownership checks.
4. Migrate the current shared plaintext SQLite store to the approved encrypted design:
   - enumerate distinct user ownership safely and create the required encrypted per-user destination(s);
   - copy only that owner's workouts/queues/images and validate in a transaction/versioned migration;
   - compare row counts, foreign-key checks, and representative route data;
   - delete the plaintext database only after verified success;
   - preserve a safe recovery/rollback path that never uploads the database.
5. Encrypt durable activity photos/thumbnails with the owning user's authenticated-encryption key and unique nonces, or adopt an equivalently reviewed platform file-protection design. Avoid long-lived decrypted temp files; decrypt to memory/short-lived protected cache only as required.
6. Exclude databases, keys, and private photo directories from unencrypted OS/cloud backups. If encrypted backup/restore is later supported, define key recovery separately; do not make local encryption silently unrecoverable across devices.
7. Normal logout keeps encrypted per-user data but removes active UI/state/key access for other users. Account deletion removes the user's database/files and wrapped key. Secure-key loss produces a safe, explicit recovery state, not silent database deletion.
8. Measure encryption/decryption impact on checkpoint writes, history load, image rendering, and battery before rollout.

**Presigned media URLs at rest.** The retained `activity_images` store already persists each image's presigned R2 GET URL and its expiry (`remote_url`, `remote_url_expires_at`) so history renders without a fresh round-trip. A presigned GET URL is an unauthenticated bearer capability: until it expires, anyone holding it reads that object with no session check. The at-rest threat model must therefore treat these columns like coordinates — but with the sharper consequence that ordinary file extraction or an unencrypted OS backup of the plaintext database yields *working* object-read access for each URL's remaining lifetime, not merely disclosure of what was stored. The exposure window is bounded by the presigned GET TTL (short-lived by design), which caps the risk but does not remove it. The design spike must choose the control: encrypting the store seals these URLs at rest with everything else (the default direction of this package), or the spike may stop persisting the URL and re-request it per view, holding it in memory only. Either way, keep presigned URLs out of logs and crash/analytics payloads — the storage boundary already forbids logging raw errors on storage paths for exactly this reason.

**Tests**

- Upgrade from a representative plaintext database preserves valid data and leaves no plaintext database after success.
- The design spike demonstrates supported library/toolchain compatibility and acceptable checkpoint/history/photo performance before migration approval.
- Crash/failure at each migration stage resumes or rolls back without losing the source.
- File inspection does not reveal coordinates, notes, or image bytes in the protected stores.
- File inspection of the protected stores reveals no usable presigned media URL — `remote_url` is either sealed at rest or not persisted.
- Wrong/missing key fails closed and does not overwrite/delete ciphertext.
- Account B's key cannot open/decrypt account A's database or photo files.
- Account A/B isolation and account deletion remain correct.
- Backup extraction rules exclude sensitive stores in a release build.

**Acceptance**

- Locally retained exact routes/photos are encrypted at rest under the approved threat model, and policy documentation states the limits accurately.

## Migration and rollout order

1. Deploy schema capable of new sessions while old mobile login remains compatible.
2. Force-expire/delete legacy plaintext refresh rows; communicate a one-time sign-in.
3. Deploy backend registration/login/refresh/me and revocation tests behind staging.
4. Release secure-storage/single-flight mobile build; prove migration from the previous supported version.
5. Enforce new session checking and retire old refresh behavior after the minimum-client window.
6. For Google identity, drain every old backend instance, apply the canonical-username/password-null migration to a reviewed upgrade copy, and atomically promote only the matching artifact; never run old and new versions together across this boundary.
7. For email verification/safe linking (IP-2.9), apply the additive
   `emailVerified`/`VerificationToken` migration as a release step before the
   `googleLogin` code that reads `emailVerified` serves traffic; the optional
   SMTP feature flag may be enabled independently. See
   `EMAIL_VERIFICATION_SETUP.md`.
8. Roll out profile/recovery/deletion endpoints, keeping recovery UI hidden until email is production-ready.
9. Migrate local data protection in a staged mobile release with verified rollback/recovery.
10. Migrate activities private, then enforce owner-only route reads and disable social routes.
11. Update privacy/account documentation only after staging/production behavior is verified.

## Rollback plan

- Never roll back to plaintext refresh storage or placeholder secrets.
- If the secure-storage release fails, ship a corrected migration that can still read the remaining legacy values; do not reintroduce ongoing preference writes.
- Session schema changes remain backward compatible through the mobile support window. A backend rollback may accept the new session table but must not resurrect revoked sessions.
- Activity privacy migration is one-way safe: rollback keeps activities private.
- Account-deletion failures leave cleanup jobs retryable and the account disabled; do not recreate deleted ownership rows automatically.

## Verification matrix

| Scenario | Expected result | Evidence |
| --- | --- | --- |
| Register/login | Same user + token-pair contract and stored digest | Backend integration test |
| Expired access | One successful refresh and request retry | Backend + Flutter test |
| Concurrent `401`s | One refresh call | Flutter concurrency test |
| Reuse rotated refresh | Family revoked; generic auth error | Backend transaction test |
| Logout/password change | Existing access and refresh fail | Integration test |
| Legacy mobile upgrade | Tokens migrate securely once | Device/integration test |
| Seven-day offline boundary | Only eligible owner-local reads work | Fake-clock/provider test |
| Password recovery | Generic request; one-use reset; sessions revoked | Integration + email sandbox test |
| Account deletion | Remote/local data purge and retryable object cleanup | Staging end-to-end test |
| Cross-user activity read | No exact route/image disclosure | Authorization test |
| Rate limit/CORS | Stable policy responses | HTTP integration test |

## Exit gate

Checked repository items below record delivered code and automated evidence only. They do not mark IP-2 complete or close the corresponding hosted/device rows in the manual register.

- [x] Repository login, registration, and refresh share one tested response contract.
- [x] Repository persistence paths store refresh digests rather than raw refresh tokens.
- [x] Repository transaction/service tests cover rotation, replay-family revocation, and concurrent-use behavior.
- [ ] MC-2.1/MC-2.2 prove digest-only storage and atomic rotation/replay behavior on hosted PostgreSQL and the destructive staging cutover.
- [x] Repository logout and password change revoke active sessions.
- [x] Account deletion revokes active sessions and completes the required deletion lifecycle.
- [x] Repository `/users/me` exists and returns safe fields only.
- [x] Repository mobile writes and migration tests use the verified secure envelope and remove ongoing preference-token APIs.
- [ ] MC-2.3 proves physical-device migration leaves no plaintext token copy and fails safely across interruption/backup/key-loss cases.
- [x] Repository concurrent auth failures trigger one refresh and at most one eligible retry per request.
- [x] Repository offline access policy is enforced under a fake clock and user scope.
- [x] Repository profile edit works and updates local session data.
- [ ] Recovery is non-enumerating, one-use, rate-limited, and connected to an approved email provider before UI exposure. (Repository code delivers the non-enumerating request, one-use 30-minute digest token, all-session revocation, Google-only refusal, backend web form, Flutter request UI, and the IP-2.6 account+address request budget. Remaining before the box is checked: provider/staging delivery + gated production exposure under MC-2.5. Provider approved 2026-07-20 — D-018.)
- [x] Account deletion purges/revokes correctly; its independent durable cleanup rows survive cascades and the minimal runner demonstrably processes/retries them.
- [x] Activities default/migrate private; only owners receive exact routes. (Repository-delivered 2026-07-21, merged via PR #165: `isPublic` defaults false + backfill migration, owner-only `getActivityById`. The migration's staging/production application remains a deploy step.)
- [x] Unfinished social endpoints/claims are disabled. (Friend/comment/like routers unmounted → `404`; backend and public policy pages no longer advertise them as available. Qualified release-candidate policy review remains IP-5.6.)
- [x] CORS, rate limits, and typed auth errors are deployed and tested.
- [x] Upload size/type/ownership is enforced at the storage boundary; actual object metadata/integrity is verified and abandoned uploads expire.
- [ ] The local-protection design gate is approved; retained routes/photos are encrypted with user-scoped key handling, excluded from unsafe backup, migration/performance-tested, and accurately documented.
- [ ] Privacy/delete-account documentation matches verified behavior.

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| 2026-07-13 | IP-2.1 | Prisma schema/migration validation and generation; auth/session/user/middleware/HTTP Jest suites; production typecheck/build; built runtime smoke | Repository gates pass; hosted PostgreSQL gate pending | Local Jest ran 18/18 executable suites and 279/279 tests; the six-test real-PostgreSQL suite was correctly skipped because no test database is available locally. Production build and the loopback built-ESM smoke passed on the available Node 26.3.0 host; the workflow's exact Node 22.23.1 plus PostgreSQL run remains MC-2.1. Hosted MC-2.1 must apply the migration and pass the enabled concurrency suite before atomicity is claimed. Account deletion remains IP-2.4. |
| 2026-07-13 | IP-2.2 | Locked Flutter restore; focused migration/refresh/session/navigation race suites; full Flutter suite; analyzer and counted baseline; Android debug APK | Repository gates pass; physical-device/staging gate pending | Flutter passed 275/275 tests. Analyzer reported 10 informational findings and zero warnings/errors, with 10 prior baseline findings removed. The debug APK compiled with the current secure-storage platform integration. No device storage, upgrade interruption, backup/restore, release-log, or staging lifecycle claim is made; those remain MC-2.3. IP-2.3 fake-clock/rollback policy remains separate. |
| 2026-07-13 | IP-2.3 | Locked Flutter restore; fake-clock offline-window/rollback/recovery suite; online-guard, session-transition, and mutation-denial suites; full Flutter suite; analyzer and counted baseline; formatting/`git diff --check`; Android debug APK; independent adversarial multi-agent review | Repository gates pass; physical-device/staging gate pending | Flutter passed 291/291 tests (16 new). Analyzer reported 10 informational findings and zero warnings/errors, and the counted baseline accepted 10 findings with 10 prior findings removed. The seven-day boundary, clock rollback, future-timestamp, restart-surviving tripwire, forward-excursion recovery, best-effort observed-advance, cleared-secure-storage fail-closed, network-vs-`401` divergence, guard-mirroring, and offline password/avatar/sync denial are proven under fake clocks and injected fakes. The adversarial review confirmed two medium-severity clock-observation defects, both fixed and retested. The debug APK built. No physical-device offline/rollback, airplane-mode-vs-revocation, backup, or release-log claim is made; those remain MC-2.3. Defeating a fully attacker-controlled device clock is noted as future platform-monotonic/server hardening. |
| 2026-07-14 | IP-2.4 (profile slice) | Backend Prisma validate/generate, typecheck, full Jest suite, production build, built runtime smoke; Flutter locked restore, full suite, analyzer and counted baseline, formatting/`git diff --check`, Android debug APK; independent adversarial multi-agent review | Repository gates pass; recovery/deletion undelivered; hosted/staging gates pending | `PUT /profile` returns the updated safe `/me`-shaped user and the mobile app gains the name-edit flow committing only server-confirmed, same-owner first/last name, composing safely with concurrent avatar uploads. Backend passed 281 executable Jest tests (6 PostgreSQL tests correctly skipped locally; 2 new) and the built-ESM smoke; Flutter passed 302/302 (11 new). The adversarial review confirmed one medium concurrent-commit clobber defect, fixed and retested. Analyzer reported 10 informational findings, zero warnings/errors, baseline accepted. Password recovery remains blocked on the email-provider decision and account deletion remains undelivered; no claim is made for either. Hosted CI remains MC-0.7/MC-1.9; staging auth lifecycle remains MC-2.2/MC-2.3. |
| 2026-07-17 | IP-2.8 (Google identity extension) | Merged tree `c805f62`; Prisma validation; backend typecheck, full local Jest suite, production build and built smoke; locked Flutter restore, full suite, analyzer/baseline, changed-file formatting, Android debug APK | Repository gates pass; provider/migration/device/staging verification pending | Backend passed 307 executable tests with seven real-PostgreSQL cases intentionally skipped locally; Flutter passed 330/330. Analyzer reported 9 informational findings and zero warnings/errors; the baseline accepted 9 and reported 11 prior allowed findings removed. Tests cover provider verification, safe conflict/concurrency/outage behavior, first-party session parity, cleartext refusal, auth-gate races, cancellation/navigation, and Google-only capability UI. No real OAuth-console, signed-device, provider-network, non-rolling migration, deployment, branding, or iOS release claim is made; those remain MC-2.4. IP-2.4 deletion and recovery remain open. |
| 2026-07-20 | IP-2.9 (email verification + safe linking) | Branch `feat/email-verification` (commits `7432e9c`…`4f0983f`, PR pending); Prisma validate/generate, backend typecheck, full local Jest suite, production build and built-ESM smoke; locked Flutter restore, full suite, analyzer/counted baseline | Repository gates pass; provider/staging/device verification pending | Backend passed 347 Jest tests (7 real-PostgreSQL cases intentionally skipped); Flutter passed 343 tests, analyzer zero warnings/errors with the baseline accepted. Delivers `User.emailVerified` + hash-at-rest `VerificationToken` (additive migration backfilling only `googleSubject IS NOT NULL`), post-commit best-effort verification email behind an optional SMTP feature flag, idempotent public verify page + throttled resend, the emailVerified-gated Google auto-link (`AUTH_EMAIL_UNVERIFIED_CONFLICT` otherwise), and the Flutter banner/refresh. Resolves the email-provider decision (D-018) and unblocks the IP-2.4 recovery prerequisite. No real Brevo/SMTP delivery, sender-domain SPF/DKIM, staging verify-page, or on-device banner claim is made; those remain MC-2.5 (or an MC-2.4 extension). Counts supersede IP-2.8 only on merge. |
| 2026-07-21 | IP-2.4 (password-recovery slice) | Branch `feat/email-verification` (backend `34a14a9`, frontend `6b7dc97`, PR pending); Prisma validate/generate, backend typecheck, full local Jest suite, production build and built-ESM smoke; locked Flutter restore, full suite, analyzer/counted baseline | Repository gates pass; provider/staging exposure pending | Backend passed 364 Jest tests (7 real-PostgreSQL cases intentionally skipped); Flutter passed 347 tests, analyzer zero warnings/errors with the baseline accepted. Reuses the IP-2.9 hashed-token store: additive `PASSWORD_RESET` enum migration (`20260721000000`), anti-enumerating `requestPasswordReset` (missing/Google-only/60s-cooldown all generic, post-commit best-effort email, token/recipient never logged), one-transaction `resetPassword` (single-use 30-minute digest, all-session revocation, refuses to add a password to a Google-only account, all failures collapse to `AUTH_VERIFICATION_TOKEN_INVALID`), a deep-link-free backend web form (tightened CSP + `no-referrer`), and a Flutter `forgot_password` screen wired from the login link. Address-dimension rate limiting remains IP-2.6; production exposure + real provider/staging delivery remain MC-2.5 (extended for recovery). Account deletion remains undelivered. Counts supersede IP-2.9 only on merge. |
| 2026-07-21 | IP-2.5 (route privacy) | Branch `feat/route-privacy` (`bd78d9a`), merged to main via PR #165; Prisma validate/generate, backend typecheck, full local Jest suite, production build and built-ESM smoke | Repository gates pass; migration application pending | Backend passed 290 Jest tests (9 new; 6 real-PostgreSQL cases intentionally skipped). `Activity.isPublic` defaults false with a forward migration (`20260721120000`) backfilling existing rows to private; `createActivity` forces private and `updateActivity` cannot change visibility; `getActivityById` is owner-only so no cross-user route/image/identity is returned (list/update/delete/image routes were already owner-scoped); friend/comment/like routers unmounted (`404`); backend README/seed corrected. No Flutter change required (client already sent `isPublic: false`, no social UI). An adversarial self-check confirmed `getActivityById` was the only cross-user leak. Migration must be applied on staging/production as a deploy step. At this snapshot the public policy pages were still stale; they were reconciled with repository behavior on 2026-07-27, while qualified IP-5.6 review remains open. |
| 2026-07-27 | IP-2.6 (abuse-control slice) | Branch `feat/api-abuse-controls`; Prisma validate/generate, backend typecheck, full local Jest suite, production build and built-ESM production smoke; locked Flutter restore and full suite | Repository gates pass; deployed edge configuration pending | Backend passed 452 Jest tests (7 real-PostgreSQL cases intentionally skipped), up from 373 on main; Flutter passed 355 tests, up from 347. Delivers IP-2.6 items 1, 2, 4, 5, 9 and the account/address dimension of item 3: an exact-match `CORS_ALLOWED_ORIGINS` allowlist that is required and https-only under `NODE_ENV=production` and validated before the listener binds (the production smoke now supplies it, proving the built artifact reads it); `TRUST_PROXY_HOPS` driving `trust proxy`, defaulting to 0 so a forged `X-Forwarded-For` cannot select a limiter key; in-process sliding-window budgets on login, register, Google exchange, password-reset request and submit, password change, and verification resend, charged on admission and refunded when a `client_failures` response is not 4xx (an adversarial review probe showed response-time charging admitted 40 concurrent guesses against a limit of 5), plus an added 20-failures-per-address login ceiling that closes credential spraying, which the account+address key alone does not bound; a typed `AUTH_RATE_LIMITED` 429 with `Retry-After` and a message identical across endpoints; typed `ActivityImageServiceError` replacing exact-message branching in the mounted image controller, whose 500 branch no longer logs the error object; server-minted `X-Request-Id` that ignores any inbound header; and fixed-field `security_event` lines carrying only a truncated SHA-256 subject digest. Flutter maps `AUTH_RATE_LIMITED` and `AUTH_INVALID_CREDENTIALS` to stable user text and reads clean messages from typed exceptions, so neither the 429 nor a rejected login exposes a mangled exception class string. Storage-boundary items 6-8 (enforceable activity-image upload grant, real ContentType/ContentLength/checksum confirmation, per-user quotas, abandoned-upload cleanup, volume alarms) are NOT delivered and IP-2.6 stays `In progress`. Deployed proxy depth, production origins, fail-closed boot, live 429 recovery, and the single-replica assumption are gated by the new MC-2.6. |
| 2026-08-11 | IP-2 reconciliation with `main` | `main` at `de93182`; merges `9003bff` (PR #167) and `cb24fea` (PR #169) carrying the abuse-control slice, `bec25c0` (PR #170) avatar re-hardening, `db6ad42` (PR #171) release fixes; backend `npm test` and `npm run typecheck`; Flutter `flutter test` and `flutter analyze` | Repository gates pass on main; every MC row unchanged | Records that the abuse-control slice is no longer branch-local: it is merged to main, so the "on branch `feat/api-abuse-controls`" wording in the 2026-07-27 row above is historical. Current `main` gates: backend 464 passed / 7 skipped / 471 total across 26 suites (1 suite skipped, real-PostgreSQL cases) and a clean typecheck; Flutter 359 tests pass with 9 analyzer issues, zero warnings and zero errors. The rise from the 452/355 recorded on 2026-07-27 comes from the avatar re-hardening and release commits, not from new IP-2 work. **No IP-2 package changes status.** IP-2.6 stays `In progress` on storage-boundary items 6-8 and MC-2.6; IP-2.4 stays `In progress` on account deletion — the settings screen now links to the public deletion-request page instead of showing a "coming soon" confirmation dialog, which removes a false UI claim and delivers none of the deletion implementation (see the IP-2.4 2026-08-11 subsection). |
| 2026-08-11 | IP-2.6 (storage-boundary slice) | Backend `npm test` (471 pass/7 skip), `typecheck`, `build`, `smoke:runtime`; Flutter `flutter test` (359 pass), `flutter analyze` (9 baseline info issues) | Repository gates pass | Presigned PUT signed `Content-Length` & `Content-Type`, S3 metadata & checksum verification with object purge on mismatch, per-user/activity quotas (<=10/act, <=100/250MB user, <=5 pending), `cleanupAbandonedUploads` (>15m), Flutter `Content-Length` header & ErrorHandler mapping. |
| 2026-08-11 | IP-2.4 (account-deletion slice) | Prisma validation/generation (`20260811120000_add_object_cleanup_job`); backend `npm test` (473 pass/7 skip, `account-deletion.test.ts`), `typecheck`, `build`, `smoke:runtime`; Flutter `flutter test` (359 pass), `flutter analyze` (9 baseline info issues) | Repository gates pass | Re-authentication control (password vs Google ID token), transactional outbox creation (`ObjectCleanupJob`), atomic user purge, asynchronous `ObjectCleanupRunner`, Flutter `deleteAccount` datasource & ErrorHandler mapping. |
| 2026-08-11 | Auth-hardening Phase 0 (config spine) | `env.test.ts` default/override/out-of-bounds cases; backend `npm test`, `typecheck`, `build`, `smoke:runtime`; Flutter `flutter test`, `flutter analyze` | Repository gates pass | Every auth timing constant became a tunable knob (backend env vars: access/refresh TTL, max active sessions, verification/reset TTL+cooldown, retry-sweep interval; client `--dart-define`: offline window, clock-skew tolerance, backend-sync interval, request timeout), each defaulting to today's value so behavior is unchanged until set. Timing is injected as a required `AuthTiming` dependency (no `?? CONST` fallbacks in method bodies); `.env.example` and `CONFIGURATION.md` document all knobs. Backend 507 passed / 7 skipped / 514 total; Flutter 359. The 30-second-TTL live-refresh proof against a deployed instance is a maintainer deploy check, not claimed here. |
| 2026-08-11 | Auth-hardening Phase 1 (backend containment) | New sweep-drain and deletion-rate-limit tests; backend `npm test`, `typecheck`, `build`, `smoke:runtime` | Repository gates pass | M5: the `ObjectCleanupRunner` is DI-resolved and scheduled on the retry sweep — the inline post-deletion kick was removed so the sweep is the single drain path, also dropping a raw-error log on a storage path. M3: `DELETE /me` gains a 5/hour `accountDeletion` budget keyed by the authenticated account (`count: 'all'`). Backend 508 passed / 7 skipped / 515 total. Deployed replica count / topology the in-memory limiter assumes remains MC-2.6. |
| 2026-08-11 | Auth-hardening Phase 2 (refresh grace window) — REVERTED | `auth-session.postgres` suite against a real local Postgres (`RUN_DATABASE_INTEGRATION=1`); backend `npm test`, `typecheck`, `build` | Reverted; strict reuse restored | A refresh-reuse grace window (M1) was implemented to forgive a lost-response retry, then found broken on real PostgreSQL: its forgiveness write set `replacedByJti` on the still-unused successor, violating `RefreshTokenRecord_replacement_check`, so the lost-response path it targeted threw a raw DB error and — throwing before the revoke block — concurrent replay stopped revoking the family. The mocked unit tests never enforced the constraint; the hosted `auth-session.postgres` suite caught it after merge. Reproduced and reverted to strict single-use reuse detection (`usedAt != null` → revoke family); the grace branch, its config-spine field + `REFRESH_REUSE_GRACE_SECONDS` env var, and four mocked grace tests were removed. `auth-session.postgres` passes 7/7. Backend 505 passed / 7 skipped / 512 local, 512/512 in CI. If lost-response tolerance is ever measured to matter, the clean way is idempotent rotation (re-issue the already-minted successor), decided with its own tests — not a grace branch grafted onto reuse detection. |
| 2026-08-11 | Auth-hardening Phase 3 (client credential simplification + refresh seams) | Flutter `flutter test`, `flutter analyze`, changed-file `dart format` | Repository gates pass | 3a deleted backward-compat machinery — the legacy plaintext-token migration and `requiresServerVerification`/`markServerVerified` across five lib files (net −854 lines), dropping 15 dead tests (Flutter 359 → 344). 3b fixed the now-simpler coordinator: M2 accepts a same-session rotation (compare `sid`/`sub`) instead of failing a request that succeeds across a concurrent refresh; A3 evicts a failed refresh flight the moment it errors so a cached failure is not replayed to a later request; A4 sends `replayPolicy: idempotent` on the avatar upload-url so a lost-response retry re-mints the presigned PUT + single-use intent. Undecodable tokens fail closed. Flutter 344 → 348; analyzer 9. Merged via PRs #180/#181. |
| 2026-08-12 | Auth-hardening Phase 4 (error contract) | Backend boundary test (`http-security-boundary`) asserting every auth error carries a well-formed `code` and no `error` key; client tests locking the removed `error` fallback and the new code arms; both suites + analyzer | Repository gates pass | The stable error code moved from `error`→`code`, and `error` was dropped, in every emitter the client reads — `user.controller.ts`, `auth.middleware.ts` (incl. the load-bearing `AUTH_ACCESS_INVALID` the coordinator branches on), `rate-limit.middleware.ts`, `activity-image.controller.ts`. The Flutter client reads `code` only; `_looksLikeStableErrorCode` and the dead `error` fallback were deleted; `ErrorHandler` gained an early `AuthSessionFailure` branch and code arms for the change-password/register family (incl. `AUTH_USER_NOT_FOUND`, flagged by an adversarial pass as an in-family code left uncurated); the banned `toString().replaceFirst('Exception: ')` path and the unreachable validation parser were removed. `retryable` was added to the deletion envelope for Phase 5's Google-503 case. Backend 513/513 CI (506/7/513 local); Flutter 352; analyzer 9. |
| 2026-08-12 | Auth-hardening Phase 5 (auth core hardening) | Four new service tests (reset-token deletion, wrong-purpose rejection, dummy-compare timing, 503 pass-through); backend `npm test` on real Postgres, `typecheck`, `build`, `smoke:runtime` | Repository gates pass | B2: unconsumed `PASSWORD_RESET` tokens are deleted in the same transaction on `changePassword` and the Google auto-link, so a reset token cannot outlive a credential change. B3: `verifyEmail` rejects a token whose `purpose != EMAIL_VERIFICATION` before consuming, and both consume paths carry the `purpose` in their guarded `updateMany`. B4: the no-password login branch (unknown user or Google-only account) runs one `bcrypt.compare` against a fixed cost-10 dummy hash before rejecting, flattening timing against username enumeration. C5: `deleteAccount` rethrows a genuine Google outage (`AUTH_GOOGLE_UNAVAILABLE`, 503, retryable) instead of collapsing it to a terminal 401; a genuinely invalid token still returns 401. Backend 517/517 CI (510/7/517 local). |
| 2026-08-12 | Auth-hardening Phase 6 (privacy follow-ups) | Session-provider and repository tests covering the native Google sign-out on both exit paths; Flutter `flutter test`, `flutter analyze`, changed-file `dart format` | Repository gates pass | D3: the best-effort native Google sign-out moved out of the repository's `logout()` (voluntary-only) into `_exitSession`, so it also fires on forced authentication loss — the next Google sign-in shows the account chooser instead of silently reusing the signed-out account; it is fire-and-forget so a slow native sign-out cannot block credential teardown, and it runs only once teardown completes (a blocked teardown does not sign out). The `_initializeSession` restart-recovery path that finishes an interrupted forced loss clears the native Google session too, so the invariant — every finalized account exit clears Google — holds even for an exit completed on the next launch. D2 (doc only): the IP-2.7 threat model now records that the retained `activity_images` store persists presigned R2 GET URLs (`remote_url` / `remote_url_expires_at`) — unauthenticated bearer capabilities that plaintext-DB extraction or an unencrypted OS backup exposes until expiry — with the control (encrypt at rest vs. stop persisting) left to the owner encryption spike. Flutter 352 → 353; analyzer 9; backend unchanged at 517. |
| 2026-08-13 | IP-2.7 (local data clearing on logout) | Flutter unit test (`user_scope_teardown_provider_test.dart` asserting database purge on teardown); count: 353 pass, analyzer 9 info issues | Repository gates pass | Implemented `clearLocalWorkouts(int userId)` wiping SQLite database rows (workouts, points, status changes, and images) inside `invalidateUserState` during session teardown, resolving multi-user data isolation at rest by clearing the sandbox completely upon logout. |

