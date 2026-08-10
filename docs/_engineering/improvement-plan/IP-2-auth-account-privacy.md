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

### IP-2.4 — Account deletion *(the last slice; profile and recovery are delivered)*

Profile edit is delivered (`PUT /profile` returns the updated safe `/me`-shaped
user; the mobile name-edit flow commits only server-confirmed, same-owner
names). Password recovery is delivered and merged via PR #164 — an
anti-enumerating request endpoint, a one-transaction single-use 30-minute reset
that revokes every session and refuses to add a password to a Google-only
account, a deep-link-free backend web form, and the Flutter forgot-password
screen, all reusing the IP-2.9 hashed-token store. Their production exposure is
gated by MC-2.5; their implementation detail is in git history.

**Account deletion is not started.** It is blocked on an owner decision:
retention policy, and whether password accounts re-enter their password while
Google-only accounts must present a fresh provider assertion.

**Implementation: account deletion**

1. Require recent authentication and explicit destructive confirmation. Password-capable accounts re-enter the current password; Google-only accounts must present a fresh provider assertion that the backend verifies again. Never treat a cached profile, email match, or old RythmRun access token alone as destructive reauthentication.
2. Add a minimal `ObjectCleanupJob`/outbox table and durable runner in this phase. Each job stores the validated object key, operation, idempotency identity, status, retry count, next attempt, and safe error independently; it must survive `User`/activity cascades and must not rely on a deleted foreign-key owner row.
3. In one transaction, revoke sessions, create cleanup jobs/tombstones for avatar/activity-image objects, and delete/anonymize database rows according to the approved retention policy.
4. Do not perform irreversible S3 work before the database transaction. The initial single-replica runner is restart-safe and retries idempotently; IP-4.6 adds general leasing/multi-replica coordination and reuses it for all deletion paths.
5. Keep the account disabled/deletion-pending until required cleanup reaches the policy-defined terminal state. Do not expose the production deletion UI as complete while no runner processes the jobs.
6. After server acknowledgement, delete that user's SQLite workouts/points/status/image rows, private photo files/thumbnails, cached user metadata, secure tokens, and per-user local encryption key. Run a local orphan/file check.
7. Show queued/completed deletion state safely and prevent automatic recreation by sync.

**Tests this slice owes**

- Deletion requires recent authentication and creates cleanup records *before*
  user cascades remove ownership data.
- Cleanup rows survive user cascades, and a runner restart completes them
  without duplicate harmful work.
- Repeated cleanup is harmless.
- A deleted account cannot refresh or log in unless product policy allows a new
  registration, and old local data and files are gone.

**Account-deletion UI state (2026-08-11, `028d469`) — not a delivery**

The settings screen previously showed a full destructive-confirmation dialog —
red warning, "This action cannot be undone. All your data will be permanently
deleted", and a type-`DELETE`-to-confirm field — whose confirm button did
nothing but display *"Account deletion feature coming soon!"*. It now opens the
public deletion-request page (`docs/delete-account.md`, served from the policy
site) in an external browser, and `SettingsScreen` takes an injectable
`externalUrlLauncher` so the launch is testable.

This is recorded here so the change cannot be misread later:

- **None of the seven "Implementation: account deletion" items above is
  delivered.** There is no deletion endpoint, no reauthentication step, no
  `ObjectCleanupJob` outbox, no runner, and no local purge. The retention and
  password-versus-fresh-Google reauthentication decision gate is still open, and
  IP-2.4 is still the current canonical package.
- What it does deliver is honesty in the UI: the app no longer presents a
  confirmation ritual for a capability that does not exist. That is IP-5.6 item
  2 ("remove or label unimplemented claims") arriving early on one surface, not
  IP-2.4 progress.
- The linked page states that deletion is a manual support process rather than
  an automated flow, that device-local workouts and photos cannot be removed
  remotely, and that support confirms scope before proceeding — so the public
  text and the shipped behavior agree. Keeping them in agreement is an IP-5.6
  obligation each time either side changes.
- The "recovery, edit, delete" audit finding stays open.

### IP-2.6 — Storage boundary *(items 6-8; the abuse-control slice is delivered)*

Items 1, 2, 4, 5, 9 and the proxy-aware part of item 3 are delivered and merged
via PRs #167/#169: an exact-match `CORS_ALLOWED_ORIGINS` allowlist that is
required and https-only in production and validated before the listener binds;
`TRUST_PROXY_HOPS` driving `trust proxy` with a default of 0; in-process
sliding-window budgets on login, register, Google exchange, reset request and
submit, password change, and verification resend, charged on admission and
refunded when a failure-counting response is not 4xx; a typed
`AUTH_RATE_LIMITED` 429 with `Retry-After`; typed `ActivityImageServiceError`
replacing exact-message branching in the mounted image controller; server-minted
`X-Request-Id`; and fixed-field `security_event` lines carrying only a truncated
subject digest. Detail is in git history and the evidence log below. MC-2.6 owns
the deployed edge configuration.

Two notes worth keeping: the login budget carries a *second* ceiling of 20
failed attempts per address per 15 minutes, because the account+address key
bounds guessing one account's password but never trips against credential
spraying, where every attempt names a different account and mints a fresh key.
And budgets are charged on admission rather than on response, because an
adversarial review probe showed response-time charging admitted 40 concurrent
guesses against a limit of 5.

**What remains — items 6, 7, 8**

6. Replace upload grants that cannot enforce size at the storage boundary with an enforceable mechanism carrying an approved content type and the exact user-owned key. **Avatars did this on 2026-07-28 (`76fa16f`) and are the working model:** a presigned PUT with both `content-type` and `content-length` in the *signed* header set, so the uploader must present exactly the signed values. Do not copy the S3 POST policy this item originally suggested — Cloudflare R2 does not support presigned POST, which is why the avatar grant enforced nothing until it was corrected. Activity images still need this: `getPresignedPutUrl` already accepts a `sizeBytes` and signs `content-length` when given one, but `activity-image.service.ts` does not pass it. Server-side metadata validation after upload is still required, but it is not a storage-cost control.
7. Verify activity-image confirmation against actual S3 `ContentType`, bounded `ContentLength`, expected key, and a server-computable/checkable checksum mechanism. A client-declared checksum alone is not evidence of object integrity.
8. Add per-user object/count/byte quotas, lifecycle cleanup for abandoned uploads, and alarms for unusual presign/storage volume.

**Not delivered by this slice**

- Items 6–8: the enforceable storage-boundary upload grant for activity images
  (avatars got theirs in IP-0.4's 2026-07-28 correction),
  confirmation against actual `ContentType`/`ContentLength`/checksum,
  per-user object/count/byte quotas, abandoned-upload lifecycle cleanup, and
  presign/storage volume alarms. Changing the activity-image grant alters the
  client upload contract and needs a coordinated Flutter change plus
  real-storage proof, so it is scoped as a separate slice.
- The corresponding test bullets ("an upload exceeding the declared size is
  rejected by the storage policy…" and "wrong content type/checksum/ownership…
  and abandoned objects expire") remain unmet.

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
- [ ] Account deletion revokes active sessions and completes the required deletion lifecycle.
- [x] Repository `/users/me` exists and returns safe fields only.
- [x] Repository mobile writes and migration tests use the verified secure envelope and remove ongoing preference-token APIs.
- [ ] MC-2.3 proves physical-device migration leaves no plaintext token copy and fails safely across interruption/backup/key-loss cases.
- [x] Repository concurrent auth failures trigger one refresh and at most one eligible retry per request.
- [x] Repository offline access policy is enforced under a fake clock and user scope.
- [x] Repository profile edit works and updates local session data.
- [ ] Recovery is non-enumerating, one-use, rate-limited, and connected to an approved email provider before UI exposure. (Repository code delivers the non-enumerating request, one-use 30-minute digest token, all-session revocation, Google-only refusal, backend web form, Flutter request UI, and the IP-2.6 account+address request budget. Remaining before the box is checked: provider/staging delivery + gated production exposure under MC-2.5. Provider approved 2026-07-20 — D-018.)
- [ ] Account deletion purges/revokes correctly; its independent durable cleanup rows survive cascades and the minimal runner demonstrably processes/retries them.
- [x] Activities default/migrate private; only owners receive exact routes. (Repository-delivered 2026-07-21, merged via PR #165: `isPublic` defaults false + backfill migration, owner-only `getActivityById`. The migration's staging/production application remains a deploy step.)
- [x] Unfinished social endpoints/claims are disabled. (Friend/comment/like routers unmounted → `404`; backend and public policy pages no longer advertise them as available. Qualified release-candidate policy review remains IP-5.6.)
- [ ] CORS, rate limits, and typed auth errors are deployed and tested.
- [ ] Upload size/type/ownership is enforced at the storage boundary; actual object metadata/integrity is verified and abandoned uploads expire.
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
