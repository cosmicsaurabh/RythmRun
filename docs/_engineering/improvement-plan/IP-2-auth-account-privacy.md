---
published: false
---

# IP-2: Authentication, account lifecycle, and privacy

| Field | Value |
| --- | --- |
| Status | Planned |
| Priority | P1 |
| Target | 2–4 weeks in independently shippable packages, plus external email/privacy decisions |
| Owner | Unassigned |
| Last updated | 2026-07-10 |
| Depends on | IP-0 secret/avatar fix; IP-1 user-scope teardown and minimum CI |
| External prerequisites | Password-recovery email provider/domain; privacy/deletion retention decision |
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

## Non-goals

- OAuth/social login or enterprise identity providers.
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

### IP-2.1 — Rebuild backend session and refresh semantics

**Primary files**

- `RythmRun_backend_nodejs/prisma/schema.prisma`
- New Prisma migration replacing/backfilling `RefreshToken`
- `RythmRun_backend_nodejs/src/routes/user.routes.ts`
- `RythmRun_backend_nodejs/src/controllers/user.controller.ts`
- `RythmRun_backend_nodejs/src/services/user.service.ts`
- `RythmRun_backend_nodejs/src/middleware/auth.middleware.ts`
- `RythmRun_backend_nodejs/src/models/dto/user.dto.ts`
- New auth/session service modules and backend tests

**Implementation**

1. Add the refresh-session schema and indexes on user, token digest, expiry, and active-session lookup. Choose a migration that can force logout rather than attempting to preserve plaintext tokens indefinitely.
2. Generate the session and persist the refresh digest during both registration and login in the same logical transaction as session issuance.
3. Make `/refresh-token` unauthenticated by access token; it authenticates the refresh token itself.
4. Validate refresh JWT signature, `typ`, `sub`, `sid`, expiry, and digest match.
5. Rotate atomically:
   - conditionally mark the matching token record used only when `usedAt` and `revokedAt` are null;
   - issue a new access/refresh pair;
   - insert the new digest/JTI and link it through `replacedByJti`;
   - ensure two uses of the same old token cannot both succeed.
6. On detected reuse of a previously rotated token, revoke the session family and return a generic invalid-session error. There is no replay grace window; the Flutter single-flight coordinator prevents benign concurrent rotation. Do not reveal whether a user/session exists.
7. Make logout revoke the presented session before returning success. Password change and account deletion revoke all of the user's sessions.
8. Add authenticated `GET /api/users/me` returning safe user data; use it for verification/profile refresh.
9. Keep access lifetime short and explicit in configuration. Refresh lifetime and session count are documented and bounded.
10. Use the injected shared Prisma client and typed application errors. Never instantiate Prisma inside middleware.

**Automated tests**

- Registration and login each create a session digest and return the same response shape.
- Database never receives the raw refresh token.
- Expired access + valid refresh returns one rotated pair.
- Old refresh token fails after rotation; concurrent use yields one success at most.
- Reuse revokes the relevant family.
- Wrong token type, signature, `sid`, subject, expiry, or digest fails with the same safe external error class.
- Logout, password change, and account deletion invalidate existing access and refresh tokens.
- `/me` rejects revoked/expired access and returns only safe fields when valid.

**Acceptance**

- Refresh no longer depends on an unexpired access token.
- Token rotation and replay behavior are transactionally proven.

### IP-2.2 — Add secure mobile token storage and single-flight refresh

**Primary files**

- `rythmrun_frontend_flutter/lib/core/services/auth_persistence_service.dart`
- `rythmrun_frontend_flutter/lib/data/datasources/auth_local_datasource.dart`
- `rythmrun_frontend_flutter/lib/data/datasources/auth_remote_datasource.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/auth_repository_impl.dart`
- `rythmrun_frontend_flutter/lib/core/network/http_client.dart`
- `rythmrun_frontend_flutter/lib/presentation/common/providers/session_provider.dart`
- `rythmrun_frontend_flutter/lib/data/models/auth_response_model.dart`
- Platform secure-storage configuration and new tests

**Implementation**

1. Create a token store abstraction backed by `flutter_secure_storage` for access/refresh tokens. Keep non-secret cached user metadata and last-verification time in preferences if useful.
2. One-time migration:
   - if secure storage has no token pair, read legacy preference tokens;
   - validate that both form a coherent pair;
   - write to secure storage and read back successfully;
   - only then remove legacy preference keys;
   - on interruption, retry safely without logging values.
3. Remove all APIs that return/print the token strings. Debug output may state only presence/expiry category.
4. Introduce a single authenticated request coordinator rather than manually attaching stale headers throughout repositories.
5. On `401` caused by access expiry:
   - enter one shared in-flight refresh future;
   - other requests await it instead of sending their own refresh;
   - update the token pair atomically;
   - replay each original request at most once;
   - never refresh the refresh endpoint recursively.
6. Distinguish network/offline failure from invalid/revoked credentials using typed errors. A network failure preserves eligible offline access; an invalid session clears secure tokens and transitions to unauthenticated.
7. Make registration consistently auto-login because the backend issues a session. Update the screen/navigation through session state rather than manually popping toward Landing.
8. Close/dispose HTTP clients and avoid retrying non-idempotent requests unless their endpoint has an idempotency key. Workout creation keeps `clientSyncId` protection.
9. Remove or guard named navigation that can build `/home` without an authenticated/offline-authorized session. Authentication state, not knowledge of a route name, controls access.

**Automated tests**

- Legacy token migration succeeds once and deletes only the old secret keys after verified secure write.
- Interrupted/failed secure write leaves a recoverable state without token loss.
- Three concurrent `401`s trigger one refresh and three one-time retries.
- Refresh failure due to network enters allowed offline state; invalid/reused token clears secrets and session state.
- Registration and login reach the same authenticated root state.
- Direct navigation to `/home` while unauthenticated returns to the authenticated root/landing flow and cannot instantiate user-scoped providers.
- No token appears in logs or preference enumeration.

**Acceptance**

- Plain preferences do not contain access or refresh tokens after migration.

### IP-2.3 — Define and implement offline-session behavior

**Decision**

The last verified user may access only that user's local completed history while offline for at most seven days after successful server verification. Network mutations, profile/account actions, and sync require a valid/refreshable online session. An invalid/revoked session makes cached data inaccessible until that same account authenticates again; normal logout does not delete completed local workouts.

**Implementation**

1. Track `lastServerVerifiedAt` separately from "last sync attempted", keep its integrity-sensitive value with secure session metadata, and update it only after `/me` or refresh succeeds.
2. On startup:
   - valid access session → authenticated;
   - expired access + valid refresh + network → refresh;
   - network unavailable + cached identity within offline window → authenticated-offline;
   - server says invalid/revoked → clear tokens and unauthenticated;
   - offline window exceeded → require online verification without deleting completed data.
3. Feature gating must deny all server mutations in offline state and show a clear, non-alarming explanation.
4. Store the last observed wall-clock/monotonic relationship where the platform permits. Clock rollback, invalid timestamp, or elapsed time beyond the seven-day boundary requires online verification and never extends offline access.
5. Reuse IP-1 owner-scoped queries. Offline access is not permission to access every row in the database.

**Tests**

- Boundary before/at/after seven days under a fake clock.
- Network timeout versus server `401` produces different transitions.
- User A cached state never authorizes user B's rows.
- Reinstall/cleared secure storage cannot infer authorization from an unencrypted SQLite row alone.

### IP-2.4 — Complete profile, password recovery, and account deletion

**Primary backend areas**

- User DTO/controller/service/routes
- Prisma schema and the existing password-reset migration history
- New email/reset service abstraction
- S3/object cleanup queue introduced transactionally

**Primary Flutter areas**

- Profile screen/view model
- New forgot/reset password screens/providers
- Settings/account deletion UI
- Auth persistence and local database/image file services

**Implementation: profile**

1. `PUT /profile` returns the updated safe user, not only a message.
2. Flutter updates the session/cache from that response and supports first/last name only until additional profile fields have an explicit schema.
3. Avatar remains the IP-0 S3 pipeline and cannot be updated through generic profile DTOs.

**Implementation: password recovery**

1. Reconcile the existing migration named for password reset with the current Prisma schema; create a clean forward migration rather than editing applied history.
2. Request endpoint always returns a generic success response, rate limits by safe dimensions, and stores only a reset-token digest with a 30-minute expiry and single-use marker.
3. Send the raw token only through the configured transactional email provider. Never log it or place it in analytics.
4. Reset consumes the digest transactionally, updates the password, marks the token used, and revokes all sessions.
5. Hide/disable the production UI until email delivery, sender domain, link handling, and abuse monitoring are configured.

**Implementation: account deletion**

1. Require recent authentication/password confirmation and explicit destructive confirmation.
2. Add a minimal `ObjectCleanupJob`/outbox table and durable runner in this phase. Each job stores the validated object key, operation, idempotency identity, status, retry count, next attempt, and safe error independently; it must survive `User`/activity cascades and must not rely on a deleted foreign-key owner row.
3. In one transaction, revoke sessions, create cleanup jobs/tombstones for avatar/activity-image objects, and delete/anonymize database rows according to the approved retention policy.
4. Do not perform irreversible S3 work before the database transaction. The initial single-replica runner is restart-safe and retries idempotently; IP-4.6 adds general leasing/multi-replica coordination and reuses it for all deletion paths.
5. Keep the account disabled/deletion-pending until required cleanup reaches the policy-defined terminal state. Do not expose the production deletion UI as complete while no runner processes the jobs.
6. After server acknowledgement, delete that user's SQLite workouts/points/status/image rows, private photo files/thumbnails, cached user metadata, secure tokens, and per-user local encryption key. Run a local orphan/file check.
7. Show queued/completed deletion state safely and prevent automatic recreation by sync.

**Automated/manual tests**

- Profile response updates both visible and persisted safe user fields.
- Recovery request does not reveal account existence.
- Expired/used/wrong reset token fails; valid token works once and revokes sessions.
- Deletion requires recent authentication and creates cleanup records before user cascades remove ownership data.
- Cleanup rows survive user cascades, and a runner restart completes them without duplicate harmful work.
- Repeated cleanup is harmless.
- Deleted account cannot refresh/login unless product policy allows new registration, and old local data/files are gone.

### IP-2.5 — Make exact routes private and disable unfinished social paths

**Primary files**

- `RythmRun_backend_nodejs/prisma/schema.prisma` and a forward migration
- `RythmRun_backend_nodejs/src/services/activity.service.ts`
- Activity DTO/controller/routes
- Comment/like/friend routes and application mounting
- Flutter sync model and any visibility UI
- Privacy/account documentation after behavior ships

**Implementation**

1. Change backend default `isPublic` to `false` and explicitly set private on creation.
2. Migrate existing activities to private unless there is recorded, explicit user consent to public visibility. Current default alone is not consent.
3. During this phase, exact route detail is owner-only. Do not return another user's `locations`, start/end coordinates, or signed private images.
4. If summary sharing remains necessary, define a route-free summary DTO; otherwise disable it.
5. Unmount or return a deliberate unavailable response for unfinished comment/like/friend endpoints. Do not spend the phase merely adding `mergeParams` to expose an unsupported product journey.
6. Remove/qualify README and UI claims about social/public sharing until privacy controls, redaction, blocking/reporting, and moderation exist.
7. Plan route start/end redaction as a future opt-in feature; do not claim it in this phase.

**Tests**

- Activity created without visibility field is private.
- Existing migration makes audited default-public rows private.
- User B cannot retrieve User A's exact private/public-legacy route ID.
- Owner can retrieve their own full route.
- Disabled social routes cannot mutate or reveal data.

### IP-2.6 — Add API abuse controls and typed auth errors

**Implementation**

1. Configure CORS from a required production allowlist; mobile clients are not protected by CORS, so authentication remains mandatory.
2. Start with configurable limits and test them exactly: 5 failed login attempts per account+trusted client address per 15 minutes, 5 registrations per trusted client address per hour, 3 recovery requests per account+address per hour, and 5 password-change attempts per account per hour. IP-0 avatar limits remain in force; disabled social paths receive no quota budget until intentionally restored.
3. Apply stricter per-account upload/object quotas in addition to IP-based controls; trust proxy settings must match the actual hosting proxy.
4. Introduce typed application errors and centralized HTTP mapping for auth/account flows. Avoid controller branches on exact message strings.
5. Add request IDs and privacy-safe security event categories without logging bodies, tokens, email reset links, signed URLs, or exact coordinates.
6. Replace upload grants that cannot enforce size at the storage boundary with an enforceable mechanism (for example an S3 POST policy with a `content-length-range`, approved content type, and exact user-owned key). Apply this to avatars and activity images; server-side metadata validation after upload is still required but is not a storage-cost control.
7. Verify activity-image confirmation against actual S3 `ContentType`, bounded `ContentLength`, expected key, and a server-computable/checkable checksum mechanism. A client-declared checksum alone is not evidence of object integrity.
8. Add per-user object/count/byte quotas, lifecycle cleanup for abandoned uploads, and alarms for unusual presign/storage volume.
9. Document what happens when the rate-limit backing process restarts. A single-process limiter is acceptable only while running one replica and must fail safely under the deployed topology.

**Tests**

- Allowed/disallowed origins behave as configured without wildcard credentials.
- Rate limits return stable `429` and recover after the test window.
- Spoofed forwarding headers cannot trivially bypass limits under configured proxy settings.
- Typed error mapping produces consistent status/code without leaking internal details.
- An upload exceeding the declared size is rejected by the storage policy rather than accepted and merely rejected at confirmation.
- Wrong content type/checksum/ownership cannot become an uploaded avatar/activity-image record, and abandoned objects expire.

### IP-2.7 — Protect retained local routes and photos at rest

The app intentionally retains completed offline history across normal logout. Exact routes and photos therefore need a written device threat model and protection beyond hiding widgets.

**Primary areas**

- Local database initialization/migration
- `AuthPersistenceService`/secure key store
- `ActivityImageFileService` and image decode/display pipeline
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

**Tests**

- Upgrade from a representative plaintext database preserves valid data and leaves no plaintext database after success.
- The design spike demonstrates supported library/toolchain compatibility and acceptable checkpoint/history/photo performance before migration approval.
- Crash/failure at each migration stage resumes or rolls back without losing the source.
- File inspection does not reveal coordinates, notes, or image bytes in the protected stores.
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
6. Roll out profile/recovery/deletion endpoints, keeping recovery UI hidden until email is production-ready.
7. Migrate local data protection in a staged mobile release with verified rollback/recovery.
8. Migrate activities private, then enforce owner-only route reads and disable social routes.
9. Update privacy/account documentation only after staging/production behavior is verified.

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

- [ ] Login, registration, and refresh share one tested response contract.
- [ ] Raw refresh tokens are never stored server-side.
- [ ] Refresh rotation is atomic; replay and concurrent-use behavior are proven.
- [ ] Logout, password change, and deletion revoke active sessions.
- [ ] `/users/me` exists and returns safe fields only.
- [ ] Mobile tokens live only in secure storage after migration.
- [ ] Concurrent auth failures trigger one refresh and one retry per request.
- [ ] Offline access policy is enforced under a fake clock and user scope.
- [ ] Profile edit works and updates local session data.
- [ ] Recovery is non-enumerating, one-use, rate-limited, and connected to an approved email provider before UI exposure.
- [ ] Account deletion purges/revokes correctly; its independent durable cleanup rows survive cascades and the minimal runner demonstrably processes/retries them.
- [ ] Activities default/migrate private; only owners receive exact routes.
- [ ] Unfinished social endpoints/claims are disabled.
- [ ] CORS, rate limits, and typed auth errors are deployed and tested.
- [ ] Upload size/type/ownership is enforced at the storage boundary; actual object metadata/integrity is verified and abandoned uploads expire.
- [ ] The local-protection design gate is approved; retained routes/photos are encrypted with user-scoped key handling, excluded from unsafe backup, migration/performance-tested, and accurately documented.
- [ ] Privacy/delete-account documentation matches verified behavior.

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| — | — | No implementation evidence yet | Not started | Planning document only |
