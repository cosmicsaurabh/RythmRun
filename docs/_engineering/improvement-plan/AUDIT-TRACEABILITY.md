---
published: false
---

# Audit finding traceability

This matrix maps the 2026-07-10 read-only audit to the implementation program. It prevents lower-visibility findings from being lost while keeping phase order driven by security, correctness, privacy, and data durability.

Merged repository implementation evidence is recorded in the IP-0 phase log. A finding is not considered deployed or production-verified until the applicable migration, staging, deployment, incident, and operational evidence is also present.

Hosted and human-operated evidence is tracked in the [manual verification register](./MANUAL-CHECKS.md); repository commits and local tests do not close those checks.

## Current selection

- Human-operated action now: [IP-0.1 production containment and evidence preservation](./IP-0-security-containment.md).
- Merged code delivery: the IP-0.2 through IP-0.5 profile/avatar security slice and its local automated suite are in `origin/main` through `e33f314`/`54a5b26`. Migration, coordinated mobile rollout, staging proof, deployment, and production verification remain open.
- Repository-delivered; hosted verification pending: IP-0.7a Express HTTP security regressions and minimum backend CI are committed in `c52fb87`; do not call CI operational until MC-0.7 through MC-0.9 pass.
- Repository-delivered; advisory verification pending: IP-0.7 dependency-surface reduction is committed in `fc33dca`; the dated advisory gate remains open until MC-0.10 records an approved scan and reviewed disposition for every result.
- Repository-delivered; rollout pending: IP-1.1 canonical metrics and provenance are committed in `ba7b288`; production migration and rollout remain gated.
- Repository-delivered; device verification pending: IP-1.2 one GPS acceptance policy, deterministic pause timing, provider-owned route state, and shared map/elevation segmentation is committed in `c41d3dc`; MC-1.5 remains open.
- Repository-delivered; device/staging verification pending: IP-1.3 explicit nullable-state clearing, coordinated user-scope teardown, live/sync/profile/auth operation draining, durable credential-cleanup recovery, and A→B cache isolation is committed in `06369b7`; MC-1.6 remains open.
- Repository-delivered; device/hosted verification pending: IP-1.4 owner-bound local workout/image/queue access and SQLite v6 foreign-key, migration, cascade, duplicate-quarantine, and index enforcement is committed in `a976f4c`; MC-1.7 Android migration proof and hosted FFI execution remain open.
- Repository-delivered; staging verification pending: IP-1.5 presence-aware serializable PATCH collection replacement, bounded pre-transform activity validation/error output, and a measured route-specific 3 MiB activity parser behind authentication and interim admission are committed in `d2c1b95`. The mobile client emits UTC timestamps and records permanent `400`/`413`/`422` sync rejections while leaving auth, admission, server, and network failures retryable. Deployed proxy/resource/PostgreSQL rollback/concurrency and timestamp-compatibility proof remain open under MC-1.8.
- Repository-delivered; hosted verification pending: IP-1.6 retains the stable backend check and completes the Prisma 7.8 migration with Prisma Config, generated TypeScript under `src`, the PostgreSQL adapter, one DI-owned client/pool, native NodeNext ESM, explicit server/main cleanup, production build validation, and a built no-database runtime smoke. It also adds pinned Flutter CI with locked restore, merge-base-changed formatting, fatal warning/error analysis, a counted informational baseline, and the full Flutter suite. Node 22.22.3 clean install, Prisma validation/generation, production typecheck/build, all 15 native ESM suites and 244 tests, and the built smoke passed locally; hosted success, independent failure probes, protected CI review, required checks, and real PostgreSQL/deployment proof remain open.
- Repository-delivered; hosted/staging verification pending: IP-2.1 is committed in `d8f6a9f` and replaces plaintext backend refresh rows with digest-only bounded sessions, standard claims, serializable rotation/replay revocation, active-session access checks, presented-session logout, all-session password revocation, and safe `/users/me`. The disposable-PostgreSQL CI suite and destructive staging cutover remain pending under MC-2.1/MC-2.2.
- Repository-delivered; device verification pending: IP-2.2 stores the mobile access/refresh pair in one verified secure envelope, migrates coherent IP-2.1 preferences without token-loss windows, centralizes revision-safe refresh and exact invalid-session quarantine, gates offline admission, revokes local state immediately after password change, removes raw-token APIs, and guards every production `/home` construction. The locked restore, 275 Flutter tests, analyzer/baseline gates, and Android debug build pass locally; MC-2.3 retains device, upgrade, backup, log, and staging proof.
- Repository-delivered; device verification pending: IP-2.3 anchors offline admission to an integrity-sensitive secure verification timestamp bounded to seven days, fails closed on clock rollback below a persisted observed high-water mark, future-dated verification, or window overrun without deleting completed local data, keeps the five-branch startup state machine, reuses IP-1.4 owner-scoped queries, and adds a data-layer online-operation guard that denies password change, avatar upload, and coordinated sync in offline mode. The locked restore, 291 Flutter tests, analyzer/baseline gates, formatting, Android debug build, and an independent adversarial multi-agent review (two confirmed medium clock-observation defects fixed and retested) pass locally; MC-2.3 retains device offline/rollback, airplane-mode-versus-revocation, backup, and log proof.
- Current package under review (profile slice delivered): IP-2.4's profile-edit slice makes `PUT /profile` return the updated safe `/me`-shaped user with unchanged mass-assignment rejection and gives the mobile app a name-edit flow that commits only server-confirmed, same-owner first/last name through the authenticated coordinator and is denied offline by the IP-2.3 guard. Backend typecheck, 281 executable Jest tests, production build, and built smoke plus the 302-test Flutter suite, analyzer/baseline, formatting, and Android debug build pass locally. Password recovery stays blocked on the email-provider decision and account deletion stays undelivered; the "recovery, edit, delete" audit finding remains open until all three slices land and MC-level proof exists.
- Manual/hosted gates: [MC-0.1 through MC-0.12, MC-1.1 through MC-1.14, and MC-2.1 through MC-2.3](./MANUAL-CHECKS.md), including hosted CI, independent failure probes, required checks, dependency review, security operations, metric sampling/backups, compatibility, GPS/account-exit/database-migration/device proof, bounded-ingest staging, real PostgreSQL/TLS/pool/migration proof, auth-session concurrency/cutover, secure mobile credential migration, artifact/deploy ordering, SIGTERM cleanup, ad-device safety, and controlled rollout.
- Concurrent owner action: IP-0.6 exposure review and credential rotation decision.

## P0/P1 findings

| Audit finding | Priority | Planned owner | Required proof |
| --- | --- | --- | --- |
| Mass assignment can set `profilePicturePath` | P0 | IP-0.2 | Unknown fields rejected; explicit Prisma data test |
| Stored profile path reaches unauthenticated read and later unlink | P0 | IP-0.1, IP-0.3 | Production containment; no local route/sink; malicious seeded-row test |
| Avatar confirmation accepts an arbitrary object-storage key (historically S3; current adapter targets R2) | P0 | IP-0.4 | Foreign/unissued/mismatched object tests |
| Possible deployed secret exposure | P0 | IP-0.1, IP-0.6 | Restricted incident disposition and credential revocation evidence |
| JWT configuration falls back to public placeholders | P0 | IP-0.5 | Startup-failure tests; deployed smoke check |
| Vulnerable production dependencies, including Multer/validator and the remaining dated advisories | P0/P1 | IP-0.3, IP-0.7/IP-0.7a, IP-1.6; recheck IP-5.3 | Remove/upgrade exposed paths, triage every advisory, then enforce dated CI/release gates |
| Average speed displays roughly 3.6× high | P1 | IP-1.1 | Exact 10 km/h fixture and versioned migration |
| Calories use double-converted speed | P1 | IP-1.1 | Calorie input spy/fixture receives km/h once |
| Movement during pause increases distance | P1 | IP-1.2 | Fake-stream pause/move/resume test |
| Finish while paused counts open pause as active | P1 | IP-1.2 | Fake-clock finish-during-pause test |
| Map rejects GPS jumps after metrics already accepted them | P1 | IP-1.2 | Shared accepted-point route/metric equivalence test |
| Exact coordinates and paths appear in device logs | P1 | IP-1.2, IP-5.2 | Release-log scan and redaction tests |
| Nullable state cannot clear user/errors/workout | P1/P2 | IP-1.3 | Explicit-null contracts plus fail→success transition tests for every audited state |
| User providers/tracking survive logout/account switch | P1 | IP-1.3 | A→logout→B invalidation, live/auth/user-work drains, durable local-clear retry, and late-callback rejection tests |
| Local detail/delete uses row ID without owner | P1 | IP-1.4 | Known foreign-ID workout/image/queue read and mutation denial, owner-change, and provider-result tests |
| SQLite foreign keys/cascades are disabled | P1 | IP-1.4 | Fresh/reopen and v1–v5 plus shipped-v3-hybrid migration tests for `foreign_keys`, orphan repair, cascades, exact indexes, rollback, and `foreign_key_check` |
| Ordinary 750-point workout exceeds default JSON limit | P1 | IP-1.5, superseded by IP-4.2 | Interim 750-point fixture; bounded batch E2E |
| Nested activity arrays/domain fields are weakly validated | P1 | IP-1.5, IP-4.2 | Malformed/over-limit contract tests |
| PATCH deletes status history when field omitted | P1 | IP-1.5 | Name-only PATCH preservation test |
| Token refresh is broken across route, secret, claim, storage, and response | P1 | IP-2.1, IP-2.2 | Expiry→single refresh→retry E2E |
| Registration stores client tokens inconsistently with UI/backend session | P1/P2 | IP-2.1, IP-2.2 | Login/register equivalent state test |
| Tokens are plaintext in SharedPreferences/PostgreSQL | P1 | IP-2.1, IP-2.2 | DB digest assertion; device storage migration check |
| Logout/password change leaves access sessions usable | P1 | IP-2.1 | Revoked access/refresh integration tests |
| Public activities expose exact route points | P1 | IP-2.5 | Cross-user exact-route denial test and private migration |
| No rate limits and permissive CORS | P1/P2 | IP-2.6 | `429`, proxy, and origin tests |
| Presigned uploads do not enforce object size; image confirmation trusts incomplete metadata/checksum claims | P1/P2 | IP-2.6 | Storage-policy oversize rejection and actual-object verification tests |
| Local SQLite/routes/photos are retained unencrypted | P1/P2 | IP-2.7 | Encrypted migration, file inspection, backup-exclusion, and key-loss tests |
| Password recovery/profile correction/account deletion missing | P1/P2 | IP-2.4 | Recovery, edit, delete E2E and cleanup proof |
| Active workout exists only in memory | P1 | IP-3.1–IP-3.3 | Kill-at-boundary recovery suite |
| Reliable Android screen-off/background tracking missing | P1 | IP-3.4 | Physical-device locked-screen matrix |
| Long live sessions copy/rebuild full route repeatedly | P1/P2 | IP-3.5 | Multi-hour memory/frame/write profile |
| No remote pull/new-device restore | P1/P2 | IP-4.5 | Fresh-device idempotent restore E2E |
| Sync status/retry is not actionable to the user | P1/P2 | IP-4.1 | State migration and UI/manual-retry tests |
| Activity lists eagerly return every GPS point | P1/P2 | IP-4.3 | Response schema/byte/query-count assertion |
| PostgreSQL route/history indexes are missing | P1/P2 | IP-4.4 | Representative `EXPLAIN ANALYZE` evidence |
| Activity/object-storage deletion is cross-system fragile | P1/P2 | IP-4.6 | DB-first outbox and worker failure tests |
| Image cleanup timer is not durable/replica-safe | P1/P2 | IP-4.6 | Lease concurrency/process-death test |
| Local full-workout loading performs 2N+1 child queries | P2 | IP-4.3 | Bounded local list/detail query-count tests |

## Architecture, quality, and product findings

| Audit finding | Disposition | Planned proof or reason |
| --- | --- | --- |
| Multiple Prisma clients/pools | IP-1.6 repository code centralizes all request/service access on one adapter-backed Prisma client and removes the unused per-request constructor; deployment remains unverified | Factory/lifecycle tests plus real connection measurement across deployed replicas in MC-1.12/MC-1.13 |
| Generic/string-matched backend errors | IP-2.6 and IP-4 contract work | Typed error/status-code tests |
| `app.ts` listens and starts jobs on import | IP-0.5 introduced the seam and IP-1.6 adds native-ESM `main`/`server` ownership plus shared cleanup; deployed bounded shutdown/readiness maturity remains IP-5.1 | Built import/runtime smoke, deployed SIGTERM gate MC-1.13, and later readiness/grace-deadline tests |
| Environment loads after imported S3-compatible R2 dependencies | Fix is merged in IP-0.5 but not deployed; deployed smoke proof remains | Startup-order/config tests |
| Health ignores dependencies and cold start is slow | IP-5.1 | Liveness/readiness failure and startup timing evidence |
| No proven operational CI and narrow HTTP-level security coverage | Current IP-0.7a; expanded IP-1.6/IP-5.3 | Successful GitHub Actions run URL, Express regressions, required checks, and intentional-failure probes |
| Historical 159 Flutter analyzer findings; current tree has 10 information findings and no warning/error, but no hosted gate yet | Baseline protection IP-1.6; reduction continued in IP-2.2; release gate IP-5.3 | Counted fingerprint baseline does not increase; hosted warning/new-info probes fail; remaining information backlog is then reduced |
| Large mixed-responsibility DB/UI files | Extract only phase-required seams; broader cleanup deferred | Focused tests first; no risk-unrelated rewrite |
| Duplicate map/formatting logic | IP-1.1/IP-1.2/IP-3.5 | One unit formatter and one accepted-point route |
| Named `/home` route has no route-level auth guard | IP-2.2 | Unauthenticated direct-navigation/provider-instantiation test |
| Duplicate local/object-storage avatar implementations | Local pipeline removal is merged in IP-0.3/IP-0.4; deployment remains | Deployed route inventory proves only the hardened R2 route/lifecycle remains |
| Conflicting Android Gradle files | Fix in IP-3.4; verify in IP-5.5 | One authoritative clean foreground-service/release build configuration |
| Connectivity may never emit initial connected state and polls public DNS | IP-4.1 | Immediate-state/provider tests; probe removed |
| iOS configuration/readiness incomplete | IP-5.5 | Fully proven device gate or explicit Android-only scope |
| Production ad IDs/early monetization | IP-5.5/IP-5.7 | Environment IDs, consent, and post-value placement tests |
| Stale README/backend/config/privacy claims | IP-5.6 | Release-candidate documentation verification |
| Missing notes/name capture despite model support | IP-5.7 | Offline post-workout journal flow |
| Missing trends/personal bests/goals/streaks | IP-5.7 after release controls | Metric fixtures and measured adoption |
| Social backend routes broken/no frontend journey | Disabled in IP-2.5; feature deferred | Privacy/moderation/product plan required before revival |
| History search state/SQL lacks UI path | Deferred until trust/release gates | Lower ROI than current P0/P1 work |
| Imperial setting does not affect output | Deferred product backlog; formatters from IP-1 make later implementation safer | Separate unit-presentation acceptance plan required |
| Offline map implementation is commented out | Deferred | Not required for reliable local workout recording |
| Banner ads unused | Deferred | Monetization expansion is not a trust prerequisite |
| Large image decode/resize work runs on the UI isolate | IP-3.5; verify under IP-5.7 expansion | Frame/performance and durable-image failure tests |
| Unused dependencies and dead/commented files | IP-5.3/IP-5.6 cleanup after safety gates | Dependency scan and verified removal; avoid unrelated early refactors |
| Domain interfaces depend on models inside the monolithic local DB service; feature layout is mixed | Extract only phase-required domain/DAO seams in IP-1/IP-3; broader structure deferred | Dependency-boundary tests and no unrelated rewrite |
| Activity/status/friend states are free-form strings | Activity/status allowlists in IP-1/IP-4; social states deferred while routes disabled | DTO/DB constraint tests for active product paths |
| Friend uniqueness is directional and comments/friend requests are unbounded | Social endpoints disabled in IP-2.5; schema/pagination redesign deferred | No exposed journey until privacy/moderation and an explicit social plan |
| R2 credential scope, bucket access/delivery, encryption/lifecycle, and DB TLS/backups were unverifiable | IP-0.6 verification; IP-5.4 ongoing drills | Restricted configuration evidence and isolated backup restore, never secrets in Git |
| Data export/profile sharing/notifications/help | Deferred | Re-prioritize after IP-5 based on user evidence |
| Larger IDs/partitioning/cursor pagination at high scale | Measure in IP-4; implement only where evidence supports it | Avoid premature infrastructure |

## Invariants not to regress

The audit also identified strengths. Every phase must preserve them:

- local-first completed workout saving;
- `(userId, clientSyncId)` idempotency;
- queued remote workout deletion;
- durable activity-image upload/retry/replace/delete states;
- local durable photo originals/thumbnails;
- lightweight local history list with detail-only route loading;
- direct-to-R2 upload and signed activity-image reads after hardening.
