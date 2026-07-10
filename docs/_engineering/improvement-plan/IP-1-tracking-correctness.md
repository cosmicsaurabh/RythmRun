---
published: false
---

# IP-1: Tracking correctness and per-user local integrity

| Field | Value |
| --- | --- |
| Status | Planned |
| Priority | P1 |
| Target | 3–5 focused work packages after IP-0 |
| Owner | Unassigned |
| Last updated | 2026-07-10 |
| Depends on | IP-0 patched deployment; incident containment remains active until IP-0 exits |
| Exit condition | Metrics, account-switch, cascade, PATCH, long-payload, and CI gates pass |

## Outcome

After this phase, a user can trust the app's distance, active duration, speed, pace, and calorie inputs; paused or rejected GPS movement cannot corrupt those metrics; completed local data is accessible only by its owner; SQLite cascades are enforced; unrelated backend edits preserve route history; and minimum CI protects the corrected behavior.

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
- No tracked CI workflow protects existing tests or the fixes in this phase.

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

- Active-workout persistence and background service implementation; IP-3 owns those.
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
- Pace for 5 km in 25 minutes formats as `5:00` min/km.
- A version-1 fixture migrates once; a version-2 fixture remains unchanged.
- A corrupt/zero-duration legacy row is not divided or assigned infinity/NaN.
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
- State models for login, registration, tracking details, profile, change password, and live tracking
- `rythmrun_frontend_flutter/lib/main.dart`
- `rythmrun_frontend_flutter/lib/presentation/features/profile/screens/profile_screen.dart`
- `rythmrun_frontend_flutter/lib/core/di/injection_container.dart`
- New user-scope teardown coordinator and tests

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
   - when network is merely unavailable, keep the same verified user in eligible offline mode rather than treating it as a forced logout;
   - stop GPS subscription and timers;
   - clear live in-memory state;
   - stop new sync work and let no completion callback write under a newly active user;
   - invalidate history, detail, profile, activity-image, sync/repository caches, settings tied to a user, and home tab state;
   - clear session secrets/user state last for voluntary logout, while still guaranteeing local cleanup if the server call fails.
5. Key any retained provider cache by user ID or recreate it after user changes. A family keyed only by workout ID is insufficient if local IDs can be stale in UI state.
6. Preserve completed offline rows on normal logout as stated in Decision D-004, but make them inaccessible until that same account authenticates again. Account deletion in IP-2 purges them.

**Automated tests**

- `copyWith(user: null)` actually clears the session user.
- A successful retry clears a previous details/login error.
- Logout during idle state invalidates all listed providers.
- Voluntary logout with an active workout cannot silently proceed without a user choice.
- Forced auth loss either durably finalizes locally before teardown or leaves account switching blocked on an explicit local-save error; it never silently continues or relabels the workout.
- Account A logout → account B login yields empty B-scoped providers even when A had loaded history/images.

**Acceptance**

- No Riverpod state from account A renders or mutates under account B.

### IP-1.4 — Enforce local ownership, foreign keys, and indexes

**Primary files**

- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart`
- `rythmrun_frontend_flutter/lib/data/datasources/workout_local_datasource.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/workout_repository_impl.dart`
- Activity-image local data source/repository methods
- `rythmrun_frontend_flutter/lib/domain/repositories/workout_repository.dart`
- New sqflite migration/integration test helpers

**Implementation**

1. Increment the SQLite schema version; never rely only on `_ensure...` calls that obscure migration history.
2. Add `onConfigure` to every opened connection and execute `PRAGMA foreign_keys = ON` before create/upgrade/open work.
3. Before relying on cascades, migrate existing data transactionally:
   - find child tracking/status/image rows without a parent workout;
   - quarantine counts in safe migration logs, delete or repair according to deterministic rules;
   - run `PRAGMA foreign_key_check` and fail migration/verification when violations remain.
4. Add indexes:
   - `workouts(user_id, start_time DESC)`;
   - `tracking_points(workout_id, timestamp)`;
   - `status_changes(workout_id, timestamp)`;
   - retain existing image/delete-queue indexes;
   - unique `workouts(user_id, client_sync_id)` after resolving duplicates safely.
5. Require `userId` at the local data-source boundary for get, delete, sync-state update, image attach/read/delete, and any operation using a local workout ID.
6. Use predicates such as `WHERE id = ? AND user_id = ?`. For child tables without `user_id`, join/verify the parent in the same transaction; do not perform a race-prone check and later unscoped mutation.
7. Re-read the active user before asynchronous sync completion writes. If the account changed, stop and leave the original user's row retryable.
8. Keep domain repository convenience methods free to obtain the current user, but make it impossible to call the DAO without an explicit owner.
9. Add `sqflite_common_ffi` as a test-only dependency and initialize a shared host database factory under `test/support/` for schema/DAO/migration tests in normal CI. Keep platform encryption/backup and process-lifecycle checks as `integration_test`/device tests where FFI cannot represent behavior.

**Automated tests**

- Account B cannot read/delete/update account A's known local workout ID.
- The same protection covers activity images and queued deletion state.
- Deleting an owned workout cascades points, status changes, and images.
- `PRAGMA foreign_keys` reports enabled on a test connection.
- Migration from database versions 1–4 preserves valid data, removes/handles seeded orphans, and passes `foreign_key_check`.
- Duplicate legacy client sync IDs are resolved without duplicating remote activities.
- New indexes exist after both fresh create and upgrade.

**Acceptance**

- Local row IDs are never treated as authorization.

### IP-1.5 — Preserve backend history and bound the interim workout payload

**Primary files**

- `RythmRun_backend_nodejs/src/app.ts`
- `RythmRun_backend_nodejs/src/models/dto/activity.dto.ts`
- `RythmRun_backend_nodejs/src/controllers/activity.controller.ts`
- `RythmRun_backend_nodejs/src/services/activity.service.ts`
- `RythmRun_backend_nodejs/src/__tests__/activity.service.test.ts`
- New controller/integration tests and a 750-point fixture generator

**Implementation**

1. Keep a small default parser for ordinary routes. Apply the measured temporary activity-body limit only to authenticated activity create/update routes, after a minimal rate/concurrency guard and an early `Content-Length` rejection where present; the parser limit remains authoritative for chunked/missing-length bodies. Start measurement at 2 MiB, then commit the exact limit and fixtures before merge. Do not raise the global Express limit.
2. Bound and validate the domain independently of the body limit:
   - maximum 12,000 locations, with a serialized maximum fixture below the configured body limit;
   - maximum 1,000 status changes;
   - nested validation with `ValidateNested({ each: true })` and `Type`;
   - finite latitude `[-90,90]`, longitude `[-180,180]`, sane accuracy/speed/heading/elevation ranges, valid timestamps, and chronological bounds within the activity window;
   - workout type/status allowlists and bounded text/client ID lengths;
   - internally consistent end time, active duration, paused duration, distance, and point count.
3. Adjust the numeric cap after measuring realistic serialized fixtures; body limit and array cap must not contradict each other.
4. Define PATCH collection semantics by property presence:
   - omitted `locations`/`statusChanges` preserves existing rows;
   - explicit empty array clears when the API intentionally permits it;
   - non-empty array replaces inside the transaction.
5. Never delete either collection before validation of the complete replacement succeeds.
6. Return actionable validation codes so the mobile sync layer can distinguish permanent malformed/oversized data from retryable network failure. UI visibility arrives in IP-4.

**Automated tests**

- Audited 750-point/~103 KB fixture succeeds.
- A representative multi-hour fixture below both caps succeeds.
- Above-limit body returns `413`; too many points returns deterministic `400/422` without persistence.
- Oversized unauthenticated/high-concurrency requests are rejected before expensive JSON/domain work, and unrelated routes retain the small default limit.
- Invalid nested coordinate/type/timestamp is rejected before transaction writes.
- PATCH of name only preserves locations and status history.
- PATCH with explicit empty collection follows the documented clear rule.
- Transaction failure leaves old collections intact.

**Acceptance**

- Ordinary MVP workouts no longer fail at Express's default 100 KB limit, while the endpoint remains bounded.

### IP-1.6 — Add minimum CI and phase gates

**Primary files**

- New `.github/workflows/ci.yml`
- Root `.gitignore` (carefully preserve its existing user changes and explicitly unignore `.github/workflows/`)
- Backend and Flutter configuration only as required for deterministic CI

**Implementation**

1. Backend job on a pinned supported Node version:
   - `npm ci`;
   - `npx prisma generate`;
   - `npx tsc --noEmit`;
   - `npm test -- --runInBand`.
2. Flutter job on a pinned Flutter/Dart version matching `pubspec.yaml`:
   - dependency restore;
   - formatting check for touched/new files, expanding to the repository after existing formatting debt is fixed;
   - `flutter test`;
   - `flutter analyze` with a machine-readable baseline.
3. Fix the six existing warnings in this phase so errors/warnings are fatal. Commit a small comparison script and normalized baseline file for the remaining informational findings (rule + repository-relative path + message fingerprint); fail on additions while allowing removals. Define changed files from the merge-base diff only for reporting—do not rely on an undefined "touched file" rule.
4. Cache only reproducible dependency data, never generated secret/config files.
5. Require both jobs before merge once the workflow is stable.

**Acceptance**

- A deliberately failing backend test, Flutter test, type error, and new analyzer warning each cause the expected CI failure in a temporary branch/PR.
- A synthetic new informational finding fails the baseline comparison, while removing an old finding passes.

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
- If 2 MiB handling causes resource pressure, keep domain caps and reduce the limit based on measured fixtures; do not return to the unannounced 100 KB default.
- CI can temporarily be non-required while infrastructure is repaired, but must continue reporting and cannot be marked complete until failure probes work.

## Verification matrix

| Scenario | Expected result | Evidence |
| --- | --- | --- |
| 10 km in 1 hour | Store ~2.7778 m/s; display 10.0 km/h | Unit/provider test |
| Pause, move, resume | Paused and bridge movement add 0 m | Fake-stream test + device run |
| Finish while paused | Open pause excluded exactly once | Fake-clock test |
| GPS jump then valid point | Jump rejected; valid point uses last accepted anchor | Policy/provider test |
| A logout → B login | No A state/data visible or mutable | Provider + repository integration test |
| Delete owned workout | All child rows cascade; foreign key check clean | SQLite migration test |
| PATCH name only | Route/status rows unchanged | Backend service/integration test |
| 750-point payload | Activity created successfully | HTTP integration test |
| Oversize/malformed payload | Stable non-retryable 4xx; no partial rows | HTTP + DB test |
| CI failure probe | Required job fails for intentional regression | CI run link |

## Exit gate

- [ ] Canonical units are documented in code and covered by exact-value tests.
- [ ] Historical speed migration was sampled, backed up, versioned, and exercised safely.
- [ ] Calories receive km/h exactly once and are labeled as an estimate.
- [ ] Overall/per-type duration statistics subtract paused time and match detail semantics.
- [ ] One GPS policy governs map, metrics, and persistence.
- [ ] Paused movement and resume bridging add no active distance.
- [ ] Finish-while-paused active duration is correct.
- [ ] Exact coordinates are absent from release logging.
- [ ] Nullable state can be explicitly cleared across all audited state models.
- [ ] Logout/account switch stops user-scoped work and invalidates state.
- [ ] Every local get/mutation by row ID is owner-scoped.
- [ ] SQLite foreign keys are on, orphans are handled, cascades pass, and required indexes exist.
- [ ] SQLite host migration/DAO tests run under an explicitly initialized FFI database in CI; platform-only checks are assigned to device integration tests.
- [ ] Omitted PATCH collections are preserved.
- [ ] Representative long workouts sync under explicit limits; invalid/oversized payloads fail safely.
- [ ] The larger activity parser is authenticated, route-specific, rate/concurrency guarded, and does not raise unrelated route limits.
- [ ] Backend and Flutter CI jobs run and fail on intentional regressions.
- [ ] Debug/staging cannot use production AdMob IDs, and ads never appear before durable local completion.

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| — | — | No implementation evidence yet | Not started | Planning document only |
