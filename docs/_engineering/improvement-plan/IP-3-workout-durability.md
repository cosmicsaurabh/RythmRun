---
published: false
---

# IP-3: Active-workout durability and background reliability

| Field | Value |
| --- | --- |
| Status | Planned |
| Priority | P1 |
| Target | 1–2 weeks, including physical-device evidence |
| Owner | Unassigned |
| Last updated | 2026-07-17 |
| Depends on | IP-1 tracking state/units; IP-2.1–IP-2.3 stable session identity/offline rules for recovery integration |
| Platform gate | Android first; iOS remains out of release scope until IP-5 |
| Exit condition | Crash recovery, screen-off, failure-injection, and long-session gates pass |

## Outcome

After this phase, an active workout is a durable state machine rather than an in-memory UI session. A process kill loses no more than the documented checkpoint window, recovery cannot duplicate or cross accounts, pause semantics remain correct through restarts, and Android tracking continues under screen-off/background conditions with a visible foreground-service notification.

## Audit evidence

- `live_tracking_provider.dart` keeps the session, start time, current pause, total pause, and points in memory.
- The first SQLite write occurs only after the user taps Finish.
- The provider subscribes directly to the global location singleton, while the map maintains another subscription.
- The Android manifest contains foreground location permissions but no complete foreground-location service declaration/permission set.
- `LiveTrackingService` uses generic `LocationSettings`, not a configured foreground notification lifecycle.
- Every accepted point copies the full point list, the map rebuilds route segments, and the whole Track screen can update every second; long sessions trend toward quadratic work.
- App lifecycle handling currently triggers cloud sync but does not checkpoint an active session.

## Scope

- Write-ahead active-workout checkpoint schema and DAO.
- Pure workout engine/state transitions separated from UI.
- Bounded point flushing and atomic finalization.
- Current-user recovery choices after process death/restart.
- Android foreground tracking and notification lifecycle.
- One GPS subscription and incremental/bounded active-route presentation.
- Failure-injection, process-kill, screen-off, battery, and multi-hour testing.

## Non-goals

- iOS background readiness; IP-5 decides whether to implement or explicitly defer it.
- Cloud restore; IP-4 owns remote pull/merge.
- Full offline map tiles.
- Exact zero-loss GPS under sudden hardware/power failure. The phase defines and proves a bounded loss objective.
- Medical-grade location/calorie claims.

## Durability objective

- Checkpoint accepted points at least every five points or five seconds, whichever occurs first.
- Persist start, pause, resume, finish, and discard transitions immediately.
- Maximum accepted crash loss: the smaller of five unflushed points or five seconds of accepted points.
- A finalization attempt results in exactly one of:
  - one valid active checkpoint, or
  - one completed local workout with its points/status events.
- It must never result in neither record or two completed records.

The exact interval may be tightened after battery/write measurement, but cannot be loosened without updating the user-facing recovery expectation and tests.

## Target state machine

```text
none -> starting -> active <-> paused -> finishing -> completed
                      |          |          |
                      +----------+----------+-> recoverable after interruption

recoverable -> active (resume)
recoverable -> completed (finish at last durable point)
recoverable -> discarded (explicit confirmation)
```

Invalid transitions fail without deleting the checkpoint. `completed` and `discarded` are terminal. Repeating finish/discard is idempotent.

## Checkpoint data model

Add dedicated local tables rather than exposing incomplete rows through completed-history queries.

### `active_workout_checkpoints`

- local checkpoint ID;
- `user_id` and `client_sync_id`; enforce exactly one active checkpoint per user plus a unique `(user_id, client_sync_id)` identity;
- workout type and state (`starting`, `active`, `paused`, `recoverable`, `finishing`);
- started timestamp, current pause start, accumulated paused milliseconds/seconds;
- last accepted point timestamp and last sequence;
- durable aggregate distance, max speed, elevation inputs/version as needed;
- metric/checkpoint schema version;
- created/updated/last-flushed timestamps.

### `active_tracking_points`

- checkpoint foreign key with cascade;
- monotonically increasing sequence unique within checkpoint;
- accepted latitude, longitude, altitude, accuracy, speed, heading, and source timestamp;
- only points accepted by the IP-1 policy; rejected raw samples are not persisted as route data.

### `active_status_events`

- checkpoint foreign key with cascade;
- monotonic sequence;
- active/paused/interrupted transition and timestamp.

`interrupted` is local recovery metadata, not part of the current backend status contract. Finalization converts it into the corresponding pause boundary/status history sent by the supported API.

All tables are user-reachable only through a parent checkpoint scoped by `user_id`. Add indexes for current-user recovery and sequence reads. Add a transaction guard and unique constraint/index that prevents two active checkpoints for one user even under concurrent Start taps. The migration must coexist with existing database versions and pass `foreign_key_check`.

## Ordered work packages

### IP-3.1 — Extract a durable workout engine and checkpoint DAO

**Primary files**

- `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/providers/live_tracking_provider.dart`
- `rythmrun_frontend_flutter/lib/domain/repositories/live_tracking_repository.dart`
- `rythmrun_frontend_flutter/lib/domain/repositories/workout_repository.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/live_tracking_repository_impl.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/workout_repository_impl.dart`
- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart`
- New domain workout engine/checkpoint entity/repository/DAO files
- New migration and integration tests

**Implementation**

1. Split responsibilities:
   - raw location source;
   - IP-1 point acceptance policy;
   - pure workout transition/metric engine using an injected clock;
   - checkpoint writer;
   - Riverpod UI adapter.
2. `start` first creates the durable `starting` checkpoint with user ID and `clientSyncId`, then starts location, then commits `active`. If location startup fails, preserve or clean the checkpoint through an explicit failed-start transaction.
3. Assign each accepted point a sequence number. Buffer no more than five accepted points and flush on the five-second timer, app lifecycle transition, pause, finish, or explicit stop.
4. Point batch insert and checkpoint aggregate/sequence update occur in one SQLite transaction. A retry uses the sequence uniqueness constraint and is idempotent.
5. Pause/resume flush pending points first and persist the state/status event immediately. Use the durable clock values as the source of truth after restart.
6. The UI provider observes engine snapshots and contains no independent session clock/pause arithmetic that can diverge.
7. Keep completed history queries explicitly filtered from active checkpoint tables.
8. Add a stable `sequence` to completed `tracking_points` and status events. Backfill legacy rows deterministically by `(timestamp, existing row id)`, enforce uniqueness within each workout, and preserve active sequences during finalization. IP-4 depends on this contract.
9. If extracting the 1,633-line DB service, do it narrowly into migration/checkpoint/workout DAO files without changing unrelated image state behavior.

**Automated tests**

- Start checkpoint exists before the first point.
- A batch retry after an injected error produces no duplicate sequences.
- Pause/resume is durable even with zero points.
- Flush timer and point-count threshold each trigger; neither exceeds the loss objective.
- User/account changes abort writes rather than relabeling a checkpoint.
- Two concurrent Start calls for one user yield one checkpoint and one explicit already-active result.
- Legacy completed points/events receive stable deterministic sequence values exactly once.
- Database upgrades from all supported versions preserve completed workouts and create valid empty checkpoint tables.

**Acceptance**

- Closing the UI process after a successful flush leaves enough data to recover the workout.

### IP-3.2 — Finalize exactly once and make every failure recoverable

**Implementation**

1. On Finish:
   - stop accepting new raw points or establish a deterministic final sequence boundary;
   - flush all accepted buffered points;
   - close an open pause interval at the chosen end timestamp;
   - set checkpoint state to `finishing`;
   - recompute/validate final metrics from durable points/status and the IP-1 unit contract;
   - in one SQLite transaction, insert the completed workout and child rows using the same `clientSyncId`, then delete the checkpoint (cascade deletes active children).
2. Enforce unique `(user_id, client_sync_id)` on completed workouts so retrying finalization cannot duplicate the session.
3. If a completed row already exists after a crash, treat finalization as complete and remove only the matching owned checkpoint after verifying row integrity.
4. Do not start cloud sync until the completed local transaction commits.
5. A failed finalize leaves `finishing/recoverable` data intact and presents Retry/Recover; it never resets the provider to an empty success state.
6. Discard deletes only the active checkpoint and children after explicit user confirmation. It cannot delete a completed workout with the same ID accidentally.

**Failure-injection tests**

- Crash/failure before buffer flush.
- Failure after point flush but before `finishing` update.
- Failure during completed-workout insert.
- Crash after the finalization transaction commits but before UI acknowledgement/sync starts; reopen recognizes the completed row and does not duplicate it.
- A deliberately seeded completed-row-plus-checkpoint corruption case reconciles only after verifying matching owner/client identity.
- Repeated Finish taps/recovery attempts.
- Sync starts only after one completed record exists.

**Acceptance**

- Every injected boundary yields either one recoverable checkpoint or one completed workout, never data loss/duplication.

### IP-3.3 — Add current-user recovery UX and policy

**Primary files**

- `rythmrun_frontend_flutter/lib/main.dart`
- Session initialization/provider flow
- Live tracking provider and Track screen
- New recovery notifier/dialog/screen and widget tests

**Recovery policy**

1. After session identity is established, query only that user's checkpoint.
2. Reconcile transient states first:
   - `starting` with no proven running service/points becomes recoverable-start and offers Resume or Discard; it cannot create a zero-data completed workout;
   - `finishing` with a matching completed `(userId, clientSyncId)` is complete and cleans only the stale checkpoint; without a completed row it remains recoverable-finalization and offers Retry Finish or Discard, not Resume into a second route.
3. If the last durable state was `active` but no foreground service is currently proving continuity, append a local interruption/pause boundary at the last durable accepted timestamp. Unknown downtime is excluded from active duration.
4. If the last state was `paused`, the pause remains open through recovery until Resume or Finish.
5. For active/paused recoverable states, present exactly three explicit actions:
   - **Resume**: reopen the durable state, start foreground tracking, append an active event, and use the first accepted point as a zero-distance anchor;
   - **Finish**: complete at the last durable point/event timestamp under the documented pause policy;
   - **Discard**: destructive confirmation, then delete the owned checkpoint.
6. Do not auto-resume location after reboot or login without a user action and visible foreground notification.
7. A checkpoint belonging to a different account is ignored and inaccessible, not offered for takeover.
8. If checkpoint validation fails, preserve it, show a safe recovery error/export-support identifier, and avoid deleting it automatically.

**Automated tests**

- Kill/reopen after start, active points, pause, resume, and finishing.
- Starting-without-points and finishing-with/without-completed-row follow the deterministic reconciliation rules.
- Active interruption excludes unknown downtime.
- Paused interruption extends pause correctly.
- Resume creates no paused-displacement distance.
- Finish/discard are idempotent.
- Account B cannot see or act on account A's checkpoint.
- Corrupt checkpoint produces a recoverable error and no deletion.

**Acceptance**

- The user always sees a truthful recovery choice before starting another workout.

### IP-3.4 — Implement Android foreground/screen-off tracking

**Design proposal (2026-08-17, awaiting maintainer approval, no code changed):**
[Android background tracking and notification controls](../tracking/android-background-tracking-design.md)
— one Dart isolate on a cached FlutterEngine, an app-local `location`-type foreground
service that owns only the notification/actions/wake lock, no `ACCESS_BACKGROUND_LOCATION`,
no new dependency. Its §8 splits IP-3.1–3.4 into PRs; its §11 lists the decisions needed
before PR-1.

**Primary files**

- `rythmrun_frontend_flutter/android/app/src/main/AndroidManifest.xml`
- The single authoritative Android Groovy build plus Gradle/AGP/Kotlin and plugin configuration
- `rythmrun_frontend_flutter/lib/core/services/live_tracking_service.dart`
- Native/Flutter service integration selected for the pinned SDK/plugin versions
- Permission and notification UX in Track flow

**Implementation**

1. Preserve the duplicate-build-file resolution already delivered in `a9f2535` (`app/build.gradle` is authoritative). Before foreground-service changes, move beyond Flutter's current warning thresholds—Gradle 8.11.1 to at least 8.14, AGP 8.9.1 to at least 8.11.1, and Kotlin 2.1.0 to at least 2.2.20—evaluate built-in Kotlin compatibility for the app plus `location` and `package_info_plus`, and prove clean debug/release configuration without regressing signing, Google Sign-In, or ads fail-closed rules.

   **Version half delivered 2026-08-11 (`f6b9d0a`), proof half not.** The
   declared versions now sit exactly at the stated minimums: Gradle 8.14, AGP
   8.11.1, Kotlin 2.2.20. Nothing else in this item is satisfied — no Android
   build was run against the new toolchain during the 2026-08-11 plan
   reconciliation, so plugin/Kotlin compatibility is unevaluated and clean
   debug/release configuration, signing, Google Sign-In, and the IP-1.7 ads
   fail-closed rules are unverified under it. **Before this package starts, run
   a debug and a release configuration/build and record the result**; a prior
   attempt in this program exhausted host disk, so budget for that. Treat the
   bump as a prerequisite that is declared, not proven.
2. Follow official Android and pinned location-plugin requirements for foreground location, foreground-service type, notification permission, and any background-location permission that the chosen behavior actually needs. Do not cargo-cult permissions from an older target SDK.
3. Start the foreground service only from a user-initiated Start/Resume while the app is eligible to do so.
4. Show a persistent notification containing non-sensitive state (workout type, elapsed time, pause/resume/stop actions if safely supported). Never show exact coordinates.
5. Notification actions route through the same durable engine transitions; they do not mutate a second state machine.
6. Keep checkpoint flushing active while screen is off. If the OS kills the service, retain the last checkpoint and surface recovery.
7. Stop the service on Finish, Discard, account loss, and fatal location permission revocation.
8. Explain denied permission and OEM battery restriction clearly; never imply tracking is active when foreground service startup failed.
9. Record device/OS/plugin versions in evidence. Emulator-only evidence is insufficient.

**Physical-device matrix**

At minimum:

- one current stock/near-stock Android device;
- one Samsung device with common background restrictions;
- one older supported Android API level;
- normal battery and battery-saver modes;
- screen locked for at least 30 minutes and one representative multi-hour session;
- network online, airplane mode, and reconnect.

**Acceptance**

- A visible service runs during tracking; route and checkpoints continue under screen off within the documented accuracy/battery bounds.

### IP-3.5 — Remove long-session quadratic UI behavior

**Primary files**

- Live tracking state/provider/Track screen
- `presentation/features/Map/screens/live_map_feed.dart` and map segment helpers
- Home screen eager tab construction
- `ActivityImageFileService` and image attach/replace processing
- New performance fixture/benchmark tests

**Implementation**

1. Keep full-fidelity accepted points in the checkpoint store, not as a list copied into every UI state emission.
2. Expose lightweight engine snapshots: current point, total distance, active duration, pace, and a route-display revision/chunk.
3. Maintain an incremental or bounded display polyline. Sampling/simplification affects rendering only; persisted route fidelity remains intact.
4. Make widgets use Riverpod selectors so the one-second elapsed tick does not rebuild the whole tracking/map tree.
5. Remove the map's direct location subscription and full segment reconstruction on each point.
6. Lazily build/activate home tabs so an offstage map does not request location before the user enters tracking.
7. Move existing large image decode/resize/JPEG work off the UI isolate, preserve the durable original/thumbnail/checksum ordering, and add cancellation/failure/frame-time tests.
8. Measure memory, frame time, DB write time, image processing frame impact, and battery for a synthetic multi-hour route; record device/build configuration.

**Acceptance targets**

- Point processing cost remains approximately constant/bounded as route length grows.
- A multi-hour fixture does not show unbounded frame degradation or memory growth.
- The displayed route remains visually useful while completed detail can load full fidelity.

## Migration and rollout order

1. Ship checkpoint schema/DAO behind a disabled feature flag and prove migration.
2. Enable write-ahead engine for internal/staging builds; keep legacy finish flow available only as a controlled rollback path.
3. Exercise failure-injection and recovery UI before foreground service rollout.
4. Add `integration_test` device targets plus guarded scripts under `tool/device_test/` for install, synthetic route/clock hooks, `adb shell am force-stop`, relaunch, screen off/on, and log/result collection. Normal `flutter test` continues to cover pure transactions; only the device harness claims real process death/background evidence.
5. Enable foreground service on the physical-device matrix.
6. Enable UI/image performance changes after route and durable-image equivalence tests.
7. Release gradually, tracking checkpoint creation, recovery offers, finalization failures, and service-start failures with privacy-safe metrics.

## Rollback plan

- Do not ship an older binary whose lower SQLite version cannot open the upgraded database. Mobile rollback is forward-compatible: build the prior behavior from the same/new schema version with compatible migrations, or roll forward with a fix. Prove open/read behavior before rollout.
- A foreground-service rollback stops new service starts but preserves checkpoints and recovery UI.
- If the new engine is disabled remotely/configurationally, block starting a workout rather than returning to a memory-only path unless the maintainer explicitly accepts data-loss risk for a development build.
- Schema downgrade is not required; forward-compatible unused tables are safer than destructive downgrade.

## Verification matrix

| Scenario | Expected result | Evidence |
| --- | --- | --- |
| Kill after Start | Durable recoverable checkpoint | Integration/process-kill test |
| Kill after four buffered points | Loss stays within documented bound | Failure-injection test |
| Kill during pause | Pause state/duration recover exactly | Fake-clock reopen test |
| Kill during Finish | One checkpoint or one completed workout | Transaction test |
| Resume after movement | First point anchors; no bridge distance | Engine test |
| Account switch | Other user's checkpoint invisible | Repository/provider test |
| 30-minute screen lock | Foreground notification and checkpoint progress continue | Physical-device record |
| Multi-hour session | Bounded memory/frame/write behavior | Profile report |
| Permission revoked | Service stops truthfully; checkpoint remains | Device/manual test |
| Airplane mode/reconnect | Local recording uninterrupted; later sync remains queued | Device/E2E test |

## Exit gate

- [ ] Active checkpoint schema migrates cleanly from all supported local DB versions.
- [ ] Exactly one active checkpoint per user is enforced; completed points/events have stable deterministic sequences.
- [ ] Start/pause/resume transitions are durable and use the IP-1 metric engine.
- [ ] Point flushing meets the five-point/five-second loss objective.
- [ ] Finalization is atomic and idempotent under every injected failure boundary.
- [ ] Recovery offers Resume/Finish/Discard for only the current user.
- [ ] `starting` and `finishing` crash states reconcile deterministically.
- [ ] Unknown process downtime is not counted as active duration.
- [ ] Android foreground service starts/stops with a visible, non-sensitive notification.
- [ ] Screen-off and background behavior passes the physical-device matrix.
- [ ] Process-kill claims come from the documented `integration_test`/ADB harness, distinct from pure unit failure tests.
- [ ] Permission/service failure never leaves a false "tracking" UI state.
- [ ] One authoritative GPS subscription feeds engine, metrics, persistence, and map.
- [ ] Multi-hour performance is measured and remains within agreed bounds.
- [ ] Existing image processing no longer blocks the UI isolate and preserves durable image semantics.
- [ ] No checkpoint or full-fidelity route is silently deleted during rollout/rollback.

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| — | — | No implementation evidence yet | Not started | Planning document only |
| 2026-08-17 | IP-3.4 design (pre-3.1) | [Android background tracking design](../tracking/android-background-tracking-design.md); static read of code, plugin sources, embedding bytecode, and Android/Play docs; no build, test, or device run | Proposed — not approved, nothing delivered | Recommends an own minimal Kotlin foreground service + cached engine over geolocator's notification (insufficient for shade controls) or `flutter_foreground_task`; decisions listed in its §11 |
| 2026-08-17 | IP-3 audit (pre-3.1) | [Battery and active-workout durability audit](../tracking/battery-durability-audit.md); static read of code, plugin/framework sources, and one local build artifact; no build, test, or device run | Audit only — nothing delivered | Failure-boundary matrix, battery findings `B-01`…`B-12`, durability findings `D-01`…`D-10`; endorses the IP-3.4 design with three departures (no default partial wake lock, GPS off on pause, lifecycle-gated tick) and adds four schema-free battery PRs before IP-3.1; lists drift (§7) incl. the unrecorded local debug assemble on the bumped toolchain and the transitively merged `FOREGROUND_SERVICE`/`WAKE_LOCK` |
| 2026-08-18 | IP-3.3/3.4 UX (pre-3.1) | [Workout-tracking UX and accessibility audit](../tracking/workout-tracking-ux-accessibility-audit.md); static read of Track screen, provider/state, live map, recovery card, exit dialogs, theme, manifest, tests, and pinned `geolocator_android-5.0.3` permission source; no build, test, or device run | Audit only — nothing delivered | Findings `UX-01`…`UX-27`; journey table; exact strings `S0`…`S18` for the states IP-3.3 must present (recovery card Resume/Finish/Discard with a permission gate before Resume; loss acknowledged in duration/distance only); recommends the IP-3.4 two-tap notification Finish be **on** (in-app Finish is already confirmed; no undo exists) and a `Recording` / `Waiting for GPS` split in the notification text; stages 0–2 of its plan are schema-free and can precede IP-3.1 |
| 2026-08-18 | IP-3.5 map layer (pre-3.1) | [Map rendering and tile-provider reliability audit](../tracking/map-tile-reliability-audit.md); static read of the map widgets and pinned `flutter_map 8.3.1` / `http 1.6.0` sources; OSMF policy quoted; no build, test, or device run | Audit only — nothing delivered | Confirms tracking/save are tile-independent; adds to the IP-3.5 scope two lifetime defects in `LiveMapFeed` (`M-05` leaked status listeners replaying stale camera moves per completion; `M-16` a new `NetworkTileProvider`/`HttpClient` per rebuild) that should not wait for the incremental-polyline work, plus `M-06` (whole-state watch → per-second re-projection) which IP-3.5 already owns; policy/privacy items (`M-01`…`M-04`, `M-07`, `M-08`, `M-10`) are Flutter-only and schema-free |
