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
- Current repository package: IP-1.3 explicit nullable-state clearing, coordinated user-scope teardown, live/sync/profile/auth operation draining, durable credential-cleanup recovery, and A→B cache isolation. This is repository work only; MC-1.6 remains open.
- Manual/hosted gates: [MC-0.1 through MC-0.12 and MC-1.1 through MC-1.6](./MANUAL-CHECKS.md), including hosted CI, dependency review, security operations, metric sampling/backups, compatibility, GPS and account-exit device proof, staging, and controlled rollout.
- Concurrent owner action: IP-0.6 exposure review and credential rotation decision.

## P0/P1 findings

| Audit finding | Priority | Planned owner | Required proof |
| --- | --- | --- | --- |
| Mass assignment can set `profilePicturePath` | P0 | IP-0.2 | Unknown fields rejected; explicit Prisma data test |
| Stored profile path reaches unauthenticated read and later unlink | P0 | IP-0.1, IP-0.3 | Production containment; no local route/sink; malicious seeded-row test |
| Avatar confirmation accepts arbitrary S3 key | P0 | IP-0.4 | Foreign/unissued/mismatched object tests |
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
| Local detail/delete uses row ID without owner | P1 | IP-1.4 | Known foreign-ID read/delete tests |
| SQLite foreign keys/cascades are disabled | P1 | IP-1.4 | `foreign_keys`, cascade, migration, `foreign_key_check` tests |
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
| Activity/S3 deletion is cross-system fragile | P1/P2 | IP-4.6 | DB-first outbox and worker failure tests |
| Image cleanup timer is not durable/replica-safe | P1/P2 | IP-4.6 | Lease concurrency/process-death test |
| Local full-workout loading performs 2N+1 child queries | P2 | IP-4.3 | Bounded local list/detail query-count tests |

## Architecture, quality, and product findings

| Audit finding | Disposition | Planned proof or reason |
| --- | --- | --- |
| Multiple Prisma clients/pools | Avatar controller fix is merged in IP-0.4 but not deployed; remaining clients complete across IP-2.1/IP-4.6/IP-5.1 | Pool/client lifecycle tests and connection measurement |
| Generic/string-matched backend errors | IP-2.6 and IP-4 contract work | Typed error/status-code tests |
| `app.ts` listens and starts jobs on import | Minimal app/server seam is merged in IP-0.5 but not deployed; lifecycle maturity remains IP-5.1 | Import-without-socket test and graceful shutdown test |
| Environment loads after imported S3 dependencies | Fix is merged in IP-0.5 but not deployed; deployed smoke proof remains | Startup-order/config tests |
| Health ignores dependencies and cold start is slow | IP-5.1 | Liveness/readiness failure and startup timing evidence |
| No proven operational CI and narrow HTTP-level security coverage | Current IP-0.7a; expanded IP-1.6/IP-5.3 | Successful GitHub Actions run URL, Express regressions, required checks, and intentional-failure probes |
| 159 Flutter analyzer findings | Baseline protection IP-1.6; release gate IP-5.3 | No increase, then zero errors/warnings and bounded info/deprecation plan |
| Large mixed-responsibility DB/UI files | Extract only phase-required seams; broader cleanup deferred | Focused tests first; no risk-unrelated rewrite |
| Duplicate map/formatting logic | IP-1.1/IP-1.2/IP-3.5 | One unit formatter and one accepted-point route |
| Named `/home` route has no route-level auth guard | IP-2.2 | Unauthenticated direct-navigation/provider-instantiation test |
| Duplicate local/S3 avatar implementations | Local pipeline removal is merged in IP-0.3/IP-0.4; deployment remains | Deployed route inventory proves only the hardened S3 route/lifecycle remains |
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
| IAM/S3 public access, encryption/lifecycle, CloudFront origin control, DB TLS/backups were unverifiable | IP-0.6 verification; IP-5.4 ongoing drills | Restricted configuration evidence and isolated backup restore, never secrets in Git |
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
- direct-to-S3 upload and signed activity-image reads after hardening.
