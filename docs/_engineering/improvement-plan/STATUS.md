---
published: false
---

# Program status

The single live view of where the improvement program stands. If this page and a
phase file disagree, **the phase file wins** and this page is wrong.

`Complete` · `Verification` (code merged, local tests pass; hosted/device/staging
proof open) · `In progress` · `Planned` · `Blocked` · `Deferred`

**Nothing is `Complete`.** Every delivered package still owes at least one item
in [ACTION-REQUIRED.md](./ACTION-REQUIRED.md). "Merged and tested locally" is not
"done" anywhere in this program.

_Last updated: 2026-08-12 against `main` including the auth-hardening (IP-2 follow-up) slice._

## At a glance

| Phase | Status | Repo-delivered | Not started |
| --- | --- | --- | --- |
| IP-0 Security containment (P0) | **In progress** | 6 of 10 code packages | IP-0.1, 0.1A, 0.6, 0.7 — all operational |
| IP-1 Tracking correctness | **Verification** | 7 of 7 | — |
| IP-2 Auth, account, privacy | **Verification** | 7 of 8 + IP-2.9 code-delivered | IP-2.7 |
| IP-3 Workout durability | **Planned** | 0 of 5 | all |
| IP-4 Sync & restore | **Planned** | 0 of 6 | all |
| IP-5 Release readiness | **Planned** | 0 of 7 | all (5.7 `Deferred`) |

**32 manual/hosted checks, 0 verified.** One is `Blocked` (MC-0.10, pending your
approval to send the dependency inventory to npm). The rest are `Pending`.

**The single most important fact: IP-0 is a P0 release blocker and its blocking
work is operational, not code.** Containment, exposure investigation, and
credential rotation cannot be closed from the repository.

Current `main` gates: backend 510 passed / 7 skipped / 517 total locally
(517 passed / 517 total in CI with PostgreSQL enabled), typecheck clean; Flutter
353 passed; analyzer 9 issues, 0 warnings, 0 errors. The counted analyzer
baseline is stamped Flutter 3.44.1 / Dart 3.12.1 to match CI, so it can only be
checked on the pinned toolchain. The rise from 464/471 and Flutter 359 is the
auth-hardening slice (config spine, containment, refresh seams, error contract,
core hardening) net of Phase 3a's deletion of 15 dead legacy-migration tests.

## Deployment reality — corrected 2026-08-11

**Render auto-deploys the backend from `main`.** Merging is deploying; there is
no separate gate between the two. Earlier wording in this program — "merged; not
deployed", "undeployed", "repository evidence, not deploy authorization" — was
written on the assumption of a manual promotion step that does not exist. Those
statements have been corrected where found; if more survive in the phase files,
read them as "not *verified* in production" rather than "not running".

What this changes:

- **Backend security fixes are live**, not waiting. IP-0.2 through IP-0.5 and
  the IP-2 auth work are serving traffic. That is good news for exposure, and it
  does **not** close any manual check — running is not the same as proven, and
  every `ACTION-REQUIRED.md` item still stands.
- **The backend always runs newer than the installed app.** A Flutter change
  needs a Play Store release; a backend change needs a merge. Backward
  compatibility with the released app is therefore a hard rule, not a courtesy.
  It has already broken once: `76fa16f` changed the avatar upload contract on
  both sides, so the backend half went live immediately while the client half
  waits on a release — an app older than `1.2.0+21` cannot upload an avatar.
- **A merged migration is an applied-or-crashed decision, not a plan.** Two
  migrations in this repository are deliberately not rolling-compatible (the
  Google-auth nullable-password change and the auth-session rebuild) and both
  assume old instances are drained first. Auto-deploy does not drain anything.

**Open question worth confirming:** whether Render's configured build command
also runs `npm run migrate:deploy`. There is no `render.yaml` in the repository,
so the deploy sequence lives only in the Render dashboard. If the app deploys
but migrations do not, a merged schema change ships code against an old schema.
Confirm this before merging any migration.

## What's left, by package

### IP-0 — Security containment `In progress`

| Pkg | Status | Repo | What's left |
| --- | --- | --- | --- |
| 0.1 Contain production, preserve evidence | Planned | ✗ | **Operational.** MC-0.1, MC-0.2 |
| 0.1A Bootstrap isolated staging | Planned | ✗ | **Operational.** MC-0.6 — most other checks need this first |
| 0.2 Writable-field allowlists | Verification | ✓ | Merged `e33f314`, and therefore live (see the deployment note below). Re-runs under the 0.7 controlled reopen |
| 0.3 Retire filesystem avatars | Verification | ✓ | Production route-containment proof; quarantine of suspicious legacy avatar rows |
| 0.4 Harden R2 avatar pipeline | Verification | ✓ | Re-hardened `76fa16f` — presigned PUT with a signed `content-length`, no public delivery origin, explicit bucket on confirm/cleanup. MC-0.11 **must be re-run**; the old evidence is void. Quota and bucket-lifecycle rule still open |
| 0.5 Fail closed on config/secrets | Verification | ✓ | Hosted smoke proving a prod process with a bad JWT secret exits before listening |
| 0.6 Investigate exposure, rotate | Planned | ✗ | **Operational.** MC-0.2, MC-0.3, MC-0.5 |
| 0.7 Regression, staging rollout, reopen | In progress | ✗ | Corpus committed; the package is operational. MC-0.10, MC-0.12, MC-0.7–0.9 |
| 0.7-dep Dependency-surface reduction | Verification | ✓ | Committed `fc33dca`. MC-0.10 (blocked), hosted Node 22 confirmation |
| 0.7a HTTP security regressions + CI | Verification | ✓ | Committed `c52fb87`. MC-0.7, MC-0.8, MC-0.9 |

### IP-1 — Tracking correctness `Verification`

All seven delivered; each waits on a device, staging, or hosted gate.

| Pkg | Waits on |
| --- | --- |
| 1.1 Metric contracts & legacy handling | MC-1.1, MC-1.2, MC-1.3, MC-1.4 |
| 1.2 GPS acceptance & pause state machine | MC-1.5 |
| 1.3 Nullable-state repair & user-scope teardown | MC-1.6 |
| 1.4 Local ownership, FKs, indexes | MC-1.7, MC-1.9 |
| 1.5 Preserve backend history & bound payload | MC-1.8 |
| 1.6 Minimum CI & phase gates | MC-0.7, MC-0.8, MC-1.9, MC-1.10, MC-1.11, MC-1.12 |
| 1.7 Ads fail-closed until durable completion | MC-1.14 |

### IP-2 — Auth, account lifecycle, privacy `In progress`

| Pkg | Status | Repo | What's left |
| --- | --- | --- | --- |
| 2.1 Session/refresh semantics | Verification | ✓ | MC-2.1, MC-2.2 |
| 2.2 Secure mobile token storage | Verification | ✓ | MC-2.3 |
| 2.3 Offline-session behavior | Verification | ✓ | MC-2.3 |
| 2.4 Profile, recovery, deletion | Verification | ✓ | Code delivered for profile, password recovery, and account deletion slices. Production exposure gated by MC-2.5 |
| 2.5 Private routes; disable social | Verification | ✓ | Merged (PR #165, `bd78d9a`). Apply the migration on staging/production; complete the IP-5.6 policy review |
| 2.6 API abuse controls & typed errors | Verification | ✓ | Code delivered for abuse-control and storage-boundary slices (items 1–9). MC-2.6 owns deployed edge configuration |
| 2.7 Protect retained routes/photos at rest | Planned | ✗ | Not started; gated on an owner design spike (threat model, library/perf, backup and key-loss recovery) |
| 2.8 Google identity extension | Verification | ✓ | Merged `c805f62`. MC-2.4. Its no-implicit-link behavior is superseded by 2.9 |
| 2.9 Email verification & safe linking | Verification | ✓ | Merged (PR #164). MC-2.5 |

### IP-3, IP-4, IP-5 — `Planned`

Nothing delivered. See the phase files for the full specs.

- **IP-3** durable engine + checkpoint DAO · exactly-once finalize · recovery UX
  · Android foreground/screen-off tracking · remove long-session quadratic UI.
  Gated on the IP-1 metric engine and IP-2.1–2.3. The checkpoint at-rest format
  is gated on the IP-2.7 design. Its Gradle/AGP/Kotlin prerequisite landed in
  `f6b9d0a` but no build was run against it — declared, not proven.
- **IP-4** sync-state enum + retry UI · resumable `/api/v2` upload ·
  summary/detail/point projections · Postgres indexes · idempotent restore ·
  durable replica-safe deletion worker.
- **IP-5** testable server lifecycle · privacy-safe observability · release-grade
  CI · staging/release/rollback discipline · platform/monetization scope ·
  documentation reconciliation · **IP-5.7 retention epic `Deferred`**.

## Next repository work

Lowest-numbered unblocked packages. The operational IP-0 gates run in parallel
and are not substitutes.

1. **IP-2.7 retained-data protection** — gated on the owner design spike.

## Delivery history

| Date | What landed | Where |
| --- | --- | --- |
| 2026-07-20 | IP-2.9 email verification + safe Google linking | PR #164 |
| 2026-07-21 | IP-2.4 password recovery (`34a14a9` + `6b7dc97`) | PR #164 |
| 2026-07-21 | IP-2.5 route privacy (`bd78d9a`) | PR #165 |
| 2026-07-27 | IP-2.6 abuse-control slice — CORS allowlist, proxy-hop trust, request budgets, typed `AUTH_RATE_LIMITED`, typed image errors, request IDs, security events | PRs #167/#169 |
| 2026-07-28 | IP-0.4 avatar re-hardening — presigned PUT with signed `content-length`, authenticated read URLs, explicit buckets | PR #170 |
| 2026-08-11 | Release fixes — OpenStreetMap attribution, deletion-request link, `1.2.0+21`; toolchain bump; `APP_ENV` define | PR #171 |
| 2026-08-11 | IP-2.6 storage boundary slice (items 6–8) — presigned PUT with signed Content-Length/Content-Type, S3 metadata & checksum verification, user/activity quotas, abandoned upload cleanup | Local branch |
| 2026-08-11 | IP-2.4 account deletion slice — re-authentication control (password/Google token), transactional `ObjectCleanupJob` outbox, atomic user delete, `ObjectCleanupRunner`, Flutter datasource & error mapping | Local branch |
| 2026-08-12 | Auth-hardening follow-up (IP-2 seams) — tunable auth-timing config spine; M5 cleanup-runner scheduled on the sweep + M3 `DELETE /me` rate limit; client credential simplification (legacy plaintext-token migration + `requiresServerVerification` deleted) and refresh seams (same-session rotation accept, failed-flight eviction, idempotent avatar upload-url); `error`→`code` error contract across every mounted emitter; core hardening (unconsumed-reset-token invalidation, `verifyEmail` purpose guard, login-timing flattening, delete-account Google-503 pass-through); native Google sign-out on forced loss; presigned-URL-at-rest note added to the IP-2.7 threat model. A refresh-reuse grace window was tried and reverted (strict reuse detection restored). | Branch `auth-impr` (PRs #180/#181 merged; remainder local) |

Each phase file's evidence log carries the detail, including what was
deliberately *not* claimed. The auth-hardening slice's per-phase detail lives in
the [IP-2 evidence log](./IP-2-auth-account-privacy.md#evidence-log).

## Audit finding traceability

The 2026-07-10 audit findings and where each is answered. A row is not closed
until its package's manual checks carry dated evidence.

### Correctness and security findings

| Audit finding | Priority | Owner package | Required proof |
| --- | --- | --- | --- |
| Mass assignment can set `profilePicturePath` | P0 | IP-0.2 | Unknown fields rejected; explicit Prisma data test |
| Stored profile path reaches unauthenticated read and later unlink | P0 | IP-0.1, IP-0.3 | Production containment; no local route/sink; malicious seeded-row test |
| Avatar confirmation accepts an arbitrary object-storage key | P0 | IP-0.4 | Foreign/unissued/mismatched object tests |
| Possible deployed secret exposure | P0 | IP-0.1, IP-0.6 | Restricted incident disposition and credential revocation evidence |
| JWT configuration falls back to public placeholders | P0 | IP-0.5 | Startup-failure tests; deployed smoke check |
| Vulnerable production dependencies | P0/P1 | IP-0.3, IP-0.7/0.7a, IP-1.6; recheck IP-5.3 | Remove/upgrade exposed paths, triage every advisory, enforce dated CI gates |
| Average speed displays roughly 3.6× high | P1 | IP-1.1 | Exact 10 km/h fixture and versioned migration |
| Calories use double-converted speed | P1 | IP-1.1 | Calorie input spy receives km/h once |
| Movement during pause increases distance | P1 | IP-1.2 | Fake-stream pause/move/resume test |
| Finish while paused counts open pause as active | P1 | IP-1.2 | Fake-clock finish-during-pause test |
| Map rejects GPS jumps after metrics accepted them | P1 | IP-1.2 | Shared accepted-point route/metric equivalence test |
| Exact coordinates and paths appear in device logs | P1 | IP-1.2, IP-5.2 | Release-log scan and redaction tests |
| Nullable state cannot clear user/errors/workout | P1/P2 | IP-1.3 | Explicit-null contracts plus fail→success transition tests |
| User providers/tracking survive logout/account switch | P1 | IP-1.3 | A→logout→B invalidation, drains, durable local-clear retry, late-callback rejection |
| Local detail/delete uses row ID without owner | P1 | IP-1.4 | Foreign-ID denial, owner-change, and provider-result tests |
| SQLite foreign keys/cascades are disabled | P1 | IP-1.4 | Fresh/reopen and v1–v5 migration tests for FKs, orphan repair, cascades, indexes, rollback |
| Ordinary 750-point workout exceeds default JSON limit | P1 | IP-1.5, superseded by IP-4.2 | Interim 750-point fixture; bounded batch E2E |
| Nested activity arrays/domain fields weakly validated | P1 | IP-1.5, IP-4.2 | Malformed/over-limit contract tests |
| PATCH deletes status history when field omitted | P1 | IP-1.5 | Name-only PATCH preservation test |
| Token refresh broken across route, secret, claim, storage, response | P1 | IP-2.1, IP-2.2 | Expiry→single refresh→retry E2E. Auth-hardening then tightened the client seams (same-session rotation accepted, failed refresh flight evicted, idempotent avatar upload-url replay) and confirmed strict single-use reuse detection on real PostgreSQL — a refresh-reuse grace window was tried and reverted for violating the replacement-check constraint |
| Registration stores client tokens inconsistently | P1/P2 | IP-2.1, IP-2.2 | Login/register equivalent state test |
| Tokens plaintext in SharedPreferences/PostgreSQL | P1 | IP-2.1, IP-2.2 | DB digest assertion; device storage migration check |
| Logout/password change leaves access sessions usable | P1 | IP-2.1 | Revoked access/refresh integration tests |
| Public activities expose exact route points | P1 | IP-2.5 | Cross-user exact-route denial test and private migration |
| No rate limits and permissive CORS | P1/P2 | IP-2.6 | `429`, proxy, and origin tests — **code-delivered**, MC-2.6 open |
| Presigned uploads don't enforce object size; image confirmation trusts declared metadata | P1/P2 | IP-2.6 | Oversize rejection and actual-object verification. **Open for activity images.** Avatars fixed in `76fa16f` but unproven against real R2 (MC-0.11) |
| Local SQLite/routes/photos retained unencrypted | P1/P2 | IP-2.7 | Encrypted migration, file inspection, backup-exclusion, key-loss tests |
| Password recovery / profile correction / account deletion missing | P1/P2 | IP-2.4 | Recovery, edit, delete E2E and cleanup proof. Recovery and edit delivered; **deletion open** — the settings link to the public request page removes a false claim, it does not implement deletion |
| Active workout exists only in memory | P1 | IP-3.1–3.3 | Kill-at-boundary recovery suite |
| Reliable Android screen-off/background tracking missing | P1 | IP-3.4 | Physical-device locked-screen matrix |
| Long live sessions rebuild the full route repeatedly | P1/P2 | IP-3.5 | Multi-hour memory/frame/write profile |
| No remote pull/new-device restore | P1/P2 | IP-4.5 | Fresh-device idempotent restore E2E |
| Sync status/retry not actionable to the user | P1/P2 | IP-4.1 | State migration and UI/manual-retry tests |
| Activity lists eagerly return every GPS point | P1/P2 | IP-4.3 | Response schema/byte/query-count assertion |
| PostgreSQL route/history indexes missing | P1/P2 | IP-4.4 | Representative `EXPLAIN ANALYZE` evidence |
| Activity/object-storage deletion cross-system fragile | P1/P2 | IP-4.6 | DB-first outbox and worker failure tests |
| Image cleanup timer not durable/replica-safe | P1/P2 | IP-4.6 | Lease concurrency/process-death test |
| Local full-workout loading performs 2N+1 child queries | P2 | IP-4.3 | Bounded local list/detail query-count tests |

### Architecture, quality, and product findings

| Audit finding | Disposition |
| --- | --- |
| Multiple Prisma clients/pools | IP-1.6 centralized on one adapter-backed client; deployed connection measurement in MC-1.12/MC-1.13 |
| Generic/string-matched backend errors | IP-2.6 delivered typed errors in the *mounted* image controller; the auth-hardening error contract (Phase 4) then moved the stable code from `error`→`code` across every mounted emitter (auth middleware incl. `AUTH_ACCESS_INVALID`, rate-limit, activity-image) and made the Flutter client branch on `code`, deleting its `error`-string heuristic; the unmounted social controllers still branch on message strings |
| `app.ts` listens and starts jobs on import | Seam added in IP-0.5, ownership in IP-1.6; deployed shutdown is MC-1.13, readiness maturity IP-5.1 |
| Environment loads after imported R2 dependencies | Fixed in IP-0.5 and live; a deployed fail-closed smoke is still owed (MC-0.5 area) |
| Health ignores dependencies; cold start slow | IP-5.1 |
| No proven operational CI; narrow HTTP security coverage | Definitions in IP-0.7a/IP-1.6; proof in MC-0.7–0.9, MC-1.9–1.11; expansion IP-5.3 |
| 159 analyzer findings historically; 9 informational now | Baseline protection IP-1.6, reduction through IP-2, release gate IP-5.3 |
| Large mixed-responsibility DB/UI files | Extract only phase-required seams; broader cleanup deferred |
| Duplicate map/formatting logic | IP-1.1/1.2/3.5 — one formatter, one accepted-point route |
| `/home` route has no route-level auth guard | IP-2.2 |
| Duplicate local/object-storage avatar implementations | Local pipeline removed in IP-0.3/0.4; deployed route inventory remains |
| Conflicting Android Gradle files | Duplicate authority removed in `a9f2535`; toolchain bumped in `f6b9d0a`; foreground-service/signing/release proof stays IP-3.4/IP-5.5 |
| Google identity added outside the audit sequence | Merged; MC-2.4 owns migration, console, device, branding, optional iOS |
| Connectivity may never emit initial state; polls public DNS | IP-4.1 |
| iOS configuration/readiness incomplete | IP-5.5 — prove it or declare Android-only |
| Production ad IDs / early monetization | IP-5.5/5.7 |
| Stale README/backend/config/privacy claims | IP-5.6. Includes the open fact that both map screens fetch tiles from `tile.openstreetmap.org` while the privacy policy describes no third-party contact |
| Missing notes/name capture despite model support | IP-5.7 |
| Missing trends/personal bests/goals/streaks | IP-5.7 after release controls |
| Social backend routes broken / no frontend journey | Disabled in IP-2.5; needs a privacy/moderation plan before revival |
| History search state/SQL lacks UI path | Deferred — lower ROI than current P0/P1 work |
| Imperial setting does not affect output | Deferred; IP-1 formatters make it safer later |
| Offline map implementation commented out | Deferred |
| Banner ads unused | Deferred |
| Large image decode/resize on the UI isolate | IP-3.5; verify under IP-5.7 |
| Unused dependencies and dead/commented files | IP-5.3/5.6 cleanup after safety gates |
| Domain interfaces depend on models inside the monolithic DB service | Extract only phase-required seams in IP-1/IP-3 |
| Activity/status/friend states are free-form strings | Allowlists in IP-1/IP-4; social states deferred |
| Friend uniqueness directional; comments unbounded | Social endpoints disabled; redesign deferred |
| R2 scope, bucket access, encryption/lifecycle, DB TLS/backups unverifiable | IP-0.6 (MC-0.5); IP-5.4 ongoing drills |
| Data export / profile sharing / notifications / help | Deferred |
| Larger IDs / partitioning / cursor pagination at scale | Measure in IP-4; implement only where evidence supports it |

## Invariants not to regress

The audit also identified strengths. Every phase preserves them:

- local-first completed workout saving;
- `(userId, clientSyncId)` idempotency;
- queued remote workout deletion;
- durable activity-image upload/retry/replace/delete states;
- local durable photo originals and thumbnails;
- lightweight local history list with detail-only route loading;
- direct-to-R2 upload and signed media reads after hardening.
