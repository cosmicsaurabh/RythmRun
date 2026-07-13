---
published: false
---

# IP-1: Tracking correctness and per-user local integrity

| Field | Value |
| --- | --- |
| Status | **In progress** |
| Priority | P1 |
| Target | 7 focused work packages after IP-0 |
| Owner | Unassigned |
| Last updated | 2026-07-13 |
| Depends on | IP-0 patched deployment; incident containment remains active until IP-0 exits |
| Exit condition | Metrics, account-switch, cascade, PATCH, long-payload, and CI gates pass |

## Outcome

After this phase, a user can trust the app's distance, active duration, speed, pace, and calorie inputs; paused or rejected GPS movement cannot corrupt those metrics; completed local data is accessible only by its owner; SQLite cascades are enforced; unrelated backend edits preserve route history; and minimum CI protects the corrected behavior.

Repository-only IP-1 work was explicitly selected by the maintainer on 2026-07-11 while IP-0 operational gates remain open. No migration execution, deployment, historic-value rewrite, or production enablement is authorized by this status change; those actions remain in the [manual verification register](./MANUAL-CHECKS.md).

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

## Ordered work packages

### IP-1.1 — Establish metric contracts, deterministic tests, and legacy handling

**Primary files**

- `rythmrun_frontend_flutter/lib/core/utils/calculation_helper.dart`
- `rythmrun_frontend_flutter/lib/domain/entities/workout_session_entity.dart`
- `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/models/live_tracking_state.dart`
- `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/providers/live_tracking_provider.dart`
- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart`
- `RythmRun_backend_nodejs/prisma/schema.prisma`
- A new Prisma migration and new Flutter database migration
- New tests under `rythmrun_frontend_flutter/test/core/utils/` and the live-tracking test folders

**Implementation**

1. Replace/rename the speed helper to return metres/second, for example `calculateAverageSpeedMetersPerSecond(distanceMeters, activeDuration)`.
2. Keep display conversion in a formatter/presentation helper. `formattedAverageSpeed` converts m/s → km/h once.
3. Pass `averageSpeedMps * 3.6` once to the existing calorie estimator, whose parameter name remains explicitly `averageSpeedKmh`.
4. Correct the entity comment for pace to match actual minutes/km behavior, or introduce a value type if the team chooses seconds/km. Do not change storage and formatter independently.
5. Add a `metrics_version` (or equivalent explicit version) to local and backend activity records before changing interpretation.
6. Do not blindly divide every historic value by 3.6. Before production migration:
   - back up data;
   - sample `distance`, active `duration`, stored `avgSpeed`, and their ratio;
   - prove the affected version range consistently stored km/h;
   - recompute canonical m/s as `distanceMeters / activeDurationSeconds` wherever inputs are valid;
   - mark invalid/zero-duration records for safe fallback rather than manufacturing a value.
7. Recompute legacy calorie estimates only when the exact historic inputs/default-weight rule are known. Otherwise preserve them as legacy estimates and ensure all new records use the corrected version.
8. Make the migration idempotent and version-guarded so rerunning cannot divide/recompute twice.
9. Correct local statistics queries to subtract `paused_duration` from wall-clock `end_time - start_time` for totals/averages, clamp corrupt negative values safely, and use the same active-duration definition as workout detail/backend sync.

**Automated tests**

- `10,000 m / 3,600 s = 2.777... m/s` and displays `10.0 km/h`.
- `1,000 m / 360 s` has the same 10 km/h display.
- Zero/negative distance or duration returns safe zero/null values as specified.
- Calorie estimator receives `10 km/h`, not `36 km/h`.
- Pace for 5 km in 25 minutes formats as `5:00` min/km; a near-boundary `5.999` formats as `6:00`, and non-finite inputs use the safe placeholder.
- A version-1 fixture migrates once; a version-2 fixture remains unchanged.
- Unsupported metric versions are rejected by both the local write boundary and SQLite constraint.
- A corrupt/zero-duration legacy row is not divided or assigned infinity/NaN.
- Negative and overlong pause values are normalized consistently for detail, persistence, and sync.
- Overall and per-type statistics exclude paused time and match the sum of fixture active durations.

**Acceptance**

- Unit names and tests make a second 3.6 conversion difficult to introduce.
- New local and backend rows agree on m/s.
- Production migration has a sampled-data approval and rollback backup.

### IP-1.2 — Create one GPS acceptance and pause state machine

**Primary files**

- `rythmrun_frontend_flutter/lib/core/services/live_tracking_service.dart`
- `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/providers/live_tracking_provider.dart`
- `rythmrun_frontend_flutter/lib/presentation/features/Map/screens/live_map_feed.dart`
- `rythmrun_frontend_flutter/lib/domain/repositories/live_tracking_repository.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/live_tracking_repository_impl.dart`
- New pure policy under `rythmrun_frontend_flutter/lib/domain/` or `lib/core/tracking/`
- New tests under `test/core/tracking/` and `test/presentation/features/live_tracking/providers/`

**Architecture decision**

Every raw point passes through one pure acceptance policy before it reaches distance, pace, maximum speed, persistence, or the drawn route. The map consumes accepted provider state and no longer has a second singleton GPS subscription or a competing jump filter.

Repository delivery uses GPS policy version 1 within the not-yet-deployed metrics-version-2 contract. If version 2 is released before this package, assign distinct persisted policy provenance rather than silently changing its meaning.

**Implementation**

1. Make the location stream and clock injectable through `LiveTrackingRepository`; the notifier must not subscribe directly to `LiveTrackingService.instance`.
2. Define a pure acceptance result containing at least `accepted/rejected`, a safe reason code, and whether the point can advance the active-distance anchor.
3. Commit the initial policy constants with fixture rationale: maximum horizontal accuracy 50 m; strictly positive timestamp delta; reset (do not bridge) the distance anchor after an active sample gap over 30 seconds; maximum implied speed 10 m/s running, 5 m/s walking/hiking, and 30 m/s cycling. Changing these values requires fixture/device evidence and a policy-version update.
4. Validate:
   - latitude/longitude ranges and the `(0,0)` sentinel policy;
   - finite numeric values;
   - configured accuracy ceiling;
   - strictly increasing timestamps;
   - distance and implied-speed plausibility for the workout type;
   - optional reported speed bounds without trusting reported speed alone.
5. On an active point:
   - compare with the last **accepted active** point;
   - add distance only when accepted;
   - append only accepted route points to the authoritative route;
   - update pace/max speed from accepted active points.
6. While paused:
   - a raw point may update a current-location marker if the privacy/product decision allows it;
   - it must not append to the active route or change distance, pace, max speed, elevation, or calories;
   - clear the active-distance anchor.
7. On resume, the first accepted point establishes a new anchor and adds zero distance. This prevents a straight bridge across paused displacement.
8. When stopping while paused, close the open pause interval at the stop timestamp exactly once before calculating active duration.
9. Use an injected clock for start/pause/resume/stop and timer tests. Clamp or reject impossible negative durations rather than silently persisting them.
10. Remove exact coordinate/timestamp/path logging from release paths. Debug logs use safe event/reason codes and must be guarded.

**Automated tests**

- Active → pause → large movement → resume: paused movement adds zero and first resumed point adds zero.
- Finish while paused subtracts the open interval once.
- Pause/resume repeated several times produces exact active duration.
- Inaccurate point, non-monotonic timestamp, non-finite coordinate, unrealistic jump, and unrealistic implied speed are rejected everywhere.
- A valid point after a rejected jump compares with the last accepted point, not the rejected point.
- Map route and metric route contain the same ordered accepted timestamp/coordinate sequence and count (or the same stable sequence once IP-3 introduces it).
- A mock location stream has one subscriber for the active workout path.

**Manual verification**

- Walk/run a known short route, pause for deliberate movement, resume, and compare recorded distance to the active route only.
- Check that no exact coordinates appear in release log output.

**Acceptance**

- Map appearance and persisted metrics cannot disagree because of separate filters.
- All pause transitions are deterministic under a fake clock.

### IP-1.3 — Repair nullable state and tear down user scope

**Primary files**

- `rythmrun_frontend_flutter/lib/presentation/common/providers/session_provider.dart`
- `rythmrun_frontend_flutter/lib/presentation/common/session/user_scope_teardown.dart`
- `rythmrun_frontend_flutter/lib/presentation/common/providers/user_scope_teardown_provider.dart`
- `rythmrun_frontend_flutter/lib/core/services/user_scope_operation_gate.dart`
- `rythmrun_frontend_flutter/lib/core/services/authentication_attempt_gate.dart`
- `rythmrun_frontend_flutter/lib/core/services/auth_persistence_service.dart`
- `rythmrun_frontend_flutter/lib/domain/repositories/auth_repository.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/auth_repository_impl.dart`
- Workout/activity-image repository sync gates and user-keyed history/detail/image providers
- State models for login, registration, tracking history/details, profile, change password, user, and live tracking
- `rythmrun_frontend_flutter/lib/main.dart`
- `rythmrun_frontend_flutter/lib/presentation/features/profile/screens/profile_screen.dart`
- `rythmrun_frontend_flutter/lib/core/di/injection_container.dart`
- Focused tests under `test/core/services/`, `test/data/repositories/`, `test/presentation/common/`, `test/presentation/features/`, and `test/presentation/state/`

**Implementation**

1. Standardize nullable `copyWith` fields using an explicit sentinel: omitted means "keep", while an explicit `null` means "clear". Do not use `value ?? this.value` for fields that must be clearable.
2. Add transition tests to every affected state, especially:
   - session user/error;
   - login/registration errors;
   - history detail workout/error;
   - profile error/avatar values;
   - live current session/location/error.
3. Introduce one user-scope teardown coordinator invoked on authenticated-user change or transition to unauthenticated.
4. Teardown order:
   - if a workout is active, require Finish or Discard before voluntary logout/account switch;
   - before IP-3 checkpoints ship, a forced server-auth loss stops tracking and attempts a blocking local finalization under the workout's original owner ID before session/provider teardown. If that local write fails, keep account switching blocked and show Retry/Discard; do not claim crash recovery, because it does not exist yet;
   - cancel and await a start already crossing the native GPS boundary; serialize duplicate Finish calls; and keep exit blocked until subscription/source cleanup succeeds;
   - when network is merely unavailable, keep the same verified user in eligible offline mode rather than treating it as a forced logout;
   - stop GPS subscription and timers;
   - clear live in-memory state;
   - stop new sync work and let no completion callback write under a newly active user;
   - invalidate history, detail, profile, activity-image, sync/repository caches, settings tied to a user, and home tab state;
   - clear session secrets/user state last for voluntary logout, while still guaranteeing local cleanup if the server call fails;
   - write a durable cleanup-pending marker before local credential removal, remove it only after all auth values are confirmed absent, and finish that cleanup before restoring any user after restart;
   - if local credential clearing itself fails, keep auth work suspended and the account exit blocked behind non-dismissible Retry cleanup. Do not publish a completed logout or permit B to activate.
5. Key any retained provider cache by user ID or recreate it after user changes. A family keyed only by workout ID is insufficient if local IDs can be stale in UI state.
6. Preserve completed offline rows on normal logout as stated in Decision D-004, but make them inaccessible until that same account authenticates again. Account deletion in IP-2 purges them.
7. Represent session validation as `valid`, `invalid`, or `unavailable`: an explicitly invoked invalid result enters forced teardown, while network unavailability preserves only the same locally verified user. Natural end-to-end `401/403` propagation, session revocation, secure token storage, and the final offline-window policy remain IP-2.
8. Put workout sync, image sync, and profile upload behind one owner-aware operation gate. Put login, registration, refresh, and validation persistence behind a second serialized auth-mutation gate plus session-generation admission token. Teardown rejects new work, awaits admitted A operations, invalidates state, persists/clears credentials, and only then permits B. Provider callbacks must also ignore writes after disposal or owner change.

**Automated tests**

- `copyWith(user: null)` actually clears the session user.
- A successful retry clears a previous details/login error.
- Logout during idle state invalidates all listed providers.
- Voluntary logout with an active workout cannot silently proceed without a user choice.
- Forced auth loss either durably finalizes locally before teardown or leaves account switching blocked on an explicit local-save error; it never silently continues or relabels the workout.
- A local credential-clear failure remains a blocked account exit and cannot activate another user until cleanup retry succeeds.
- Account A logout → account B login yields empty B-scoped providers even when A had loaded history/images.
- A remote logout failure still completes safe local teardown; a local credential-clear failure does not.
- Network-unavailable and explicitly invalid validation results take different non-destructive/forced-teardown paths.
- In-flight sync/profile leases drain under A, and disposed or stale callbacks cannot publish under B.
- A pending GPS start and duplicate Finish calls are awaited before teardown; failed native cleanup remains a recoverable blocked exit.
- Delayed validation/refresh and concurrent login/registration cannot rewrite credentials or publish a stale user after exit begins.
- A persisted cleanup marker prevents restart from restoring A after a failed credential deletion.

**Manual verification**

- Run [MC-1.6](./MANUAL-CHECKS.md#mc-16--user-scope-exit-and-account-switch-isolation) on a supported release build with synthetic staging accounts. This repository package does not claim device, restart, server-revocation, DAO-ownership, or process-death proof.

**Acceptance**

- No Riverpod state from account A renders or mutates under account B.

### IP-1.4 — Enforce local ownership, foreign keys, and indexes

**Primary files**

- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart`
- `rythmrun_frontend_flutter/lib/data/datasources/workout_local_datasource.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/workout_repository_impl.dart`
- Activity-image local data source/repository methods
- `rythmrun_frontend_flutter/lib/domain/repositories/workout_repository.dart`
- Existing host-FFI harness plus new schema, migration, ownership, and repository race tests

**Implementation**

1. Increment the SQLite schema version; never rely only on `_ensure...` calls that obscure migration history.
2. Add `onConfigure` to every opened connection and execute `PRAGMA foreign_keys = ON` before create/upgrade/open work.
3. Before relying on cascades, migrate existing data transactionally:
   - find child tracking/status/image rows without a parent workout;
   - log table names and aggregate repair counts only, delete irreparable child rows, and repair delete-queue ownership from an existing parent;
   - run `PRAGMA foreign_key_check` and fail migration/verification when violations remain.
4. Add indexes:
   - `workouts(user_id, start_time DESC)`;
   - `tracking_points(workout_id, timestamp)`;
   - `status_changes(workout_id, timestamp)`;
   - retain existing image/delete-queue indexes;
   - unique `workouts(user_id, client_sync_id)` after resolving duplicates safely. Preserve one deterministic canonical identity, quarantine additional ambiguous local rows from sync, and roll back if one client identity already maps to multiple remote activities; never mint a second uploadable identity.
5. Require `userId` at the local data-source boundary for get, delete, sync-state update, image attach/read/delete, and any operation using a local workout ID.
6. Use predicates such as `WHERE id = ? AND user_id = ?`. For child tables without `user_id`, join/verify the parent in the same transaction; do not perform a race-prone check and later unscoped mutation.
7. Re-read the active user before asynchronous sync completion writes. If the account changed, stop and leave the original user's row retryable. Hold one outer owner lease across coordinated workout/image synchronization and owner leases across foreground image preparation/mutation.
8. Keep domain repository convenience methods free to obtain the current user, but require an explicit owner on every production data-source operation. Keep the raw database accessor test-only and the production `LocalDbService` provider private.
9. Reuse the existing pinned `sqflite_common_ffi` test dependency and shared host database harness. Extend it with faithful v1–v5 and shipped-v3-hybrid schemas for schema/DAO/migration tests. Hosted Flutter CI remains IP-1.6; keep mobile-driver, installed-database, backup, and process-lifecycle checks in MC-1.7/device tests where FFI cannot represent behavior.
10. Database cascades do not safely remove app-private image files after their path rows disappear. Do not perform arbitrary file I/O inside the migration or claim physical cleanup here; durable file cleanup/outbox work remains IP-4.6.

**Automated tests**

- Account B cannot read/delete/update account A's known local workout ID.
- The same protection covers activity images and queued deletion state.
- Deleting an owned workout cascades points, status changes, and images.
- `PRAGMA foreign_keys` reports enabled on a test connection.
- Migration from database versions 1–5 plus the shipped v3 delete-queue hybrid preserves valid data, removes/handles seeded orphans, repairs queue ownership, reopens idempotently, and passes `foreign_key_check`.
- Duplicate legacy client sync IDs leave at most one uploadable canonical row; additional rows are non-syncing, and conflicting remote mappings roll back the migration.
- New indexes exist after both fresh create and upgrade.

**Manual verification**

- Run [MC-1.7](./MANUAL-CHECKS.md#mc-17--android-sqlite-v5v6-ownership-migration) on a supported Android release build. Repository FFI tests do not prove installed-device driver behavior, backup/forward-fix recovery, or app-private file cleanup.

**Acceptance**

- Local row IDs are never treated as authorization.

### IP-1.5 — Preserve backend history and bound the interim workout payload

**Primary files**

- `RythmRun_backend_nodejs/src/app.ts`
- `RythmRun_backend_nodejs/src/routes/activity.routes.ts`
- `RythmRun_backend_nodejs/src/models/dto/activity.dto.ts`
- `RythmRun_backend_nodejs/src/models/activity-domain-validation.ts`
- `RythmRun_backend_nodejs/src/middleware/activity-validation.middleware.ts`
- `RythmRun_backend_nodejs/src/middleware/validation.middleware.ts`
- `RythmRun_backend_nodejs/src/controllers/activity.controller.ts`
- `RythmRun_backend_nodejs/src/services/activity.service.ts`
- `rythmrun_frontend_flutter/lib/core/network/http_client.dart`
- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart`
- `rythmrun_frontend_flutter/lib/data/datasources/workout_local_datasource.dart`
- `rythmrun_frontend_flutter/lib/data/models/activity_sync_model.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/workout_repository_impl.dart`
- Activity boundary/domain/controller/service and Flutter HTTP/model/repository tests

**Implementation**

1. Keep a small default parser for ordinary routes. Apply the measured temporary activity-body limit only to authenticated activity create/update routes, after a process-local concurrency admission guard and an early `Content-Length` rejection where present; the parser limit remains authoritative for chunked/missing-length bodies. Measurement showed that 2 MiB contradicts the 12,000-location/1,000-status caps, so the reviewed interim application limit is exactly 3 MiB while ordinary routes remain at 100 KiB. Do not raise the global Express limit.
2. Bound and validate the domain independently of the body limit:
   - maximum 12,000 locations, with a serialized maximum fixture below the configured body limit;
   - maximum 1,000 status changes;
   - nested validation with `ValidateNested({ each: true })` and `Type`;
   - finite latitude `[-90,90]`, longitude `[-180,180]`, sane accuracy/speed/heading/elevation ranges, valid timestamps, and chronological bounds within the activity window;
   - workout type/status allowlists and bounded text/client ID lengths;
   - internally consistent end time, active/paused duration, average speed, route distance, and route-observed maximum speed.
3. Adjust the numeric cap after measuring realistic serialized fixtures; body limit and array cap must not contradict each other.
4. Define PATCH collection semantics by property presence:
   - omitted `locations`/`statusChanges` preserves existing rows;
   - explicit empty array clears when the API intentionally permits it;
   - non-empty array replaces inside the transaction.
5. Never delete either collection before validation of the complete replacement succeeds. Run the merge/read/validate/nested-write sequence at serializable isolation and retry serialization conflicts so concurrent application processes cannot commit complementary partial patches against the same stale snapshot.
6. Return actionable validation codes so the mobile sync layer can distinguish permanent malformed/oversized data from retryable auth, admission, server, and network failure. Persist only the stable permanent reason in the existing SQLite v6 `sync_blocked_reason` column; do not persist raw responses. UI visibility arrives in IP-4.

**Repository contract selected on 2026-07-11**

- `POST /api/activities` and `PATCH /api/activities/:activityId` run authentication, a process-local admission guard, early declared-length rejection, then the 3 MiB parser. The parser-selection matcher follows Express's case-insensitive route contract. The interim guard permits one active mutation per user and four per process, rejects without queueing, and does not replace IP-2.6's proxy-aware/distributed controls.
- The measured 750-point fixture is above 100 KiB. The full 12,000-location/1,000-status canonical fixture is above 2 MiB and below 3 MiB; the test asserts both facts so the body and collection caps cannot drift independently.
- Structural failures use non-retryable `ACTIVITY_REQUEST_INVALID`, `ACTIVITY_PAYLOAD_INVALID_JSON`, or `ACTIVITY_PAYLOAD_TOO_LARGE`; semantic failures use non-retryable `ACTIVITY_DOMAIN_INVALID`; temporary admission pressure uses retryable `ACTIVITY_REQUEST_BUSY` plus `Retry-After`. An exact root allowlist and scalar/collection preflight run before transformation; generic traversal is iterative and bounded by depth/object/key budgets. DTO/domain responses contain at most 25 issues, bound path/message lengths, and include `issuesTruncated` rather than amplifying a bounded request into an unbounded error response.
- Nullable scalar fields retain the current Flutter compatibility contract. Non-nullable PATCH fields and both collections reject `null`; omission preserves a collection, `[]` clears it, and a non-empty array replaces it in one owner-scoped nested Prisma update. The owner read, merged validation, and nested write use serializable isolation with up to three attempts on Prisma `P2034` conflicts.
- Non-empty canonical status history supplies pause-segmentation provenance for route-distance and implied-speed reconstruction. Once history is intentionally absent or cleared, stored aggregates remain authoritative: individual timestamp/accuracy/coordinate/reported-speed checks still run, but later patches do not invent route bridges from history that no longer exists.
- The current Flutter client serializes activity, location, and status timestamps as UTC. The backend temporarily accepts offset-less timestamps from previously supported clients; staging must prove that compatibility window before it is narrowed.
- Version 1 retains broad legacy speed/GPS interpretation. Version 2 enforces canonical metres/second, the current GPS policy, workout/status allowlists, strict calendar timestamps, bounded/ordered timelines, and route/summary consistency. This relies on the documented invariant that version 2 was not deployed before IP-1.2; if release history disproves that invariant, introduce distinct tracking-policy provenance before rollout.
- Flutter treats only activity-create `400`, `413`, and `422` as permanent, records the stable server code (or status-derived fallback) in the existing v6 block marker, and continues later rows. `401`, `403`, `429`, `5xx`, and network failures remain eligible after auth/backoff/recovery. An account switch cannot write a block reason into the newly active user's scope or launch another queued request with the prior user's cached headers.
- Deployed edge/proxy alignment, memory/latency observation, real PostgreSQL rollback proof, previous-client timestamp compatibility, and sanitized telemetry remain open under [MC-1.8](./MANUAL-CHECKS.md#mc-18--bounded-activity-ingest-and-patch-history-in-staging).

**Automated tests**

Final-tree DTO/domain/controller/service, Flutter, and socket-boundary coverage below has passed. The socket cases cover the HTTP parser/admission bullets; MC-1.8 still owns deployed proxy, resource, real PostgreSQL, compatibility, and telemetry proof.

- Audited 750-point fixture above the 100 KiB ordinary-route limit succeeds.
- A representative multi-hour fixture below both caps succeeds.
- Above-limit body returns `413`; too many points returns deterministic `400/422` without reaching the create/update handler or service.
- Oversized unauthenticated/high-concurrency requests are rejected before expensive JSON/domain work, and unrelated routes retain the small default limit.
- Invalid nested coordinate/type/timestamp is rejected before transaction writes.
- Wide unknown-root, deeply nested scalar, and attacker-sized key probes return small bounded structural errors; the declared 12,000/1,000 maxima remain inside the traversal budget.
- PATCH of name only preserves locations and status history.
- PATCH with explicit empty collection follows the documented clear rule.
- A later route-affecting PATCH remains valid after status history was intentionally cleared instead of reconstructing a false pause bridge.
- A simulated serializable conflict retries the complete owner read/validation/write sequence.
- A stateful transaction fake leaves old collections intact when the nested update fails; real PostgreSQL rollback remains MC-1.8.

**Acceptance**

- Ordinary MVP workouts no longer fail at the explicit ordinary 100 KiB cap, while the activity mutation endpoint remains bounded.
- Repository tests do not prove the deployed reverse proxy accepts 3 MiB or that the chosen concurrency/memory envelope is operationally safe; MC-1.8 must pass before rollout.

### IP-1.6 — Add minimum CI and phase gates

**Primary files**

- Existing `.github/workflows/backend-security.yml`
- New `.github/workflows/ci.yml`
- Root `.gitignore` with exact workflow allowlisting
- `RythmRun_backend_nodejs/package.json` and `package-lock.json`
- `RythmRun_backend_nodejs/prisma.config.ts` and `prisma/schema.prisma`
- `RythmRun_backend_nodejs/tsconfig.json`, test TypeScript/Jest configuration, and explicit `.js` import specifiers
- `RythmRun_backend_nodejs/src/config/database.ts` and `src/config/container.ts`
- `RythmRun_backend_nodejs/src/server.ts`, `src/main.ts`, and `scripts/smoke-built-runtime.mjs`
- `rythmrun_frontend_flutter/.flutter-version`
- `rythmrun_frontend_flutter/tool/ci/analyzer_baseline.dart`
- `rythmrun_frontend_flutter/tool/ci/analyzer_baseline.json`
- `rythmrun_frontend_flutter/test/tool/analyzer_baseline_test.dart`

**Implementation**

1. Preserve the existing `Backend security` workflow/job name so MC-0.7 through MC-0.9 and future rulesets keep one stable identity. Pin Ubuntu 24.04, Node 22.23.1, and action commits; retain read-only permissions, non-persisted checkout credentials, concurrency cancellation, and the npm download cache keyed by the lockfile.
2. Complete the clean-install Prisma migration instead of retaining a rollback. Pin `prisma`, `@prisma/client`, and `@prisma/adapter-pg` to 7.8.0; move the CLI datasource into `prisma.config.ts`; use the `prisma-client` generator to emit TypeScript under `src/generated/prisma`; and instantiate PostgreSQL through explicit pool limits/timeouts rather than a parameterless client.
3. Centralize database ownership. Create one adapter-backed `PrismaClient`, register it in the dependency container, inject it into every service/controller path, remove the unused per-request refresh-token client, and make disconnect idempotent. Load/validate configuration before importing infrastructure consumers, separate `main` from the server module, and close the listener, retry timer, and Prisma runtime through an explicit shutdown path.
4. Migrate production execution to native NodeNext ESM: set the package module type, emit ES2023/NodeNext, use explicit `.js` relative specifiers, keep generated Prisma output inside the compiled `src` tree, and run Jest through its native ESM path. A production build—not a source-only transform—must prove the emitted graph resolves under raw Node.js.
5. Run the backend job with `npm ci --no-audit`, `npx --no-install prisma validate`, Prisma generation, the production TypeScript typecheck, the complete native ESM Jest suite, `npm run build`, and `npm run smoke:runtime`. The built smoke imports the emitted server/client/container/routes, serves liveness, proves an unauthenticated protected request stops before persistence, and exercises cleanup against an intentionally unreachable database URL. It does **not** connect to PostgreSQL, run migrations, validate TLS, measure the pool, prove a database transaction, exercise R2, or reproduce deployed SIGTERM behavior; MC-1.12 and MC-1.13 own those gates.
6. Add a separate `Flutter CI` job on Ubuntu 24.04 with immutable checkout and Flutter-action commits, exact Flutter 3.44.1/Dart 3.12.1, read-only permissions, no secrets, no workspace cache, and lock-enforced dependency restoration.
7. Define formatting scope from `git merge-base` against the event's base/before commit—or the required base SHA supplied to a manual dispatch—with full history. Consume NUL-delimited Git names into a quoted Bash array and format only existing added/copied/modified/renamed Dart files. This protects new work while the 14-file whole-tree formatting debt remains; a zero-parent push checks all tracked Dart files.
8. Run `flutter analyze --no-pub --no-fatal-infos` so warning/error diagnostics remain fatal. Separately parse `dart analyze --format machine` and compare informational diagnostics with a sorted JSON multiset keyed by analyzer rule, repository-relative path, and SHA-256 of the whitespace-normalized message. Ignore line/column, preserve duplicate counts, reject malformed/out-of-package records and baseline schema/order/duplicate errors, fail additions or count increases, and allow removals.
9. Keep the source workflow independent of production/database/R2 credentials. The current backend npm cache contains only reproducible download data; Flutter starts without a cache. Require reviewed ownership of workflow/comparator/baseline changes when configuring branch rules so a pull request cannot approve its own weaker gate. Because build/migration tools are development dependencies, MC-1.13 must prove install, generate/build, migrate, prune, and start ordering on the real host before deployment.

**Analyzer-baseline maintenance**

1. Use the exact `.flutter-version` toolchain and an unchanged lockfile. Run `dart analyze --format machine` from `rythmrun_frontend_flutter` and keep the output outside the repository.
2. Prefer fixing a finding. To preview a necessary baseline rewrite, run `dart run tool/ci/analyzer_baseline.dart render --input <machine-output> --repository-root .. --package-root .` and redirect stdout to a temporary file.
3. Review the normalized JSON diff. A path/message-key addition or count increase is new debt and needs an explicit rationale; line-number movement must not change the file. Never add warnings/errors to the baseline—the renderer and checker reject them.
4. Run the comparator tests, the real baseline check, formatting, full Flutter tests, and both analyzers. Baseline/comparator/workflow changes also require the protected independent review in MC-1.11.

**Acceptance**

- Repository implementation: clean generation targets Prisma 7.8's adapter-backed client and native ESM production output; one DI-managed database lifetime replaces the former independent constructors; and the emitted build has a dedicated no-database smoke. On Node 22.22.3, clean install, Prisma validation/generation, production typecheck/build, all 15 native ESM suites and 244 tests, and the built smoke pass. The Flutter package retains its 189-test, three-file format, and exact 20-information/zero-warning/zero-error evidence.
- Hosted evidence: MC-0.7/MC-1.9 record successful backend/Flutter runs for the reviewed SHA. MC-0.8/MC-1.10 use temporary non-merge revisions to prove backend test/type, Flutter test/format, analyzer warning, and new-information failures independently. MC-0.9/MC-1.11 then prove both stable checks and CI-control review are required.
- A workflow file, local test, built smoke, or source inspection is not hosted/deployed evidence. MC-1.12 must prove the full migration chain, real adapter queries/transactions, TLS, custom-schema behavior where applicable, and connection-pool limits on PostgreSQL. MC-1.13 must prove artifact/install/migrate/start ordering and bounded deployed SIGTERM cleanup. These gates also do not prove deployed proxy limits, Android driver behavior, dependency-advisory status, or production safety.

### IP-1.7 — Prevent real ads in development and gate ads on durable completion

**Primary files**

- `rythmrun_frontend_flutter/lib/features/ads/providers/admob_ads_provider.dart`
- Ads config/provider factory and app configuration
- `rythmrun_frontend_flutter/android/app/src/main/AndroidManifest.xml`
- Live tracking completion result and Track screen ad trigger

**Implementation**

1. Debug, test, and staging builds use the no-op provider or official Google test IDs only. Remove production-ID fallbacks from Dart and inject the Android application ID per flavor/environment.
2. A release build fails configuration when production ads are intentionally enabled without explicit production IDs; development never falls through to them.
3. Make workout Finish return an explicit durable-save/finalization result. Show any post-activity ad only after the local workout transaction succeeds; failure/retry/recovery UI always comes first.
4. Full consent, placement, and monetization policy remains IP-5.5.

**Tests**

- Debug/staging configuration cannot resolve a production app/unit ID.
- Local save failure shows no ad and retains actionable workout state.
- Successful durable completion may invoke the configured test/no-op placement once.

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
- [ ] Debug/staging cannot use production AdMob IDs, and ads never appear before durable local completion.

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
