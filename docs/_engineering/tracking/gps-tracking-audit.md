---
published: false
---

# GPS Tracking Audit — Start → position → metrics → map → Finish → SQLite

| Field | Value |
| --- | --- |
| Audited | 2026-08-17, branch `auth-impr` at `d0e5b92` (plus the uncommitted sync-audit doc changes, which were read but not touched) |
| Method | Static read of the Flutter tracking path, the Android manifest/Gradle files, and the geolocator 14.0.2 / geolocator_android 5.0.3 sources in the local pub cache, plus an inventory of the existing automated tests. **Commands run:** read-only `grep`/`sed`/`ls`/`wc`, `git status --short`, `git ls-files`. **Not run:** `flutter test`, `flutter analyze`, any build, any device, CI, staging, or production. Every statement about Android runtime behaviour is inferred from platform/plugin documentation and is labelled as such — none is device-verified. Every claim cites the code it was read from. |
| Owning phases | [IP-1 tracking correctness](../improvement-plan/IP-1-tracking-correctness.md) (delivered behaviour verified here) and [IP-3 workout durability](../improvement-plan/IP-3-workout-durability.md) (the gaps this audit sizes). One finding (F3) belongs to the [sync audit](../sync/sync-reliability-audit.md) as `SYNC-01`. |
| Verdict | **Short, screen-on foreground workouts are correct and safe. Screen-off and process-death workouts are not supported today** — no checkpoint, no foreground service, no wakelock (IP-3, 0 of 5). Multi-hour sessions work but degrade linearly per tick. See §0 and §7. |

Documents read in full: `AGENTS.md`, `improvement-plan/README.md`, `STATUS.md`,
`ACTION-REQUIRED.md`, `IP-1-tracking-correctness.md`, `IP-3-workout-durability.md`, and the
gap list of the sync audit. Source read: every file named in the request plus the Track
screen, teardown, home screen, `main.dart`, DI wiring, `ActivitySyncModel`, and the tests
under `rythmrun_frontend_flutter/test/` (inventory in Appendix A; line citations
spot-checked).

All paths are repository-relative. `provider` = `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/providers/live_tracking_provider.dart`; `service` = `rythmrun_frontend_flutter/lib/core/services/live_tracking_service.dart`; `policy` = `rythmrun_frontend_flutter/lib/core/tracking/gps_point_acceptance_policy.dart`; `timeline` = `rythmrun_frontend_flutter/lib/core/tracking/workout_timeline.dart`; `segmenter` = `rythmrun_frontend_flutter/lib/core/tracking/workout_route_segmenter.dart`; `map` = `rythmrun_frontend_flutter/lib/presentation/features/Map/screens/live_map_feed.dart`; `db` = `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart`; `track_screen` = `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/screens/track_screen.dart`; `repo` = `rythmrun_frontend_flutter/lib/data/repositories/workout_repository_impl.dart`.

---

## 0. Verdict in five lines

1. **Short, screen-on, foreground workouts are correct and safe.** IP-1's claims hold in
   code: one acceptance policy feeds metrics, map and persistence; paused/rejected movement
   adds nothing; finish-while-paused closes once; units are m / s / m/s; the save is atomic
   and idempotent per `(userId, clientSyncId)`; ownership is enforced at every write.
2. **Screen-off and process-death workouts are not supported today** — no checkpoint, no
   foreground service, no wakelock. This is exactly IP-3 (0 of 5 delivered) and STATUS.md
   says so; the code confirms it.
3. **Three things the plans do not say:** (a) session teardown deletes a workout that was
   just finalized but not yet synced (already P0 `SYNC-01` in the sync audit — it also
   negates "Finish & logout saves exactly once"); (b) a mid-workout location-stream error
   has no recovery path — the timer keeps counting and the route silently stops; (c) the
   geolocator plugin already ships the Android foreground service and its manifest entry,
   so IP-3.4 needs three manifest permissions and one settings object, not native code.
4. **Multi-hour sessions work but degrade linearly per tick:** the whole Track screen and
   map rebuild every second and every point, the map re-segments the full route per point,
   and `IndexedStack` keeps that alive on other tabs.
5. **Plan drift is small:** one stale IP-3 audit bullet (the map no longer holds a second
   GPS subscription), the Gradle/AGP/Kotlin bump is declared but unproven (as STATUS says),
   and CLAUDE.md/AGENTS.md carry a stale Flutter test count.

---

## 1. Exact current flow: Start → raw position → accept/reject → metrics → map → Finish → SQLite

```
Track tab tap Start ──► LiveTrackingNotifier.startWorkout ──► LiveTrackingService (singleton)
   │                        │                                     Geolocator.getPositionStream
   │                        │                                     LocationSettings(best, 5 m)  ← generic, no FGS
   │                        ▼                                     ▼ Position (UTC fix time)
   │            locationStream.listen(_onLocationUpdate) ◄─── TrackingPointEntity (mapPosition)
   │                        ▼
   │            GpsPointAcceptancePolicy.evaluate  ──reject──► dropped, nothing changes
   │                        │ accept
   │                        ▼
   │            state.currentSession.copyWith(points+1, distance+Δ, maxSpeed) ; currentLocation ; currentPace
   │                        ▼                                   ▼
   │            Track screen ref.watch(whole state)     LiveMapFeed ref.watch + ref.listen(currentLocation)
   │            (rebuilds every tick/point)             WorkoutRouteSegmenter.buildSegments(full route) → polylines
   ▼
Finish ──► stopWorkout ──► timeline.complete ──► cancel sub/stop stream ──► completion metrics/elevation
       ──► _persistCompletedWorkout ──► WorkoutRepositoryImpl.saveWorkout (owner check)
       ──► LocalDbService.saveWorkoutInLocalDatabase: ONE transaction: workout row + points batch + status batch
       ──► fire-and-forget syncWorkouts()
```

Step by step, with evidence:

1. **Start.** `startWorkout` serialises concurrent starts on `_startFuture` (provider
   :155-168). `_startWorkoutOnce` refuses if disposed/quiescing/starting/stopping/resetting,
   if an unsaved workout is pending, or if a non-completed session exists (:171-186); retries
   pending GPS cleanup (:195-206); checks permission (:208-228); reads the user id from the
   session **once** (:230-237); creates `WorkoutTimeline.start(now)` and the session with
   `ClientSyncIdGenerator.generate(startTime, userId)` and an initial `active` status event
   (:239-257); subscribes to the broadcast stream **before** starting the native source
   (:259-264); on success sets `_activeSegmentStartedAt = startTime`, publishes state, starts
   the 1-second timer (:270-282). Failure cleans up and resets (:283-293).
2. **Raw platform position.** `LiveTrackingService.startTracking` uses generic
   `LocationSettings(accuracy: best, distanceFilter: 5)` (service :81-90). On Android that
   becomes FusedLocation `PRIORITY_HIGH_ACCURACY`, interval **5000 ms** (plugin default when
   Dart passes no `timeInterval` — `LocationOptions.parseArguments`, geolocator_android
   5.0.3), min-displacement 5 m; `Position.timestamp` is `Location.getTime()` mapped as UTC
   (`LocationMapper.java:19`; `position.dart:161-164`). `mapPosition` keeps the acquisition
   timestamp (service :147-157). Errors are forwarded to the broadcast controller (:116-118).
   No coordinates are logged anywhere on this path; `TrackingPointEntity.toString` redacts
   (`lib/domain/entities/tracking_point_entity.dart:55-58`).
3. **Acceptance/rejection.** `_onLocationUpdate` drops points while
   disposed/starting/stopping/resetting or without a session (provider :648-657), then calls
   the pure policy with `isWorkoutActive`, `previousAcceptedPoint`, `activeDistanceAnchor`,
   `activeSegmentStartedAt` (:659-667). Policy order (policy :100-246): finite values →
   coordinate range → (0,0) → accuracy present, ≥0, ≤50 m → strictly increasing timestamp vs
   last accepted → not before the active boundary → reported speed within the per-type cap
   (walk/hike 5, run 10, cycle 30 m/s) → paused ⇒ accepted as marker only → no anchor ⇒
   anchor (0 distance, new segment) → anchor gap > 30 s ⇒ accepted, 0 distance, new segment
   → haversine distance & implied speed vs cap → accepted with distance.
4. **Metric update.** Accepted paused points only update `currentLocation` (:670-675).
   Active points: instantaneous pace from this interval only (:677-685), `trackingPoints`
   copied +1, `totalDistance += Δ`, `maxSpeed = max(implied)` (:687-693), anchor advanced
   (:694-696), state published (:698-702). Elapsed time comes from
   `WorkoutTimeline.observe(now)` every second (:720-740) — wall-clock derived, so it
   self-corrects after any stall.
5. **Pause / resume.** Pause cancels the timer, `timeline.pause(now)`, clears anchor and
   boundary, appends a `paused` event, `isTracking=false` (:300-339) — the GPS subscription
   is **not** stopped. Resume `timeline.resume(now)`, sets `_activeSegmentStartedAt =
   resumeAt`, appends `active`, restarts the timer (:342-388); the next accepted point becomes
   a zero-distance anchor by construction (policy :188-196).
6. **Map.** `LiveMapFeed` watches the entire state (map :357), listens to `currentLocation`
   for the marker/follow (:369-378), and on any points/status change re-runs
   `WorkoutRouteSegmenter.buildSegments` on the whole route and rebuilds every polyline with a
   `setState` per segment plus one for the start marker (:129-181, :192-195, :207-210,
   :316-318). The map has **no** GPS subscription of its own — the only
   `locationStream.listen` in `lib/` is provider :259.
7. **Finish.** `stopWorkout` dedups concurrent calls (:391-403). `_stopWorkoutOnce`:
   `timeline.complete(now)` (closes an open pause once — timeline :91-114), cancels timer,
   cancels subscription and stops the source (:436-439, :752-781), computes m/s average,
   min/km pace, kcal, segmented elevation (:441-475), keeps the completed entity in
   `_unsavedCompletedWorkout` (:476), then persists (:495).
8. **SQLite save.** `WorkoutRepositoryImpl.saveWorkout` re-reads the current user and
   rejects an owner mismatch (repo :55-63), then `saveWorkoutInLocalDatabase(userId:)`
   asserts owner and metrics version, and in **one transaction** returns the existing row for
   the same `(user_id, client_sync_id)` if identity matches (else throws), otherwise inserts
   the workout, all points in one batch, and all status events (db :201-311); the unique
   index `idx_workouts_user_client_sync_id` backs it (:1617-1620). Sync is fire-and-forget
   after commit (repo :72-74). A failed save leaves the workout in memory with Retry/Discard
   UI (provider :614-645; track_screen :277-385).

**Time bases in play:** point timestamps = GPS fix time (UTC); timeline/status events =
`DateTime.now()` local (`lib/data/repositories/live_tracking_repository_impl.dart:15`);
SQLite stores points as `…Z` and start/end/status as offset-less local ISO (db :256-257,
:290, :303); the sync payload converts everything to UTC
(`lib/data/models/activity_sync_model.dart:14-15, 37, 49`).

---

## 2. Correctness assessment (Q2)

| Aspect | Verdict | Evidence | Notes |
| --- | --- | --- | --- |
| Distance (m) | Correct in the accepted-point model | policy :218-245; provider :690 | Haversine between consecutive distance-contributing accepted points. Two gaps: no accuracy-relative displacement gate (creep while stationary in 30–50 m accuracy) and gaps > 30 s contribute 0 m (see §3, §7 F5/F6). |
| Pace (min/km) | Correct units; noisy display | provider :677-685; `lib/core/utils/calculation_helper.dart:5-16` | Live pace is one 5-s interval; average pace at finish from active time. `calculatePace` truncates to whole seconds (`inSeconds`). |
| Speed (m/s) | Correct | provider :687-693, :469-472; helper :30-41, :44-59; `live_tracking_state.dart:110-116` | Max speed = max implied interval speed (noise-inflatable, bounded by the per-type cap). Average from active duration. km/h ×3.6 once at presentation. |
| Pause / resume | Correct | provider :300-388; policy :178-196; timeline :52-84 | Paused movement = marker only; first resumed point = zero-distance anchor; open pause closed once on finish (timeline :91-114). Tests: provider_test "paused movement and the first resumed point add no distance", "finish while paused closes once…". |
| Poor accuracy | Partially handled | policy :129-144 | Hard ceiling 50 m; nothing else. Fine for rejecting garbage; permissive for creep. Device evidence is MC-1.5's job. |
| GPS jumps | Handled, anchor preserved | policy :198-235; test "keeps the last accepted anchor after rejecting a jump" | Implied speed vs per-type cap relative to the anchor; a persistent jump is accepted after 30 s as a new segment (no lockout). |
| Timestamp changes | Bounded, not eliminated | timeline :15-19, :159-162; policy :146-157, :159-166 | Backward wall-clock change: elapsed **freezes** until the clock passes the previous max; points are rejected as non-monotonic until GPS time passes the last accepted. Forward change: elapsed **inflates**; if the jump > 30 s the bridge contributes 0 m. Only the pure `WorkoutTimeline` has a backward-clock test; nothing at notifier level. |
| Long signal gaps | Handled conservatively | policy :87, :208-216; segmenter :35-39 | > 30 s since the anchor ⇒ new segment, zero bridge distance, visible break. Under-counts real distance in tunnels/underpasses and across every screen-off period. Design choice from IP-1.2, tested at policy/segmenter level only. |
| Finish while paused | Correct | timeline :91-114; provider :428-434 | Test "finish while paused closes once and excludes shutdown latency". |
| Units / metrics version | Correct (D-003) | `workout_session_entity.dart:26-31`; db :148-149, :262; sync model :12-19 | `metricsVersion` 2 written; legacy 1 preserved. |

---

## 3. Where data can be lost, duplicated, misattributed, or become slow/battery-heavy (Q3)

### Loss

| # | Point | Evidence | Trigger → effect |
| --- | --- | --- | --- |
| L1 | Whole active workout lives in memory until Finish | provider :57-72; only writes at :495, :542 → db :201 | Process death (OOM, swipe-away, crash, OS kill in background) at any moment before a successful save ⇒ everything lost. No checkpoint tables exist (db :138-198). |
| L2 | No foreground service / wakelock; whileInUse only | service :81-90; `rythmrun_frontend_flutter/android/app/src/main/AndroidManifest.xml:3-6` (no `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`); geolocator 14.0.2 README lines 71-76 | *Platform inference:* once the activity is not visible, Android stops delivering "while-in-use" location; Android 12+ may freeze the process. Elapsed keeps counting (wall clock) while distance stops; on return the > 30 s gap yields a zero-distance bridge ⇒ route and distance permanently lost for the screen-off period; pace/avg speed wrong. |
| L3 | Stream error ⇒ no recovery | provider :706-717 (sets a message only); service :116-118; map :360-368 shows once and clears | Location services toggled, provider failure ⇒ points silently stop; workout stays "active" with a running timer; nothing re-subscribes. No test emits an error while active (only post-dispose: `test/presentation/features/live_tracking/providers/live_tracking_provider_test.dart:391`). |
| L4 | Zero-distance bridge across > 30 s gaps | policy :208-216 | Under-count by design; magnitude unmeasured. |
| L5 | Failed save is memory-only | provider :614-645, :521-554 | Retry/Discard UI exists, but a subsequent process death loses it (IP-1 explicitly defers this to IP-3). |
| L6 | **Teardown deletes the finalized-but-unsynced workout** | `lib/presentation/common/session/user_scope_teardown.dart:208→249`; `lib/presentation/common/providers/user_scope_teardown_provider.dart:25` (un-awaited `clearLocalWorkouts`); db :1340-1354 deletes every row for the user regardless of `synced` | "Finish & logout" and forced-auth-loss finalization save exactly once, then the IP-2.7 clearing wipes the row before the fire-and-forget sync can run (the operation gate is being drained). Already `SYNC-01` P0 in the sync audit; listed here because it breaks the Finish→SQLite guarantee, not re-derived. |
| L7 | Rejected raw samples are discarded | policy; provider :668 | By plan design; a future better policy cannot re-score them. Acceptable. |
| L8 | Points during `_isStarting`/`_isStopping` windows | provider :649-655 | Milliseconds; acceptable. |

### Duplication

None found in the local path: concurrent Finish dedups (provider :391-403; test "concurrent
finish calls await one finalization and one save"); repeated save is idempotent by identity
(db :231-251; `test/core/services/local_db_service_schema_test.dart:143`); equal-timestamp
points cannot both be accepted (policy :151-156); restore dedups by
`clientSyncId`/`remoteActivityId` (repo :528-539; db :1357-1389). Remote idempotency is the
backend's `(userId, clientSyncId)` contract, out of scope here.

### Misattribution

None found: user id captured at Start (provider :230); save re-checks the current user and
the entity owner (repo :57-63; db :205-211); all reads/mutations are owner-scoped (db
:1156-1188, :344-364); the notifier is invalidated on teardown so B never inherits A's
in-memory session (teardown_provider :34). A retry of A's unsaved workout under B fails closed
with a fixed message (repo :61-63 → provider :637-643).

### Slow / battery

| # | Point | Evidence | Note |
| --- | --- | --- | --- |
| P1 | Whole Track screen rebuilds on every 1-s tick and every point | track_screen :113 `ref.watch(liveTrackingProvider)` | The `select` providers at provider :864-883 exist but are unused there. |
| P2 | Map: full re-segmentation + all polylines rebuilt + several `setState`s per point | map :151-181, :192-195, :207-210, :316-318 | Segmenter is O(n·statusChanges) with per-segment `List.unmodifiable` copies. |
| P3 | Points list copied per accepted point | provider :689 | O(n) per point; ~2–4k points for 3–6 h at 5 s — cheap in absolute terms, but it is the pattern IP-3.5 targets. |
| P4 | All four tabs built eagerly and kept alive; map init requests location (and permission) at app open | `lib/presentation/features/home/screens/home_screen.dart:94-107`; map :76-81 → service :121-127 → :43-50 | |
| P5 | GPS stays at HIGH_ACCURACY / 5 s during pause | provider :300-339 (no `stopTracking`) | |
| P6 | Sync (including the paginated history restore) runs on every app resume, also mid-workout | `lib/main.dart:57-61` | |
| P7 | Backend cap 12,000 points/activity | `RythmRun_backend_nodejs/src/models/dto/activity.dto.ts:42`; sync audit `SYNC-05` | Not reachable at 5 s / 5 m (~16 h moving), but any IP-3.4 interval tightening (1–2 s) makes 4–6 h workouts permanently unsyncable. |

---

## 4. Plan vs code drift (Q4)

**IP-1 (Verification) — code matches the delivered claims inspected:** one policy for
map/metrics/persistence (`LiveMapSegmentBuilder` delegates to `WorkoutRouteSegmenter`, the
map has no rejection logic); paused/resume semantics; finish-while-paused; canonical units
(D-003); `metricsVersion`; explicit-null state (`LiveTrackingState.copyWith` sentinel);
owner-scoped DAO; `PRAGMA foreign_keys` per connection (db :80-82, verified :122-136); no
coordinate logging on tracking paths. IP-1's checked exit-gate boxes (IP-1 :126-150) are
consistent with the code; the unchecked ones are the MC items.

**IP-3 (Planned) — accurate except:**

| IP-3 text | Code today | Drift |
| --- | --- | --- |
| Audit evidence: "the provider subscribes directly to the global location singleton, **while the map maintains another subscription**" (IP-3 :26) and IP-3.5 item 5 "Remove the map's direct location subscription" (:290) | Only one `locationStream.listen` (provider :259); the map consumes accepted points via Riverpod (map :369-378). IP-1.2's evidence log already records "one `locationStream.listen` consumer". The singleton half is still true (`LiveTrackingService.instance`, `lib/core/di/injection_container.dart:272-273`). | **Stale** — half of IP-3.5 item 5 was delivered by IP-1.2; the exit-gate line "One authoritative GPS subscription…" (:347) is already true for the subscription part. |
| "Android manifest contains foreground location permissions but no complete foreground-location service declaration/permission set" (:27) | App manifest lacks the three permissions; **the plugin's merged manifest already declares `GeolocatorLocationService` with `foregroundServiceType="location"`** (`geolocator_android-5.0.3/android/src/main/AndroidManifest.xml:5-9`), and `AndroidSettings.foregroundNotificationConfig` exists (`android_settings.dart:18,56`). | Still true, but the remedy is smaller than "native/Flutter service integration" implies (IP-3.4 :233). |
| IP-3.4 item 1 versions "declared, not proven" (:240-249) | Gradle 8.14 (`android/gradle/wrapper/gradle-wrapper.properties:5`), AGP 8.11.1, Kotlin 2.2.20 (`android/settings.gradle.kts:21-22`) declared. | Consistent; no build was run in this audit. |
| Everything else in the audit-evidence list (memory-only session, first write on Finish, generic `LocationSettings`, per-point copies/rebuilds, lifecycle syncs but doesn't checkpoint) | provider :57-72, :495; service :81-84; provider :689; map :151; main :57-61 | Accurate. |
| Checkpoint tables, `sequence` column, `starting/finishing/recoverable` states, `integration_test/`, `tool/device_test/` | Absent (db :15 version 6, :138-198; neither directory exists) | Expected — nothing of IP-3 is built. |

**Cross-doc drift:** AGENTS.md/CLAUDE.md say Flutter baseline **359 passed** (AGENTS.md
:111); STATUS.md :39 says **356** and explains the delta. Static count is 345
`test(`/`testWidgets(` call sites (parametrised loops add more at runtime); the suite was not
run. Also `LiveMapFeed`/segment builder/helper have **zero** tests, and there is no
notifier-level test for stream errors, clock jumps, or long gaps.

---

## 5. Suitability by scenario (Q5)

| Scenario | Suitable today? | Why |
| --- | --- | --- |
| Short foreground workout (screen on) | **Yes** | Correct metrics, single subscription, atomic idempotent save, recovery UI for save failure. Residual: distance creep when stopped without pausing in poor accuracy; first-fix noise; a crash mid-workout loses it (rare in foreground). |
| Screen-off workout | **No** | L2: no FGS/wakelock/permissions ⇒ no updates once the activity is invisible (platform inference); time keeps counting, distance does not. Not a bug in the policy — the plumbing IP-3.4 owns is absent. |
| Process death | **No** | L1/L5: nothing durable before Finish; no recovery UX; no device harness to prove any of it. |
| Multi-hour (3–6 h) | **Works, degrades** | Memory is fine (a few thousand points); CPU cost per tick/point grows linearly (P1–P3); OSM tile fetches; save/sync of ~4k points is well under the 3 MiB / 12k caps at 5 s sampling. Combined with L2, a real multi-hour session only works with the screen kept on. |

---

## 6. Smallest low-cost architecture (Q6)

Nothing new beyond what IP-3 already lists; the point is what *not* to build.

1. **Foreground tracking = geolocator's built-in service.** Replace `LocationSettings` with
   `AndroidSettings(accuracy: high, distanceFilter: 5, intervalDuration: 5 s (measure before
   tightening), foregroundNotificationConfig: ForegroundNotificationConfig(title/text without
   coordinates, setOngoing: true, enableWakeLock: true, enableWifiLock: false))` in
   `LiveTrackingService.startTracking`; add `FOREGROUND_SERVICE`,
   `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS` to the app manifest; request
   `POST_NOTIFICATIONS` at first Start via a ~30-line `MethodChannel` in `MainActivity.kt`
   (zero deps) or `permission_handler` if Dart-only is preferred. Keep `whileInUse`; **no**
   `ACCESS_BACKGROUND_LOCATION`. Fallback only if the Samsung matrix fails:
   `flutter_foreground_task` (OSS). No native service, no second isolate, no WorkManager.
2. **Checkpoints = three SQLite tables in the existing DB (v7)** exactly as IP-3's data
   model, written by a small DAO in/next to `LocalDbService`. **Write each accepted point
   synchronously** (point insert + aggregate update in one transaction,
   `(checkpoint_id, sequence)` unique with `ConflictAlgorithm.ignore`). At the current ≥5 s
   interval this already satisfies "≤5 points / ≤5 s" with zero buffering code; the plan
   explicitly allows tightening. Persist start/pause/resume/finish/discard transitions
   immediately. Store checkpoint timestamps as UTC ISO.
3. **Finalize from the checkpoint in one transaction**: refactor `saveWorkoutInLocalDatabase`
   to accept a `DatabaseExecutor` so the completed insert and the checkpoint delete share a
   transaction; the existing unique index makes retry idempotent; keep `starting`/`finishing`
   states — they make recovery deterministic.
4. **Recovery = extend `WorkoutRecoveryCard`** with Resume, driven by a query for the current
   user's checkpoint after session identity is established; append an interruption boundary at
   the last durable point (unknown downtime excluded); never auto-resume.
5. **UI cost:** use the existing `select` providers in the Track screen; make the map append to
   the last polyline when only the active segment grew, one `setState` per update; skip map
   work when the Track tab is not the current `IndexedStack` index. Measure with a fake
   repository replaying a recorded 4–6 h route.
6. **Time base:** keep wall clock (it survives suspend and process death), keep the clamp,
   add notifier-level clock-jump tests. Do not switch to `Stopwatch` (does not advance in
   suspend and dies with the process).
7. **Sequence before IP-3.2 finalize lands:** SYNC-01 (a)+(b) — otherwise the durable
   finalize is undone at logout.

---

## 7. Prioritized findings (Q7)

| ID | Sev | Finding | Evidence | User impact | Smallest safe fix | Test required |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | **High** | Active workout is memory-only; no checkpoint before Finish | provider :57-72, :495, :542; db :138-198 (no active tables) | Process death loses the entire workout | IP-3.1/3.2: v7 tables + per-point synchronous write + finalize-from-checkpoint (§6.2-3) | FFI DB tests (write/read/cascade/unique); notifier test with fake DAO asserting a checkpoint exists before the first point; device `am force-stop` harness |
| F2 | **High** | No Android foreground service, wakelock, or FGS permissions | service :81-90; manifest :3-6; geolocator README :71-76; plugin manifest :5-9 | Screen-off/background: distance stops, time continues, route lost (platform inference) | `AndroidSettings(foregroundNotificationConfig…)` + 3 manifest permissions + POST_NOTIFICATIONS request (§6.1) | Unit test via an injected settings factory that `startTracking` passes the foreground config; physical-device matrix (IP-3.4) |
| F3 | **High** (P0 in sync audit) | Teardown wipes finalized-but-unsynced workout | teardown :208→249; teardown_provider :25 (un-awaited); db :1340-1354 | "Finish & logout"/forced loss saves then deletes | `SYNC-01` (a)+(b): keep `synced=0` and queued rows, `await` the clear | Teardown test: unsynced row survives; sync afterwards under same user |
| F4 | **Medium** | Stream error mid-workout has no recovery or truthful state | provider :706-717; service :116-118; map :360-368 | Silent no-GPS workout, timer runs | Add a persistent `trackingInterrupted` flag shown until points resume; one bounded re-subscribe (`stopTracking`+`startTracking`); remove the ambiguity of `isTracking` | Notifier test: emit error while active ⇒ flag set, resubscribe attempted once, timer unchanged |
| F5 | **Medium** (decision) | > 30 s gaps contribute zero distance | policy :87, :208-216; segmenter :35-39 | Under-count in tunnels/underpasses; every screen-off gap becomes a hole even after F2 for OEM kills | Either document the trade-off in IP-1/IP-3, or add a bounded straight-line bridge (gap ≤ N min, implied speed ≤ cap, both accuracies ≤ 20 m; visual break kept) with `policyVersion` 2 | Policy fixtures for bridged/unbridged; MC-1.5 device run |
| F6 | **Medium** (device evidence needed) | No accuracy-relative displacement gate; 50 m accepted for distance | policy :86, :140-144, :218-235 | Distance creep at stops without pausing; noisy first fixes | Count distance only when `Δ ≥ max(prevAcc, curAcc)` (accept as marker otherwise) or lower the distance-contribution accuracy bound; bump `policyVersion` | Policy fixtures (stationary jitter, warm-up); MC-1.5 |
| F7 | **Medium** | Whole Track screen and map rebuild per tick/point; map re-segments full route with multiple `setState`s; eager tabs | track_screen :113; map :151-181, :192-210, :316-318; provider :689; home :94-107 | Linear CPU growth per second in long sessions; battery | Use existing `select` providers; append-only polyline; single `setState`; gate map work on the visible tab | Widget rebuild-counter test for stats card; unit test for the append helper; multi-hour replay profile (IP-3.5) |
| F8 | **Low** | Wall-clock only; jumps freeze/inflate elapsed; points rejected after backward correction | `live_tracking_repository_impl.dart:15`; timeline :159-162; policy :146-157 | Rare, bounded | Keep wall clock; persist transitions (IP-3); add notifier-level jump tests | Notifier tests: ±5 min jump mid-workout |
| F9 | **Low** | Debug text rendered in Track screen | track_screen :129-135 | Debug strings visible to users | Delete the `Column` | Widget smoke |
| F10 | **Low** | Map init prompts for location permission at app open; `getCurrentLocation` calls `requestPermission` | map :76-81; service :121-127, :43-50 | Out-of-context permission prompt (Play policy risk) | `getCurrentLocation` checks but does not request; request on Start only | Service test with an injected permission seam |
| F11 | **Low** | GPS at high accuracy during pause | provider :300-339 | Battery on long pauses | Defer; optionally lower priority while paused | — |
| F12 | **Low** | Live pace = one 5-s interval; integer-second truncation | provider :677-685; helper :5-16 | Flickery pace | Rolling 30–60 s window over accepted deltas | Unit test |
| F13 | **Low** | Local start/end/status stored as offset-less local ISO; stats SQL uses `julianday` on them | db :17-30, :256-257, :303 | Off by DST delta for DST-spanning workouts; TZ change shifts status vs UTC points | Write UTC for new rows (as the sync model already does) | FFI fixture spanning a DST change |
| F14 | **Info** | 12,000-point backend cap vs any interval tightening in IP-3.4 | `activity.dto.ts:42`; `SYNC-05` | Long routes become unsyncable | Decide interval with the cap in view; interim bound per SYNC-05 | Payload fixture at cap |

---

## 8. Phased plan aligned with IP-3.1–3.5, with rollback and Android device tests (Q8)

**Phase 0 — prerequisites (before IP-3.1).** Run debug **and** release configuration/build
on Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 and record the result (IP-3.4 item 1 says this
is owed; budget disk). Land F9 (delete debug text) and SYNC-01 (a)+(b) so later finalization
is not undone. Add the notifier-level tests that are missing today (stream error while
active, ±clock jump, > 30 s gap through the notifier). Rollback: revert; no schema.

**Phase 1 — IP-3.1 checkpoint DAO + engine seam.** DB v7: `active_workout_checkpoints` (one
active per user, unique `(user_id, client_sync_id)`), `active_tracking_points` (unique
`(checkpoint_id, sequence)`), `active_status_events`; `sequence` on completed
`tracking_points`/`status_changes` backfilled by `(timestamp, id)`; `foreign_key_check` in
the migration like v6. Notifier writes `starting`→`active` at Start, one transaction per
accepted point, pause/resume events immediately; behind a compile-time `--dart-define` flag
default **off**. Tests: IP-3.1's list (checkpoint before first point; retry ⇒ no duplicate
sequence; zero-point pause durable; user change aborts writes; concurrent Start ⇒ one
checkpoint; legacy sequence backfill once; upgrade from v3–v6 fixtures via
`LocalDbTestHarness`). Rollback: forward-only schema (IP-3 rollback plan); flag off restores
today's path; unused tables are harmless.

**Phase 2 — IP-3.2 exactly-once finalize.** Finish: stop points, close open pause,
`finishing`, recompute metrics from durable rows, one transaction insert-completed +
delete-checkpoint (refactor `saveWorkoutInLocalDatabase` to take a `DatabaseExecutor`);
Discard deletes only the checkpoint. Failure-injection via a wrapping
`DatabaseFactory`/`Database` that throws at the N-th statement over sqflite_common_ffi:
before flush, after flush/before `finishing`, during insert, after commit/before ack, seeded
completed-row+checkpoint reconcile, repeated Finish. Rollback: flag off; a `finishing`
checkpoint left behind is reconciled by Phase 3.

**Phase 3 — IP-3.3 recovery UX.** On notifier creation after session identity: query the
current user's checkpoint; reconcile `starting`/`finishing` deterministically; active ⇒
interruption boundary at last durable point; paused ⇒ pause stays open;
`WorkoutRecoveryCard` + Resume/Finish/Discard; no auto-resume; foreign checkpoints
invisible. Enable the flag by default in debug/internal builds. Tests: kill/reopen matrix per
IP-3.3; B cannot see A's checkpoint; corrupt checkpoint preserved. **Device tests begin
here:** `integration_test/` + `tool/device_test/` scripts (IP-3 rollout item 4): install
release build against staging, synthetic account, start workout, `adb shell am force-stop
<pkg>` at each boundary, relaunch, assert the offered choice and the resulting single
completed row; `adb logcat` scan for coordinates/timestamps (must be absent). Rollback: flag
off keeps checkpoints intact and hides recovery UI (IP-3 rollback: never delete checkpoints
on rollback).

**Phase 4 — IP-3.4 foreground/screen-off.** Manifest permissions +
`AndroidSettings(foregroundNotificationConfig…)` + POST_NOTIFICATIONS request at first
Start; service stops on Finish/Discard/account loss/permission revoked; denied-permission and
OEM-restriction messaging; never claim tracking when the service failed to start. **New
maintainer item for ACTION-REQUIRED:** Google Play requires a foreground-service-type
declaration in the Play Console for `FOREGROUND_SERVICE_LOCATION` on targetSdk ≥ 34 — a
console action, not code (confirm the current console text). Device matrix (IP-3.4): stock
device, Samsung with background restrictions, oldest supported API, normal + battery-saver,
≥30 min screen locked, one multi-hour session, online/airplane/reconnect; record
device/OS/plugin versions; verify notification text has no coordinates. Rollback: a config
switch that omits `foregroundNotificationConfig` returns to today's foreground-only
behaviour; manifest permissions are inert when unused.

**Phase 5 — IP-3.5 long-session cost.** `select`-based Track screen widgets; append-only
polyline with one `setState`; skip map work when the tab is not visible; keep full-fidelity
points in the checkpoint store, not in every state emission; measure memory/frame/DB-write/
battery with a recorded multi-hour route replayed through a fake repository, on the same
devices as Phase 4. Rollback: pure UI, revert.

**Exit evidence discipline (README rule 8 and ACTION-REQUIRED):** none of the above is
"done" on merge; each phase appends a dated evidence row to IP-3, and Phases 3–5 owe
physical-device rows. Nothing in this audit was device-, CI-, or production-verified.

---

## Appendix A — test coverage relevant to this audit (from the `test/` inventory)

- Policy: `test/core/tracking/gps_point_acceptance_policy_test.dart` (12 tests: thresholds,
  finiteness, ranges, accuracy, monotonic timestamps, resume boundary, reported/implied
  speed caps, 30 s gap at :171, anchor after rejected jump, paused markers, haversine).
- Timeline: `test/core/tracking/workout_timeline_test.dart` (4 tests incl. backward clamp
  at :80). Segmenter: `test/core/tracking/workout_route_segmenter_test.dart` (4 tests).
- Notifier: `test/presentation/features/live_tracking/providers/live_tracking_provider_test.dart`
  (18 tests: pause/resume distance, finish-while-paused, elapsed timer, rejected samples,
  start/reset/dispose/account-exit serialisation, cleanup failures, save failure retry/discard).
  Stream error is tested **only** after dispose (:391, `addError` at :665).
- DB: schema (idempotent save at :143), metrics, migration (v3–v5 fixtures), ownership tests.
- Sync: repository gate tests, sync coordinator, `ActivitySyncModel` (UTC, m/s).
- **Missing:** any process-death/restart test, any `LiveMapFeed` test, notifier-level clock
  jump / long gap / stream error while active, any performance bound, `integration_test/`,
  `tool/device_test/`.

## Appendix B — explicitly not verified here

- Runtime behaviour of geolocator's Android stream after `LocationServiceDisabledException`
  (whether the native listener survives) — F4 is written so it does not depend on this.
- Actual accuracy/creep magnitudes (F5/F6) — MC-1.5's on-device run.
- The Flutter/backend test suites, analyzer, any build, the Play Console FGS requirement
  text (from platform knowledge, confirm on the console).
- The sync audit's findings beyond `SYNC-01`/`SYNC-05`, which are cited, not re-audited.
