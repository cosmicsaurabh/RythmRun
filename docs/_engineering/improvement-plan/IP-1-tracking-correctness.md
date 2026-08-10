---
published: false
---

# IP-1: Tracking correctness and per-user local integrity

| Field | Value |
| --- | --- |
| Status | **Verification** |
| Priority | P1 |
| Target | 7 focused work packages after IP-0 |
| Owner | Unassigned |
| Last updated | 2026-07-17 |
| Depends on | IP-0 patched deployment; incident containment remains active until IP-0 exits |
| Exit condition | Metrics, account-switch, cascade, PATCH, long-payload, and CI gates pass |

## Outcome

After this phase, a user can trust the app's distance, active duration, speed, pace, and calorie inputs; paused or rejected GPS movement cannot corrupt those metrics; completed local data is accessible only by its owner; SQLite cascades are enforced; unrelated backend edits preserve route history; and minimum CI protects the corrected behavior.

Repository-only IP-1 work was explicitly selected by the maintainer on 2026-07-11 while IP-0 operational gates remain open. No migration execution, deployment, historic-value rewrite, or production enablement is authorized by this status change; those actions remain in [ACTION-REQUIRED.md](./ACTION-REQUIRED.md).

## Why this phase is next

The audit's next highest risks are user-visible trust failures and cross-account data exposure:

- `calculateSpeed` returns km/h while `WorkoutSessionEntity.averageSpeed` and GPS speed are documented as m/s; UI and calorie code multiply by 3.6 again.
- Location collection continues while paused, and `_onLocationUpdate` still appends points and distance.
- Finishing during a still-open pause interval does not subtract that interval.
- GPS jump rejection exists in the map layer after the metric provider has already accepted the point.
- Logout leaves long-lived providers and tracking state alive.
- Local detail/delete APIs accept only a row ID, not the active user ID.
- SQLite declares cascades but does not enable `PRAGMA foreign_keys=ON` on each connection.
- Backend `PATCH` can delete status history when that property was omitted.
- A representative 750-point activity is about 103 KB, already above Express's default JSON limit.
- The tracked backend workflow has no reviewed hosted-run/required-check evidence; its initial dependency-only Prisma 7 upgrade did not include the required config, adapter, generated-client, module, or lifecycle migration; and no Flutter workflow protects the mobile fixes.

## Scope

- Canonical unit and metric-version contract.
- Pure GPS acceptance and active-distance semantics.
- Correct pause/resume/finish accounting.
- Nullable state clearing and complete user-scope teardown.
- User-scoped workout/image local access.
- SQLite foreign keys, orphan cleanup, uniqueness, and query indexes.
- Presence-aware activity PATCH behavior.
- A bounded interim activity payload contract so ordinary workouts sync until IP-4 introduces chunking.
- Minimum backend/Flutter CI.

## Non-goals

- Active-workout persistence and background service implementation; IP-3 owns those. Durable retry after an initial completed-workout local-save failure also remains IP-3; IP-1.2 keeps that workout in memory and blocks overwrite, but does not claim process-death recovery.
- Full refresh-token repair or secure token migration; IP-2 owns those.
- Cloud pull/restore or a final chunked route protocol; IP-4 owns those.
- A wholesale split of `local_db_service.dart` or large UI files. Extract only the boundaries needed to test this phase.
- Perfect calorie physiology. This phase makes units and inputs consistent and labels the result as an estimate.

## Canonical metric contract

| Value | Domain/storage/API unit | Presentation |
| --- | --- | --- |
| Distance | metres (`double`) | kilometres or selected user unit |
| Active duration | seconds at persistence/API boundaries; `Duration` in Dart | `hh:mm:ss` |
| Paused duration | seconds / `Duration` | Excluded from all active metrics |
| Average speed | metres/second | multiply by 3.6 exactly once for km/h |
| Maximum speed | metres/second | multiply by 3.6 exactly once for km/h |
| Pace | minutes/kilometre in the current Dart domain | format fractional minute as `mm:ss`; document if API adds it later |
| Calories | integer kcal estimate | show as estimated, never as a measured medical value |
| Elevation | metres | selected display unit at the UI boundary |

Any implementation that uses ambiguous names such as `calculateSpeed` must be renamed or strongly typed so the return unit is visible at the call site.

## What was delivered

All seven packages are code-delivered and merged. The step-by-step
implementation text for each was removed on 2026-08-11 once it was finished
work; git history holds it. What each package established, and what still gates
it, is below. The evidence log at the bottom of this file is the record.

| Pkg | What it established | Still gated on |
| --- | --- | --- |
| IP-1.1 Metric contracts and legacy handling | The canonical unit contract above, a `metricsVersion` provenance marker on every activity, deterministic fixtures, and additive migrations that tag legacy rows as version 1 without rewriting their values | MC-1.1 sampling, MC-1.2 migration rehearsal, MC-1.3 client compatibility, MC-1.4 rollout |
| IP-1.2 GPS acceptance and pause state machine | One acceptance policy shared by the map and the metric provider, so a point rejected for accuracy or implausible jump changes nothing anywhere. Paused movement and the first resumed sample add zero distance; finishing during an open pause closes it once | MC-1.5 on-device route run |
| IP-1.3 Nullable-state repair and user-scope teardown | Explicit-null contracts for user, error, and workout state; serialized live/auth operations; restart-safe credential cleanup; explicit active-workout exit decisions; A→B cache isolation | MC-1.6 staging isolation run |
| IP-1.4 Local ownership, foreign keys, indexes | Owner-bound local workout and image access, `PRAGMA foreign_keys` on every connection, SQLite v6 with orphan repair, duplicate quarantine, cascades, and exact indexes | MC-1.7 in-place device upgrade, MC-1.9 hosted FFI run |
| IP-1.5 Preserve backend history, bound the payload | PATCH no longer deletes omitted collections; nested validation and error output are bounded; only authenticated activity create/PATCH get the measured 3 MiB parser behind per-user admission; the client emits UTC and stops retrying permanent `400`/`413`/`422` | MC-1.8 deployed proxy and PostgreSQL run |
| IP-1.6 Minimum CI and phase gates | Stable `Backend security` and `Flutter CI` checks, pinned runners/toolchains/action commits, and the counted informational analyzer baseline | MC-0.7–0.9, MC-1.9–1.12 |
| IP-1.7 Ads fail-closed until durable completion | Advertising off by default; non-production and ads-disabled releases stay on the no-op provider; production IDs are validated before packaging; the only configurable ad opportunity sits after durable workout completion | MC-1.14 packaged-device run; IP-5.5 still owns consent, placement, and live enablement |

## Rollout and migration order

1. Add tests and metric version fields without changing interpretation.
2. Sample/approve legacy metric migration; back up SQLite fixture and production PostgreSQL data.
3. Deploy backend compatibility for both metric versions if a mixed mobile-version window exists.
4. Release the Flutter metric/pause/filter fix.
5. Run local ownership/FK migration before enabling any code that assumes cascades.
6. Deploy bounded payload and PATCH fixes; monitor `413`, `4xx`, and activity creation latency.
7. Deploy debug/staging ad safety and durable-completion gating.
8. Enable required CI checks after one successful baseline run.

## Rollback plan

- Metric migrations use a version marker and backup; rollback restores computed fields only from the captured pre-migration data, never by multiplying every row blindly.
- If the new mobile tracking policy rejects too many valid points, roll back thresholds/config while keeping the single-policy architecture and pause correctness.
- If SQLite migration fails, leave the old database intact and block destructive operations; never delete the user's database as a recovery shortcut.
- If 3 MiB handling causes resource pressure, change the domain caps and body limit together from measured fixtures; do not return silently to the unannounced 100 KiB default.
- CI can temporarily be non-required while infrastructure is repaired, but must continue reporting and cannot be marked complete until failure probes work.

## Verification matrix

| Scenario | Expected result | Evidence |
| --- | --- | --- |
| 10 km in 1 hour | Store ~2.7778 m/s; display 10.0 km/h | Unit/provider test |
| Pause, move, resume | Paused and bridge movement add 0 m | Fake-stream test + device run |
| Finish while paused | Open pause excluded exactly once | Fake-clock test |
| GPS jump then valid point | Jump rejected; valid point uses last accepted anchor | Policy/provider test |
| A logout → B login | A work drains; local clear succeeds; no A cache or late callback is visible under B | Session/provider/repository integration tests + MC-1.6 |
| Delete owned workout | All child rows cascade; foreign key check clean | SQLite migration test |
| PATCH name only | Route/status rows unchanged | Controller/service plus Prisma query-shape/stateful fake; real PostgreSQL in MC-1.8 |
| 750-point payload | Authenticated body is parsed and reaches the create handler | Final-tree socket-boundary test; persisted create in MC-1.8 |
| Oversize/malformed payload | Stable non-retryable 4xx; no partial rows | HTTP boundary plus transaction query-shape/stateful-fake coverage; real PostgreSQL proof in MC-1.8 |
| CI failure probe | Required job fails for intentional regression | CI run link |

## Exit gate

- [x] Canonical units are documented in code and covered by exact-value tests.
- [ ] Historical speed migration was sampled, backed up, versioned, and exercised safely.
- [x] Calories receive km/h exactly once and are labeled as an estimate.
- [x] Overall/per-type duration statistics subtract paused time and match detail semantics.
- [x] One GPS policy governs map, metrics, and persistence.
- [x] Paused movement and resume bridging add no active distance.
- [x] Finish-while-paused active duration is correct.
- [x] Exact coordinates are absent from release logging.
- [x] Nullable state can be explicitly cleared across all audited state models.
- [x] Logout/account switch stops user-scoped work and invalidates state.
- [ ] MC-1.6 proves idle/active/forced exit and A→B isolation on a supported release build and restart.
- [x] Every local get/mutation by row ID is owner-scoped.
- [x] SQLite foreign keys are on, orphans are handled, cascades pass, and required indexes exist in repository FFI coverage.
- [ ] SQLite host migration/DAO tests run under an explicitly initialized FFI database in CI; platform-only checks are assigned to device integration tests.
- [ ] MC-1.7 proves the v5→v6 in-place upgrade, reopen, owner denial, cascades, and forward-fix response on a supported Android release build.
- [x] Omitted PATCH collections are preserved in repository service/controller coverage; explicit empty arrays clear and non-empty arrays replace in one serializable nested update with conflict retry.
- [x] Final-tree socket coverage proves representative long-workout parsing plus invalid/oversized rejection.
- [x] Final-tree socket coverage proves the larger parser is authenticated, route-specific, concurrency guarded, and leaves unrelated routes at 100 KiB.
- [ ] MC-1.8 proves deployed proxy alignment, resource bounds, PATCH rollback, and sanitized telemetry in isolated staging.
- [x] Repository CI definitions pin backend/Flutter toolchains, preserve least privilege, run the complete suites, and protect the 20-finding informational analyzer multiset while making warnings/errors fatal.
- [ ] MC-0.7 and MC-1.9 prove successful hosted `Backend security` and `Flutter CI` execution for the reviewed commit.
- [ ] MC-0.8 and MC-1.10 prove each backend/Flutter failure path independently on temporary non-merge revisions.
- [ ] MC-0.9 and MC-1.11 prove both stable checks and reviewed CI-control ownership are required for normal merges.
- [x] Repository tests prove ads default off, development/staging cannot select production AdMob IDs, and only a newly committed local workout can reach the one-shot post-activity gate.
- [ ] MC-1.14 proves safe merged-manifest configuration and recovery-before-ads behavior on a supported Android build/device; IP-5.5 consent and live production enablement remain open.

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| 2026-07-11 | IP-1.1 | Flutter metric/state/sync/SQLite suites; Prisma validation/generation; backend build; focused activity suites | Pass locally; full backend and rollout pending | Flutter 39/39 passed, including 18/18 focused metric tests. Backend changed suites 22/22 and all non-HTTP suites 134/134 passed under Node 22; the unchanged 16-test socket suite could not be rerun because external execution approval hit its usage limit. Full backend, PostgreSQL migration exercise, production sampling, backup, compatibility, and rollout remain open. |
| 2026-07-11 | IP-1.1 | `flutter analyze`; changed-file analysis | Baseline only; no new metric findings | Repository analyzer baseline is now 45 findings (1 warning, 44 info) after the maintainer's preceding Dart-fix commit; metric/local DB files add none. |
| 2026-07-11 | IP-1.2 | Commit `c41d3dc`; pure GPS policy/timeline/route tests; provider stream and pause tests; native timestamp mapping; full Flutter suite | Pass locally; device verification pending | Flutter 71/71 passed, including 32/32 focused IP-1.2 tests. The authoritative route excludes paused/rejected points, stop time is captured before teardown, route/elevation segments break across pause and >30-second gaps, and start/reset/stop/dispose cleanup is serialized. A failed initial local save remains in memory and blocks overwrite; durable retry remains IP-3. MC-1.5 remains pending. |
| 2026-07-11 | IP-1.2 | `flutter analyze`; source scans for raw stream listeners and coordinate/timestamp logging | Pass with existing baseline only | Repository analyzer baseline is 20 informational findings and no warnings after removing tracking-path release logs. Production has one `locationStream.listen` consumer, and audited release paths contain no exact coordinate/timestamp/route logging. |
| 2026-07-11 | IP-1.3 | Nullable-state, teardown/session, live/auth/user-operation drain, profile race, restart marker, credential-clear retry, and multi-provider A→B tests; focused and full Flutter suites | Pass locally; device/staging verification pending | Focused impacted suite 77/77 and final full Flutter suite 130/130 passed. Explicit `null` clears audited optional state; active/pending live operations and admitted sync/profile/auth work finish or block before invalidation; local-clear failure stays recoverable across restart; history/detail/image/live/profile/calculator/password/tab/sync state is recreated before B. MC-1.6 remains pending. |
| 2026-07-11 | IP-1.3 | `flutter analyze`; `git diff --check`; independent integration review | Pass with existing analyzer baseline only | Analyzer reports the existing 20 informational findings and zero warnings/errors; the IP-1.3 diff adds none. Natural end-to-end refresh/revocation and strict offline-window enforcement remain IP-2, local DAO ownership remains IP-1.4, and durable recovery of a workout lost by process death remains IP-3. |
| 2026-07-11 | IP-1.4 | Fresh/reopen schema; v1–v5 and shipped-v3-hybrid migrations; owner-denial/cascade/queue/image/provider/sync races; focused and full Flutter suites | Pass locally; hosted/device verification pending | Database-focused FFI suite 21/21, activity-image repository suite 20/20, workout sync/duplicate suite 4/4, sync coordinator suite 3/3, and full Flutter suite 165/165 passed. Exact indexes/FKs, transactional orphan repair and rollback, one uploadable duplicate identity, owner-bound row operations, late-completion denial, claimed-operation auth retry, and idempotent remote deletion are covered. Hosted Flutter CI and MC-1.7 remain open. |
| 2026-07-11 | IP-1.4 | `flutter analyze`; `git diff --check`; independent migration/ownership/evidence review | Pass with existing analyzer baseline only | Analyzer reports the existing 20 informational findings and zero warnings/errors; IP-1.4 adds none. Android in-place migration/backup/forward-fix proof, physical orphan-image file cleanup, and hosted CI are not claimed. |
| 2026-07-11 | IP-1.5 | Activity DTO/controller/domain/service suites; all backend non-socket suites; Flutter HTTP/model/repository suites and full suite; Prisma validation; backend build | Executed local gates pass; final socket/staging/hosted verification pending | Focused backend activity coverage 94/94 and all final-tree non-socket backend coverage 206/206 passed. Focused changed Flutter coverage 43/43 and the full Flutter suite 181/181 passed. The updated socket suite now covers the HTTP maximum fixture, POST/PATCH parser failures, case-insensitive auth/parser ordering, ordinary activity routes, and admission release, but its final-tree rerun could not obtain external execution approval after the local quota was exhausted; the earlier 13/13 predecessor run is not treated as final evidence. Owner-scoped serializable PATCH preserve/clear/replace, bounded adversarial validation, permanent/retryable mobile classification, account-switch halting, UTC instant preservation, idempotency, and stateful transaction-fake behavior are covered. MC-1.8 and hosted CI remain open. |
| 2026-07-11 | IP-1.5 | Backend build and Prisma validation; `flutter analyze`; `git diff --check`; independent payload/transaction/documentation reviews | Pass with existing analyzer baseline | No Prisma or SQLite migration is included. Flutter reuses the v6 `sync_blocked_reason` column and adds UTC serialization plus permanent rejection classification. Analyzer reports the existing 20 informational findings and zero warnings/errors, with none in IP-1.5 files. The admission guard is deliberately process-local and interim; deployed proxy sizing, memory/latency, real PostgreSQL rollback, previous-client timestamp compatibility, and sanitized telemetry are not claimed by local tests. |
| 2026-07-13 | IP-1.6 | Prisma 7.8 config/adapter/client migration; native NodeNext ESM conversion; shared database/server lifecycle; clean install, schema/type/build/test/built-smoke gates; Flutter CI/analyzer baseline package | Pass locally; hosted/deployed gates pending | The earlier Prisma 6.10.1 rollback checkpoint is superseded by the complete Prisma 7.8 modernization. Under Node 22.22.3, `npm ci --no-audit` restored 612 packages; Prisma 7.8 validation/generation, production typecheck/build, 15/15 native ESM suites and 244/244 tests, and the built health/auth/shutdown smoke passed. The unchanged Flutter package retains 189/189 tests, three-file format proof, and an exact 20-information/zero-warning/zero-error analyzer result. MC-0.7/0.8/0.9, MC-1.9/1.10/1.11, real PostgreSQL gate MC-1.12, and artifact/deployed-shutdown gate MC-1.13 remain pending. |
| 2026-07-13 | IP-1.7 | Ads resolver/factory/service/source contracts; durable completion/gate/provider/recovery tests; full Flutter suite; analyzer baseline; Android debug merged manifest; direct and generic-task incomplete-production probes | Repository gates pass; packaged device proof pending | Flutter 218/218 passed serially. All 22 changed Dart files are formatted; analysis has 19 informational findings, zero warnings/errors, and the committed 20-finding baseline accepts the one removal. `processDebugMainManifest` resolves the official Google sample application ID, sets delayed measurement initialization to `true`, and omits all four ad/privacy permissions. Production ads enabled without IDs fail configuration with the two missing keys even through the generic Gradle `tasks` entry point, proving validation no longer depends on release-task name matching. A full debug APK retry passed manifest/code stages but exhausted host disk during generated asset/native merging, so no artifact/device claim is made; MC-1.14 remains pending. IP-5.5 still owns consent, placement approval, live-ID packaging, and production enablement. |
