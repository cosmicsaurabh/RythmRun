---
published: false
---

# Android Background Tracking and Notification Controls — Design for IP-3.4

| Field | Value |
| --- | --- |
| Status | **Proposed — awaiting maintainer approval. No code changed.** |
| Written | 2026-08-17, branch `auth-impr` at `d0e5b92` (plus the uncommitted sync/GPS audit docs, read but not touched) |
| Owning phase | [IP-3 workout durability](../improvement-plan/IP-3-workout-durability.md) — primarily IP-3.4, with the IP-3.1–3.3 pieces it depends on |
| Method | Static read of the Flutter tracking path, Android manifest/Gradle, `MainActivity.kt`, session/teardown plumbing, the SQLite service and test harness; the `geolocator_android 5.0.3`, `location 7.0.1`, `flutter_foreground_task 10.0.0`, `flutter_background_service_android 6.3.1` sources in the local pub cache; the Flutter 3.44.1 Android embedding (`javap` on `flutter_embedding_release`); and the official Android/Play documentation cited in §12. **Not run:** any build, `flutter test`, `flutter analyze`, emulator, device, CI, staging, or production. Every Android runtime statement is inferred from platform documentation or plugin source and is labelled as such. |
| Related | [GPS tracking audit](./gps-tracking-audit.md) (same day; §6 there proposes geolocator's built-in foreground notification — §6 here explains why this design departs from that on one point), [Sync reliability audit](../sync/sync-reliability-audit.md) (`SYNC-01`) |
| Decision needed | Approve §3 (architecture), §6 (dependency choice), and the list in §11 before PR-1 in §8 |

Purpose: a concrete, reviewable design for the smallest safe Android background-tracking and
notification-control implementation, sized so a single developer can build and maintain it,
using only platform APIs and local persistence. Nothing here is delivered; the sequence in §8
is the work.

---

## 1. Requirements this design must satisfy

Restated from the request; each is answered in the section noted.

| # | Requirement | Answered in |
| --- | --- | --- |
| R1 | Start from a visible Flutter screen creates a durable, user-scoped checkpoint **before GPS begins** | §7.2 (Start) |
| R2 | Foreground location tracking continues through screen-off/background with a visible ongoing notification | §4, §5.5 |
| R3 | Notification controls work with no Flutter screen open: Active → Pause/Finish; Paused → Resume/Finish; body tap opens the current workout safely | §5.5, §7.4 |
| R4 | Every action is idempotent and uses durable state; never depends solely on a Dart `StateNotifier` being alive | §4.2, §7.4 |
| R5 | Pause stops expensive high-accuracy updates while retaining enough service state to Resume safely | §7.2 (Pause/Resume) |
| R6 | Crash/kill leaves exactly one recoverable checkpoint or one completed workout — never neither, never duplicates | §7.2, §7.3, §7.5 |
| R7 | Account switch / logout never lets one user resume, finish, see, or alter another user's checkpoint | §7.6 |
| R8 | No `ACCESS_BACKGROUND_LOCATION` unless strictly required — with the reasoning | §7.7 |
| R9 | Android 14+/target-36 compliant FGS declaration, permissions, service type, channels, `PendingIntent` mutability, receiver export | §5.1, §5.2, §5.5 |
| R10 | Denied notification permission handled honestly | §7.7 |
| R11 | Android's system "Stop" for foreground services + recovery on next launch | §7.5 |
| R12 | No raw coordinates/routes in logs or notification text | §7.8 |

---

## 2. Verified current state

### 2.1 Facts checked against the code

| Claim | Result | Evidence |
| --- | --- | --- |
| App targets Android SDK 36 | **True.** `compileSdk 36`, `targetSdk = 36`; `minSdkVersion flutter.minSdkVersion` resolves to **24** on the pinned Flutter 3.44.1 | `rythmrun_frontend_flutter/android/app/build.gradle:150,155,153`; `$FLUTTER/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:26` |
| Manifest has only fine/coarse location permissions | **True for the app manifest** (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`). Nuance: the *merged* manifest also gains two dormant `foregroundServiceType="location"` services from plugins — geolocator's `GeolocatorLocationService` and the `location` plugin's `FlutterLocationService`. Neither plugin declares `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, or `POST_NOTIFICATIONS`, so switching geolocator's foreground mode on today would fail with `SecurityException` on API 28+ (platform documentation) | `android/app/src/main/AndroidManifest.xml:4-6`; `geolocator_android-5.0.3/android/src/main/AndroidManifest.xml`; `location-7.0.1/android/src/main/AndroidManifest.xml` |
| Tracking uses geolocator with generic `LocationSettings` | **True.** `geolocator 14.0.2` / `geolocator_android 5.0.3`; `LocationSettings(accuracy: best, distanceFilter: 5)`. `location 7.0.1` is used only for the "turn on GPS" system dialog. `permission_handler 12.0.3` is in `pubspec.lock` but **not imported anywhere under `lib/`** | `lib/core/services/live_tracking_service.dart:81-90,190-224`; `pubspec.lock` |
| Active workout state is in Riverpod memory and saved only at Finish | **True.** `LiveTrackingNotifier` holds session, timeline, points, anchors; the first SQLite write is `_persistCompletedWorkout` after `stopWorkout`. That save is one transaction, deduplicated on `(user_id, client_sync_id)` (index `idx_workouts_user_client_sync_id`, v6) | `lib/presentation/features/live_tracking/providers/live_tracking_provider.dart:57-72,405-515,614-645`; `lib/core/services/local_db_service.dart:201-307,1618-1621` |
| No foreground service, persistent notification, receiver, or action handling | **True.** `MainActivity.kt` is a 10-line `FlutterFragmentActivity` (`enableEdgeToEdge`); no other Kotlin exists. `main.dart` lifecycle handling only triggers sync on `resumed` | `android/app/src/main/kotlin/com/github/cosmicsaurabh/rythmrun/MainActivity.kt`; `lib/main.dart:39-78` |
| Android-only | Honoured (D-008). Nothing here touches `ios/`. | — |
| Personal, budget-constrained | Honoured. Platform APIs + SQLite; **no new pub dependency, no paid service** in the recommended path. | — |

### 2.2 Existing seams the design reuses (do not rebuild)

| Seam | Where | Used for |
| --- | --- | --- |
| Pure timeline (`start/pause/resume/complete/observe/snapshotAt`, monotonic clamp) | `lib/core/tracking/workout_timeline.dart` | Rebuilt from five persisted columns after restart (§7.1) |
| One GPS acceptance policy | `lib/core/tracking/gps_point_acceptance_policy.dart` | Unchanged; the engine calls it exactly as the notifier does now |
| Single `locationStream` consumer | `live_tracking_provider.dart:259` (map reads the provider, not the stream: `live_map_feed.dart:357-378`) | The engine becomes that one consumer |
| SQLite v6, `PRAGMA foreign_keys` per connection, strict `_onOpen` schema verification, `if (oldVersion < N)` migration blocks, injectable `DatabaseFactory`/path | `local_db_service.dart:14-15,62-136,1438-1482` | v7 migration and DAO follow the same pattern; tests use `test/support/local_db_test_harness.dart` |
| Per-user clearing at teardown | `local_db_service.dart:1340-1354` via `user_scope_teardown_provider.dart:21-51` | Extended to delete the user's checkpoint |
| D-011 exit requirements and drain order | `lib/presentation/common/session/user_scope_teardown.dart:122-134,137-259` | Orphan checkpoint counts as an active workout |
| `UserScopeOperationGate` leases | `lib/core/services/user_scope_operation_gate.dart` | Same lease discipline as `WorkoutRepositoryImpl` for DAO writes |
| Session identity (`UserEntity.id` is a `String`, parsed to `int` at scope boundaries) | `session_provider.dart`, `user_scope_teardown_provider.dart:22,54` | Checkpoint `user_id INTEGER` |
| Track tab index | `lib/presentation/features/home/screens/home_screen.dart:15` (`tabIndexProvider`, Track is index 0) | Notification body tap |
| Post-completion ad gate takes `LiveWorkoutFinalizationResult` | `track_screen.dart:1113-1184`, IP-1.7 | Engine returns the same result type |
| Injected `LiveTrackingService` in `LiveTrackingRepositoryImpl` | `lib/data/repositories/live_tracking_repository_impl.dart:11-15` | Test seam for a fake position source |

### 2.3 What geolocator's own foreground mode does (plugin source, `geolocator_android-5.0.3`)

- `GeolocatorLocationService` is **bound** by the plugin at engine attach (`GeolocatorPlugin.java:147-158`, `bindService … BIND_AUTO_CREATE`), never `startService`d; `onStartCommand` returns `START_STICKY` but the service lives and dies with the plugin binding, i.e. with the FlutterEngine.
- Position updates reach Dart **only** through the `EventChannel` sink (`GeolocatorLocationService.startLocationService`, `StreamHandlerImpl.onListen:91-141`). No engine ⇒ no consumer.
- The notification (`BackgroundNotification.java`) has **no action buttons**; content intent is the package launch intent; the channel is created with `IMPORTANCE_NONE`; `PRIORITY_HIGH` on the builder; `startForeground(id, notification)` without an explicit type (relies on the manifest attribute); options change only on a new `onListen` — so it cannot show elapsed time or Paused/Active state.
- In the non-foreground path (what the app uses today) the fused client is created with the **application context**; the `Activity` is used only for the settings-resolution dialog (`FusedLocationClient.java:226-257`). Position updates therefore continue while the Activity is gone as long as the engine and its sink are alive.

### 2.4 Platform facts that drive the design (documentation; §12 for sources)

1. **Foreground location includes a running foreground service.** "Your app is running a foreground service … Your app retains access when it's placed in the background, such as when the user presses the Home button on their device or turns their device's display off." A `location`-type FGS gives the whole process foreground-location capability, so geolocator's fused client in the same process keeps receiving fixes with the screen off. `ACCESS_BACKGROUND_LOCATION` is defined for access "in any situation other than" those (§7.7).
2. **API 34+**: an FGS must declare a type; type `location` needs `FOREGROUND_SERVICE_LOCATION` plus a granted runtime location permission at `startForeground`, else `SecurityException`. Starting an FGS from the background is restricted (12+); starting from a visible Activity is always allowed.
3. **API 33+ `POST_NOTIFICATIONS`**: "Apps don't need to request the POST_NOTIFICATIONS permission in order to launch a foreground service." If denied, "they still see notices related to foreground services in the Task Manager but don't see them in the notification drawer."
4. **Task Manager "Stop" (13+)**: "The system removes your app from memory … removes the app's activity back stack … The system doesn't send the app any callbacks." Scheduled jobs/alarms are preserved; the app is not put in the force-stopped state.
5. **Android 12+**: `PendingIntent` mutability must be explicit (`FLAG_IMMUTABLE` for our static intents); notification trampolines are blocked (an Activity may be started only from the notification's own content `PendingIntent`, not from a receiver/service the tap triggered); FGS notifications on low-importance channels may be delayed up to 10 s **unless** the notification has action buttons or opts in with `FOREGROUND_SERVICE_IMMEDIATE`.
6. **Android 16 (API 36)** adds no foreground-service, location, or notification behavior change beyond the 14/15 rules (behavior-changes page; the FGS-relevant entries are the health type and opt-in intent-matching enforcement, neither used here).
7. **Flutter embedding (verified in `flutter_embedding_release` bytecode for Flutter 3.44.1):** `FlutterFragmentActivity.getCachedEngineId()` reads the `cached_engine_id` intent extra by default and is overridable; with a cached engine the fragment is built with `destroyEngineWithFragment(shouldDestroyEngineWithHost())`, whose default is the `destroy_engine_with_activity` extra (**false**), so the engine survives Activity destruction while the process lives. `configureFlutterEngine` skips `GeneratedPluginRegistrant` for injected engines; the `FlutterEngine(context)` constructor registers generated plugins itself. A `NewEngineFragmentBuilder` (the non-cached path, and the `provideFlutterEngine` path on `FlutterFragmentActivity`) sets `destroy_engine_with_fragment=true`, so **the cached-engine-ID path is the one that keeps the engine alive**.
8. Consequence of 7 for today's app: swiping the app away from Recents (task removed) destroys `MainActivity` and, today, its engine — the Dart isolate, timers, GPS stream, and any in-memory workout die. A foreground service alone would keep the *process* alive while nothing tracks; the notification would lie. Any correct design must keep the tracking isolate alive for as long as the notification exists (§4.3), or move tracking into an isolate the service owns (§6, option B).

---

## 3. Recommendation

Keep **one Dart isolate** as the sole owner of the workout state machine, the GPS subscription
(geolocator, plain `getPositionStream`), the acceptance policy, and SQLite checkpoints. Add a
**small app-local Kotlin layer (~250 lines)**:

- a *started* foreground service of type `location` that owns only the ongoing notification, its
  action buttons, and a partial wake lock while tracking is active;
- a non-exported broadcast receiver that forwards Pause / Resume / Finish to Dart;
- `MainActivity` changes that keep the FlutterEngine cached (alive) while that service runs, and
  forward the notification body tap.

Notification content is rendered **from durable state after each transition commits**. Actions are
applied by a container-level `ActiveWorkoutEngine` object (isolate lifetime, not the UI
`StateNotifier`) and are idempotent against the checkpoint row. Pause keeps the foreground service
but stops GPS and the wake lock, so Resume never needs a background FGS start. No
`ACCESS_BACKGROUND_LOCATION`, no new dependencies, no paid services, no second isolate, no
Kotlin access to SQLite.

---

## 4. Architecture (deliverable A)

### 4.1 Diagram

```text
┌───────────────────────────────── Android process (one) ─────────────────────────────────┐
│                                                                                           │
│  Kotlin — app module, ~250 lines                 Dart — single isolate on a cached engine │
│  ─────────────────────────────────               ───────────────────────────────────────── │
│  MainActivity : FlutterFragmentActivity          main()                                    │
│   • before super.onCreate: get-or-create          ├─ WorkoutServiceChannel                 │
│     FlutterEngine "main" (+ WorkoutServicePlugin) │    (platform boundary, §5.4)           │
│     and put it in FlutterEngineCache              │    Dart→Kt: start/update/stop/…        │
│   • getCachedEngineId() = "main"                  │    Kt→Dart: onNotificationAction,      │
│   • onDestroy: destroy+uncache engine ONLY if     │             onServiceEvent, onOpenWorkout│
│     WorkoutTrackingService is not running         │                                        │
│   • onCreate/onNewIntent: EXTRA_OPEN_WORKOUT ──┐  ├─ ActiveWorkoutEngine  (root Provider,   │
│                                                │  │   isolate lifetime — NOT a UI notifier) │
│  WorkoutServicePlugin (MethodChannel) ◄────────┼──┤   • state machine over WorkoutTimeline  │
│   "…/workout_service"; static `current`        │  │   • GpsPointAcceptancePolicy           │
│                                                │  │   • per-point durable write + 5 s heartbeat│
│  WorkoutNotificationActionReceiver ────────────┼─►│   • single-flight operation queue        │
│   (manifest, exported=false)                   │  │   • derives the notification model       │
│        ▲ PendingIntent.getBroadcast(IMMUTABLE) │  │                                        │
│        │                                       └─►│   • onOpenWorkout → tab 0 if allowed    │
│  WorkoutTrackingService (started FGS,             │                                        │
│   foregroundServiceType=location, NOT_STICKY)     ├─ ActiveWorkoutCheckpointDao (SQLite v7) │
│   • ServiceCompat.startForeground(id, notif,      │   checkpoints / points / status events   │
│                       TYPE_LOCATION)             │   one txn per write; finalize = insert   │
│   • renders notification from the model           │   completed workout + delete checkpoint  │
│     (chronometer, distance, actions,              │                                        │
│      content intent → MainActivity)               ├─ LiveTrackingService (geolocator        │
│   • PARTIAL_WAKE_LOCK iff model.state==active      │   getPositionStream — unchanged)        │
│   • stopForeground(REMOVE) + stopSelf on stop      │                                        │
│                                                   ├─ LiveTrackingNotifier (thin adapter:    │
│  FusedLocationProvider (GMS) ── geolocator ────────┤   observes engine snapshots, forwards   │
│      EventChannel → Dart                          │   taps; no clock arithmetic of its own)  │
│                                                   └─ Track screen · recovery card · tabs    │
└───────────────────────────────────────────────────────────────────────────────────────────┘
Durable truth = SQLite. Process death removes the FGS and its notification with it.
Next launch: Kotlin reconcile (stop any zombie service) → user-scoped orphan checkpoint → recovery card.
```

### 4.2 Invariants

1. **Notification exists ⇒ `WorkoutTrackingService` is running ⇒ Dart started it in this
   process ⇒ `ActiveWorkoutEngine` exists in this isolate.** The engine is a root Riverpod
   `Provider` created in `main()`/`injection_container.dart`, never invalidated by teardown (the
   teardown only ever runs after the workout is finished or discarded, §7.6). Actions never touch
   `LiveTrackingNotifier` (R4).
2. **Notification content is derived only from committed durable state.** A failed transition
   leaves the notification unchanged, so it never claims a state that did not commit (R10, R12).
3. **No engine ⇒ no service.** The plugin stops the service on `onDetachedFromEngine`; the
   receiver, if it finds no engine, sends `ACTION_STOP`; Dart's first act at isolate start is
   `stopIfRunning()`. Process death removes both anyway.
4. **The FGS starts only from a visible screen** (Start, or Resume from the recovery card) and is
   **kept alive across Pause**, so Resume from the notification never has to start an FGS from
   the background (R5, R8).
5. **The service is `START_NOT_STICKY`.** The OS never restarts it without the user; recovery is
   user-driven on next launch (IP-3.3 policy 6).

### 4.3 Engine lifetime — cached FlutterEngine

Why: §2.4 items 7–8. Without it a swipe-from-Recents kills tracking while the FGS keeps running.

How (all in `MainActivity.kt`, ~30 lines):

- `onCreate`: `enableEdgeToEdge()`; `FlutterEngineCache.getInstance().get(ENGINE_ID) ?:
  FlutterEngine(applicationContext).also { it.plugins.add(WorkoutServicePlugin());
  it.dartExecutor.executeDartEntrypoint(DartEntrypoint.createDefault()); cache.put(ENGINE_ID, it) }`
  — **before** `super.onCreate(savedInstanceState)`, because `FlutterFragmentActivity` reads
  `getCachedEngineId()` while creating (or restoring) its `FlutterFragment`.
- `override fun getCachedEngineId() = ENGINE_ID`.
- `onDestroy`: after `super.onDestroy()`, if `WorkoutTrackingService.isRunning` is false,
  `cache.remove(ENGINE_ID)` and `engine.destroy()`. This preserves today's cold-start semantics
  whenever no workout is running; only during a workout does the Dart app survive Activity
  destruction (swipe-away, back on API < 31, low-memory Activity reclaim).
- `onNewIntent`/`onCreate`: read `EXTRA_OPEN_WORKOUT` and hand it to the plugin (§7.4).

Behavior consequences to accept (listed in §11): during a workout, reopening the app after a
swipe-away shows the same in-memory screen (fast, state intact); Flutter sends
`AppLifecycleState.detached` while no view is attached — Dart timers, streams and Riverpod keep
running; frames are simply not scheduled (`Timer.periodic` is used for elapsed time already, so
nothing depends on frames). Debug hot restart re-runs `main()` on the same engine while the
Kotlin service may still be running: invariant 3 (reconcile at isolate start) handles it and
doubles as a convenient manual test of recovery.

---

## 5. Manifest additions and Kotlin/Flutter responsibility split (deliverable B)

### 5.1 Manifest (`rythmrun_frontend_flutter/android/app/src/main/AndroidManifest.xml`)

```xml
<!-- Foreground workout tracking (IP-3.4). -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />            <!-- API 28+ -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />   <!-- API 34+, must match the service type -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />            <!-- API 33+, runtime -->
<uses-permission android:name="android.permission.WAKE_LOCK" />                     <!-- partial wake lock while active -->
<!-- Deliberately NOT declared: ACCESS_BACKGROUND_LOCATION, RECEIVE_BOOT_COMPLETED,
     REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, SCHEDULE_EXACT_ALARM/USE_EXACT_ALARM. -->

<application …>
    <service
        android:name=".tracking.WorkoutTrackingService"
        android:exported="false"
        android:foregroundServiceType="location"
        android:stopWithTask="false" />
    <receiver
        android:name=".tracking.WorkoutNotificationActionReceiver"
        android:exported="false" />   <!-- no intent-filter: only our explicit-component PendingIntents -->
</application>
```

- `MainActivity` keeps `android:launchMode="singleTop"` (needed for `onNewIntent`) and
  `taskAffinity=""` (Flutter template; the notification's launch intent still finds the
  existing task by root component, the same way the launcher icon does).
- `stopWithTask="false"` is the platform default for a started service; it is written out so the
  intent (service survives task removal) is visible.
- Gradle: `implementation "androidx.core:core-ktx:1.16.0"` (for `ServiceCompat.startForeground`,
  `NotificationCompat`, `PendingIntentCompat`); geolocator already brings `androidx.core 1.16.0`
  transitively, so no new resolution. One monochrome vector `res/drawable/ic_stat_workout.xml`
  (the launcher icon renders as a white square when used as `smallIcon` on API 21+).
- Nothing else in `build.gradle`; the ads placeholders and signing block stay untouched.

### 5.2 Kotlin components (outlines, not code)

`tracking/WorkoutTrackingService.kt` (~110 lines)

- `onCreate`: create channel `workout_tracking` (`IMPORTANCE_LOW`, `VISIBILITY_PUBLIC`,
  no sound/vibration).
- `onStartCommand(intent)`:
  - `ACTION_START` (extras = notification model, §7.4): build notification;
    `ServiceCompat.startForeground(this, NOTIFICATION_ID, notification,
    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)` inside `try`; on any exception
    (`SecurityException`, `ForegroundServiceStartNotAllowedException`) → report
    `startFailed(code)` through the plugin, `stopSelf()`. On success report `started`.
    Idempotent when already in foreground (just re-renders).
  - `ACTION_UPDATE`: re-render with `NotificationManagerCompat.notify(NOTIFICATION_ID, …)`;
    acquire the partial wake lock iff `model.state == active`, else release. If the service is
    not in foreground state (stale update racing a stop) → `stopSelf()`.
  - `ACTION_STOP`: release wake lock; `stopForeground(STOP_FOREGROUND_REMOVE)`; `stopSelf()`;
    report `stopped`.
  - returns `START_NOT_STICKY`.
- `onTaskRemoved`: no-op (service keeps running; the engine is cached).
- `onDestroy`: release wake lock; clear `isRunning`.
- Companion: `isRunning` (volatile), `start(context, model)` = `ContextCompat.startForegroundService`,
  `update(context, model)` / `stop(context)` = `context.startService` (legal: while an FGS runs
  the uid is active; when nothing runs, only `START` is ever sent, and only from a visible
  Activity).

`tracking/WorkoutNotificationActionReceiver.kt` (~20 lines)

- `onReceive`: `action ∈ {pause, resume, finish}` → `WorkoutServicePlugin.current?.dispatch(action)`;
  if `current == null` (no engine — should not happen while a notification exists) →
  `WorkoutTrackingService.stop(context)`. Never starts an Activity (12+ trampoline rule).

`tracking/WorkoutServicePlugin.kt` (~90 lines) — `FlutterPlugin`

- `MethodChannel("com.github.cosmicsaurabh.rythmrun/workout_service")`, handler on the main thread.
- Dart→Kotlin methods in §5.4; Kotlin→Dart `invokeMethod` for actions, service events, and the
  open-workout request.
- Static `current` set in `onAttachedToEngine`, cleared in `onDetachedFromEngine` (which also
  stops the service if running — invariant 3).
- `handleLaunchIntent(intent)` reads `EXTRA_OPEN_WORKOUT` (called from `MainActivity`).

`MainActivity.kt` — as in §4.3.

### 5.3 Dart components

| Component | Location | Role |
| --- | --- | --- |
| `WorkoutServiceChannel` | `lib/core/services/workout_service_channel.dart` | The platform boundary: typed wrappers over the `MethodChannel`; exposes `Stream<NotificationAction>`, `Stream<ServiceEvent>`, `Stream<void> openWorkoutRequests`; `NoopWorkoutServiceChannel` for tests and for PR-2a before Kotlin lands. Earns its file by isolating a real side-effect boundary. |
| `ActiveWorkoutEngine` | `lib/core/tracking/active_workout_engine.dart` (pure Dart, injected clock/DAO/location source/channel/gate) | State machine, timeline, acceptance, durable writes, notification model, single-flight ops; emits `ActiveWorkoutSnapshot`. |
| `ActiveWorkoutCheckpointDao` | `lib/core/services/active_workout_checkpoint_dao.dart` (takes the opened `Database` from `LocalDbService`) | Schema-owning DAO for the three v7 tables + `finalizeActiveWorkout` transaction. |
| `LiveTrackingNotifier` | existing file, slimmed | UI adapter: permission checks/messages, forwards Start/Pause/Resume/Finish/Discard/Retry to the engine, mirrors snapshots into `LiveTrackingState`. No independent session clock or pause arithmetic (IP-3.1 item 6). |
| Recovery card | existing `workout_recovery_card.dart` extended | Resume / Finish / Discard for the current user's orphan checkpoint. |
| Startup hooks | `main.dart` / `injection_container.dart` | `stopIfRunning()` at isolate start; orphan discovery after `activateUserScope(userId)`; `openWorkoutRequests` → `tabIndexProvider = 0` when allowed. |

### 5.4 Channel contract

| Direction | Method | Payload | Semantics |
| --- | --- | --- | --- |
| Dart→Kt | `start` | notification model | `startForegroundService`; returns `true` if the intent was accepted; the definitive outcome arrives as `onServiceEvent(started|startFailed)`. Dart waits ≤5 s then treats silence as failure. |
| Dart→Kt | `update` | notification model | Re-render + wake-lock by state. |
| Dart→Kt | `stop` | — | Stop foreground, remove notification, `stopSelf`. Idempotent. |
| Dart→Kt | `stopIfRunning` | — | Reconcile at isolate start (kills a zombie service). |
| Dart→Kt | `isRunning` | — | For teardown assertions and honest UI. |
| Dart→Kt | `notificationsEnabled` | — | `areNotificationsEnabled()` && channel importance ≠ `NONE` — for honest copy (R10). |
| Dart→Kt | `consumeLaunchIntent` | — | Returns `true` once if the Activity was (re)launched with `EXTRA_OPEN_WORKOUT`. |
| Kt→Dart | `onNotificationAction` | `{action: pause|resume|finish}` | Forwarded to `ActiveWorkoutEngine.applyAction`. |
| Kt→Dart | `onServiceEvent` | `{event: started|startFailed|stopped, code?}` | `startFailed` is fatal for a Start in progress (§7.2). |
| Kt→Dart | `onOpenWorkout` | — | Body tap while the engine is alive (`onNewIntent`). |

Notification model (the only thing Kotlin ever sees about a workout):

```text
{ state: active | paused | finishing | locationUnavailable,
  workoutType: running | walking | cycling | hiking,
  activeElapsedMs: int,            // chronometer base for `active`; static text otherwise
  distanceText: "3.2 km",          // formatted by Dart with the IP-1 formatter; no coordinates
  actions: [pause, finish] | [resume, finish] | [] }
```

### 5.5 Notification specification (R2, R3, R9, R12)

- Channel `workout_tracking`, `IMPORTANCE_LOW`, `VISIBILITY_PUBLIC` (content is type / elapsed /
  distance only, so lock-screen controls are acceptable and useful).
- Builder: `setSmallIcon(ic_stat_workout)`, `setContentTitle("RythmRun · Running")`,
  `setContentText("Tracking · 3.2 km")` with `setUsesChronometer(true).setWhen(now −
  activeElapsedMs).setShowWhen(true)` while active (the system renders the running timer, so no
  periodic Dart→Kotlin updates are needed); `"Paused · 3.2 km · 00:23:15"` while paused;
  `"Paused — location unavailable"` for `locationUnavailable`; `"Saving workout…"` with no
  actions for `finishing`. `setOngoing(true)`, `setOnlyAlertOnce(true)`,
  `setCategory(CATEGORY_WORKOUT)`, `setForegroundServiceBehavior(FOREGROUND_SERVICE_IMMEDIATE)`,
  `setSilent(true)`.
- Actions: `NotificationCompat.Action` per model action; `PendingIntent.getBroadcast(context,
  requestCode(action), Intent(context, WorkoutNotificationActionReceiver::class.java).setAction(
  ACTION_PREFIX + action), FLAG_IMMUTABLE or FLAG_UPDATE_CURRENT)`. Order: Pause/Resume, then
  Finish.
- Content intent: `PendingIntent.getActivity(context, RC_OPEN, Intent(context,
  MainActivity::class.java).apply { action = ACTION_MAIN; addCategory(CATEGORY_LAUNCHER);
  flags = FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_SINGLE_TOP; putExtra(EXTRA_OPEN_WORKOUT, true) },
  FLAG_IMMUTABLE or FLAG_UPDATE_CURRENT)`. Existing task → `onNewIntent`; destroyed Activity →
  new instance attaching to the cached engine; process dead → cold start (recovery card).
- Distance text refreshes on transitions and at most every ~15 s while active (piggybacking on
  durable writes); the elapsed time never needs an update thanks to the chronometer.

---

## 6. Extend geolocator vs. small dependency vs. own native layer (deliverable C)

| Option | What it gives | Complexity | Maintenance risk | Cost | Verdict |
| --- | --- | --- | --- | --- | --- |
| **A. geolocator `AndroidSettings.foregroundNotificationConfig`** (already a dependency; the [GPS audit §6.1](./gps-tracking-audit.md) proposal) | Background continuity + a plain notification + wake lock | Lowest to switch on. But (§2.3): **no action buttons, no elapsed/paused text, no state-driven content, no chronometer**; the service is bound to the engine and cannot outlive it; it still needs our manifest permissions **and** the cached engine of §4.3 to survive swipe-away. Adding our own second notification for controls means two notifications; overwriting geolocator's notification ID/channel from our code couples us to plugin internals. Forking to add actions means re-applying a patch on every plugin release. | Baseflow is well maintained; a fork is not | Free | **Insufficient for R3.** Fine as the position source, which stays. It is the correct choice only if notification controls are dropped from scope. |
| **B. `flutter_foreground_task` 10.0.0** (or `flutter_background_service`) | FGS with type config, notification buttons and `onNotificationButtonPressed`/`onNotificationPressed`, wake lock, `POST_NOTIFICATIONS` helper; the tracking loop would run in a **second Dart isolate** owned by the service, so actions never depend on the UI engine | Medium–high: two engines/isolates; every snapshot crosses `sendDataToMain/sendDataToTask`; sqflite from two isolates means two connections to one file (busy/lock handling); plugin registration in the task isolate; its manifest merges `RECEIVE_BOOT_COMPLETED` plus an **exported** boot/`MY_PACKAGE_REPLACED` receiver and auto-restart options that we must remove with `tools:node="remove"` to honor "no auto-resume". `flutter_background_service_android` also exports its service. 2,635 lines of Kotlin we do not control. | Single-maintainer package, major-version churn (6→10 in about two years) | Free | Viable fallback if option C fails the device matrix; not the smallest. It solves the engine-lifetime problem by adding an engine; C solves it by caching the one we have. |
| **C. Own minimal native layer** (this design) | Exactly R2–R5 and R9–R12; keeps "one authoritative GPS subscription feeds engine, metrics, persistence, and map" (IP-3 exit gate); Kotlin never touches SQLite or coordinates | ~250 lines Kotlin (service ~110, receiver ~20, plugin ~90, `MainActivity` ~30) + `WorkoutServiceChannel` ~80 lines Dart | Ours; built on stable platform APIs (`ServiceCompat`, `NotificationCompat`, `FlutterEngineCache`) that the app already depends on transitively | Free; no new pub package | **Recommended.** |

Departure from the GPS audit, stated plainly: the audit's §6.1 chose geolocator's built-in
notification because it audited against continuity only. This design's R3 (Pause/Resume/Finish
from the shade with no screen open) makes that insufficient, and both approaches need the cached
engine anyway. Everything else in the audit's §6 (checkpoint tables, per-point synchronous
write, finalize-from-checkpoint in one transaction, recovery card, no ABL, wall clock, SYNC-01
first) is adopted here unchanged.

---

## 7. Durable state model (deliverable D)

### 7.1 Schema — SQLite v7 (one additive migration; forward-only)

`LocalDbService._databaseVersion` 6 → 7. `openDatabase` sets no `onDowngrade`, so an older
binary cannot open a v7 file; that matches the IP-3 rollback rule (never ship a lower-version
binary against an upgraded database).

```sql
CREATE TABLE active_workout_checkpoints (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,                 -- one non-terminal checkpoint per user
  client_sync_id TEXT NOT NULL,             -- reused verbatim by the completed row
  type TEXT NOT NULL,                       -- WorkoutType.name
  state TEXT NOT NULL CHECK (state IN ('starting','active','paused','finishing')),
  started_at TEXT NOT NULL,                 -- WorkoutTimeline.startedAt (UTC ISO-8601)
  last_transition_at TEXT NOT NULL,         -- WorkoutTimeline.lastTransitionAt
  pause_started_at TEXT,                    -- WorkoutTimeline.openPauseStartedAt; non-null iff paused
  closed_paused_ms INTEGER NOT NULL DEFAULT 0,
  total_distance_m REAL NOT NULL DEFAULT 0,
  max_speed_mps REAL NOT NULL DEFAULT 0,
  last_point_sequence INTEGER NOT NULL DEFAULT 0,
  last_event_sequence INTEGER NOT NULL DEFAULT 0,
  last_accepted_point_at TEXT,
  metrics_version INTEGER NOT NULL DEFAULT 2,
  checkpoint_schema_version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_flushed_at TEXT NOT NULL             -- liveness heartbeat; recovery boundary (§7.5)
);
CREATE UNIQUE INDEX idx_active_checkpoints_user ON active_workout_checkpoints(user_id);
CREATE UNIQUE INDEX idx_active_checkpoints_user_client_sync_id
  ON active_workout_checkpoints(user_id, client_sync_id);

CREATE TABLE active_tracking_points (
  checkpoint_id INTEGER NOT NULL REFERENCES active_workout_checkpoints(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL,
  latitude REAL NOT NULL, longitude REAL NOT NULL,
  altitude REAL, accuracy REAL, speed REAL, heading REAL,
  timestamp TEXT NOT NULL,
  PRIMARY KEY (checkpoint_id, sequence)
);
CREATE TABLE active_status_events (
  checkpoint_id INTEGER NOT NULL REFERENCES active_workout_checkpoints(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active','paused','interrupted')),
  timestamp TEXT NOT NULL,
  PRIMARY KEY (checkpoint_id, sequence)
);
-- Same migration (IP-3.1 item 8): ALTER TABLE tracking_points ADD COLUMN sequence INTEGER;
-- ALTER TABLE status_changes ADD COLUMN sequence INTEGER; deterministic backfill ordered by
-- (timestamp, id) per workout; UNIQUE(workout_id, sequence) indexes on both.
```

Rules:

- Only accepted points are stored (rejected raw samples are never route data).
- `UNIQUE(user_id)` is the "exactly one active checkpoint per user" guard: terminal states
  (`completed`, `discarded`) are deletions, so the table only ever holds non-terminal rows and a
  second concurrent Start fails on the index and is reported as *already active*.
- `recoverable` is **derived, not stored**: at isolate start no in-memory engine session can own
  a checkpoint, so any row for the current user is an orphan (§7.5).
- Every DAO method takes `userId` and predicates on it; `LocalDbService._onOpen` verification is
  extended to the new indexes; `clearUserDataFromLocalDatabase(userId)` also deletes
  `active_workout_checkpoints WHERE user_id = ?` (children cascade); the migration ends with
  `foreign_key_check` like v6.
- Timestamps are written as UTC ISO-8601 (as `ActivitySyncModel` already does); this avoids
  the DST issue the GPS audit lists as F13 for the new tables.

### 7.2 State machine and transitions

```text
none ─start─► starting ─(location + service up)─► active ◄─resume── paused
                 │                                   │  ▲          │
                 │ (any failure: delete)             │  └──pause───┘
                 ▼                                   │
              deleted                    finish ─────┴───────────► finishing ─► completed (row moved)
                                                                       │
recovered orphan (any of starting/active/paused/finishing) ── discard ─► deleted (explicit confirm)
```

| Op | Durable write (all inside the engine's single-flight queue) | Then |
| --- | --- | --- |
| **Start** (visible tap) | precheck location permission (existing flow) → **`INSERT` checkpoint `starting`** with `user_id`, `client_sync_id`, `started_at` (R1: durable before GPS) | `channel.start(model)` → await `started` (≤5 s) → `startTracking()` (geolocator) → `UPDATE state='active'` + event `active@started_at`. Any failure (unique violation excepted): `channel.stop()`, `DELETE` the checkpoint in an explicit failed-start transaction, honest error ("Couldn't start background tracking; the workout was not started"). Unique-index violation ⇒ *already active*; nothing deleted. |
| **Point accepted** | one transaction: `INSERT OR IGNORE` point with `sequence = last_point_sequence + 1`, `UPDATE` aggregates, `last_point_sequence`, `last_accepted_point_at`, `updated_at`, `last_flushed_at` | Retry after an error re-issues the same row (sequence uniqueness ⇒ idempotent). Distance text pushed to the notification at most every ~15 s. |
| **Heartbeat** (5-s timer while `active`) | if no point was written in the last 5 s: `UPDATE last_flushed_at` | Bounds unknown downtime to ≤5 s (§7.5). |
| **Pause** | `UPDATE state='paused', pause_started_at, last_transition_at` + event `paused` | `stopTracking()` (GPS off), `channel.update(paused)` → notification "Paused", **service kept**, wake lock released. |
| **Resume** | `UPDATE state='active', closed_paused_ms += now − pause_started_at, pause_started_at = NULL, last_transition_at` + event `active` | `startTracking()` (legal in the background because the location FGS still runs); the acceptance policy's `activeDistanceAnchor` is reset so the first accepted point adds 0 m; `channel.update(active)`. |
| **Finish** | close an open pause at `end` → `UPDATE state='finishing'` → recompute metrics from durable points/events (IP-1 unit contract; `interrupted` events map to `paused` boundaries) → **one transaction**: insert `workouts` + `tracking_points` (with sequences) + `status_changes`, then `DELETE` the checkpoint | `channel.stop()`; existing `syncWorkouts()` trigger only after commit; returns `LiveWorkoutFinalizationResult.saved(localId)`. If a `workouts` row with the same `(user_id, client_sync_id)` already exists (crash after commit): verify type/start match, delete only the owned checkpoint, report saved. Repeated Finish is a no-op result. Headless finish shows no ad (the IP-1.7 gate is invoked only from the Track screen). |
| **Discard** | explicit confirmation → `DELETE` the owned checkpoint (`WHERE id=? AND user_id=?`) | `stopTracking()`, `channel.stop()`. Cannot touch `workouts`. |
| **Fatal location error** (services turned off, permission lost, stream error) | `UPDATE state='paused'` + event `interrupted` | `channel.update(locationUnavailable)` → "Paused — location unavailable" [Resume][Finish]; service kept; Track screen shows the same truth. (Note: revoking a runtime permission force-stops the app on Android; that case lands in §7.5.) |
| **Teardown** (D-011) | voluntary logout/switch with an active or orphan checkpoint ⇒ decision required (Finish or Discard) exactly as today; forced loss ⇒ engine `finish()` | service stopped in both paths before `invalidateUserState` runs. |

Idempotency and concurrency: every operation runs through one queue (the pattern of today's
`_startFuture`/`_stopFuture`) and re-reads `state` inside its transaction, so a duplicate
Pause/Resume/Finish from UI + notification, or a double tap, becomes a no-op result. Kotlin needs
no de-duplication and holds no state beyond "is the service running".

### 7.3 Point flushing and loss bound

The IP-3 objective ("checkpoint at least every five points or five seconds") is met with the
smallest possible implementation: **write each accepted point synchronously** in its own
transaction plus the 5-s heartbeat. At the plugin's default 5-s fused interval and the 5-m
distance filter this is at most one small transaction every few seconds — the same choice the GPS
audit makes in §6.2. Loss on kill: the one point in flight and ≤5 s of active time. If the device
matrix shows write cost mattering, the engine can buffer ≤5 points behind the same DAO call
without changing the schema; that is the only tightening lever needed.

### 7.4 Notification model derivation and action handling (R3, R4)

- After every committed transition the engine derives the model in §5.4 from the durable row
  (never from UI state) and calls `channel.update`. Distance is formatted with the IP-1
  formatter; the elapsed base is `activeDuration` at commit time.
- Action path: tap → `PendingIntent.getBroadcast` → `WorkoutNotificationActionReceiver` →
  `WorkoutServicePlugin.dispatch(action)` → Dart `onNotificationAction` →
  `ActiveWorkoutEngine.applyAction(action)` → transition per §7.2 → derived model →
  `channel.update`. If the operation fails or is a no-op, the notification is left as it was.
- Actions are not persisted as an event log: they are applied synchronously to durable state; if
  the process dies before an action is applied, the workout is exactly as durable as it was (and
  tracking has stopped anyway), so the next launch offers recovery. This is documented behavior,
  not a gap.
- Body tap: `EXTRA_OPEN_WORKOUT` → Dart `openWorkoutRequests`. `main.dart` acts only if the
  session is authenticated **and** this user has a live engine session or an orphan checkpoint:
  pop to root and set `tabIndexProvider = 0`. Otherwise it is ignored (login flow shows as
  usual). The tap never chooses *which* workout; it navigates to a user-scoped screen (R7).
- Optional (decision in §11): a two-tap Finish inside the notification ("Finish? [Confirm]
  [Cancel]", auto-reverts after 10 s, transient Dart-side state, no durable write) to guard against
  accidental taps. Not required by R3; recommended off for the first release, on if the maintainer
  wants it.

### 7.5 Recovery on next launch (R6, R11)

Order at isolate start (`main()`), then again whenever `activateUserScope(userId)` runs:

1. `channel.stopIfRunning()` — a service without an engine session is a zombie (hot restart,
   or an exotic engine death); remove it before anything can claim tracking.
2. After DB open and session identity: `dao.findCheckpoint(userId)`. Rows of any other user are
   never queried (R7).
3. Reconcile deterministically (each step idempotent):
   - `active` → append event `interrupted @ last_flushed_at`; `UPDATE state='paused',
     pause_started_at = last_flushed_at` (guarded `WHERE state='active'`). Unknown downtime is
     therefore excluded from active duration; the pause stays open until Resume or Finish.
   - `paused` → nothing; the pause remains open.
   - `starting` → recoverable-start: offer Resume or Discard only (a zero-data completed workout
     is never created).
   - `finishing` → if a completed row with the same `(user_id, client_sync_id)` exists and
     matches, delete only the owned checkpoint (finish was complete); otherwise offer Retry
     Finish or Discard, never Resume into a second route.
   - validation failure (unreadable row) → preserve it, show a safe recovery error with a stable
     code, never delete automatically.
4. Recovery card offers exactly Resume / Finish / Discard for the current user. **Resume** starts
   the FGS from the visible screen, restarts GPS, appends `active`, and anchors the first accepted
   point at zero distance. **Finish** completes at the last durable boundary. **Discard** is a
   destructive confirmation.
5. Never auto-resume location after reboot, kill, or login without a user action and a visible
   notification (IP-3.3 policy 6). `START_NOT_STICKY` guarantees the OS cannot do it for us.

Task Manager **Stop** (Android 13+, R11): no callback; the checkpoint is at most ~5 s stale;
the next launch runs the steps above and shows an interrupted-and-paused workout. Force-stop,
runtime-permission revocation (which force-stops the app), reboot, and OEM kills all take the
same path. Optionally log `ApplicationExitInfo.REASON_USER_REQUESTED` as a privacy-safe count.

### 7.6 Account switching and logout (R7)

- Checkpoint rows are keyed by `user_id`; every DAO read and mutation is user-scoped, mirroring
  `workouts`.
- `DefaultUserScopeTeardown._hasActiveWorkout()` is extended to include an orphan checkpoint for
  the exiting user, so a voluntary logout or account switch still requires Finish or Discard
  (D-011); forced authentication loss finishes locally as today. In both cases
  `channel.stop()` runs before `invalidateUserState`; `clearUserDataFromLocalDatabase(userId)`
  deletes any remaining checkpoint of that user as a backstop.
- User B's recovery query (`WHERE user_id = B`) cannot see A's row; the notification never exists
  across a user boundary because the service is stopped in the teardown path; a notification
  action arriving mid-teardown hits an engine that is finishing and is a no-op.
- `SYNC-01` (teardown deletes unsynced workouts) is unchanged by this design; a headless Finish
  followed by forced auth loss still hits it. It stays the P0 it already is and must land before
  or with IP-3.2 (GPS audit §6.7).

### 7.7 Permissions

**Why no `ACCESS_BACKGROUND_LOCATION` (R8).** Android's own definition of *foreground*
location includes "your app is running a foreground service … your app retains access when it's
placed in the background … or turns the display off" (§2.4 item 1). Concretely:

1. The FGS is started only while an Activity is visible (Start, or Resume from the recovery
   card) — the case Android 12+ always permits — and a running `location` FGS grants the process
   foreground-location capability, so geolocator's fused client keeps delivering with the screen
   off.
2. Pause keeps the FGS alive, so a Resume from the notification never needs to start an FGS from
   the background (where Android 14/15 would withhold while-in-use location).
3. Nothing in scope needs location without a user action: no auto-restart after kill/reboot
   (IP-3.3 policy 6), no geofencing, no scheduled tracking. Those are the only cases ABL exists
   for.
4. Not requesting ABL keeps the app out of Play's mandatory background-location declaration and
   review; the FGS use is "a continuation of an in-app, user-initiated action" and is "terminated
   immediately after the application completes the intended use case" (Finish/Discard/teardown),
   which is the Play condition for FGS location.

It would be insufficient only if we wanted `START_STICKY` auto-resume after process death, which
is deliberately out of scope. If an OEM kills the service anyway, the answer is the recovery UX,
not ABL.

**`POST_NOTIFICATIONS` (R10).** Request at the first Start on API 33+ with a one-line rationale
("Show Pause/Finish controls in your notifications; tracking works either way"), using the
already-declared `permission_handler` (`Permission.notification`) or a 15-line Kotlin request —
maintainer choice (§11). If denied or the channel is later muted: the workout **still starts**
(the FGS does not need the permission); the Track screen shows once per workout: "Notifications
are off, so Pause/Finish won't appear in your notification shade; tracking still continues in
the background." Kotlin's `notificationsEnabled` keeps that copy truthful; no UI text ever tells
the user to use a control that cannot be shown. `openAppSettings()` is offered as a link, not a
gate.

**Approximate location (Android 12+).** A coarse-only grant still satisfies the FGS
prerequisite but degrades tracking; this is a pre-existing gap (the app treats `whileInUse` as
sufficient) and is surfaced, not fixed, here.

### 7.8 Privacy (R12)

- The notification model carries type, state, elapsed, formatted distance, and actions — never
  coordinates, timestamps of fixes, or route shape.
- Kotlin logs at most action names, service events, and stable failure codes. Dart logs stable
  codes and counts (existing IP-1.2 discipline: no coordinates on any release path).
- The tables live in the same app-private SQLite file; the IP-2.7 at-rest design covers them
  when it lands.

---

## 8. Implementation sequence — small PRs, each leaves a coherent app (deliverable E)

| PR | Package | Content | Behavior change | Verification |
| --- | --- | --- | --- | --- |
| **PR-0** | IP-3.4 item 1 | Toolchain proof, **no code**: debug and release configuration/build on Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20; record the result in the IP-3 evidence log (budget disk — a prior attempt exhausted the host). Land GPS-audit F9 (debug text) if convenient. | None | Build logs |
| **PR-1** | IP-3.1 | SQLite v7: three checkpoint tables + indexes, completed `sequence` columns with deterministic backfill, `_onOpen` verification, `clearUserDataFromLocalDatabase` deletes checkpoints; `ActiveWorkoutCheckpointDao` (create/find/update/point/event/finalize/delete). Nothing calls it from production yet. | None visible; schema bump | FFI migration tests v1–v6 (+hybrid) → v7, `foreign_key_check`, unique-index behavior, backfill exactly once |
| **PR-2a** | IP-3.1 | `ActiveWorkoutEngine` extracted from the notifier (injected clock, DAO, location source, `NoopWorkoutServiceChannel`, gate); durable start/pause/resume; per-point write + heartbeat; snapshots; notifier becomes an adapter; map/track keep reading the provider. | Workouts are checkpointed. Background continuity unchanged (still stops) — honest because nothing claims otherwise yet. | Engine unit tests with fakes; provider tests updated; full `flutter test` |
| **PR-2b** | IP-3.2 | Finalize-exactly-once (`finalizeActiveWorkout` transaction sharing a private insert with `saveWorkoutInLocalDatabase`), `finishing` reconciliation, discard, sync-after-commit. | Finish is durable across kills | Failure-injection via a wrapping `DatabaseFactory` (IP-3.2 list) |
| **PR-3** | IP-3.3 | Startup reconcile hook after `activateUserScope`, orphan policy, recovery card Resume/Finish/Discard, teardown `_hasActiveWorkout()` includes orphan, honest error for corrupt rows. | Recovery UI appears after kills | Kill/reopen matrix (IP-3.3 list); teardown tests |
| **PR-4a** | IP-3.4 | Manifest (§5.1), `WorkoutTrackingService`, `WorkoutServicePlugin`, `WorkoutServiceChannel`, `MainActivity` cached engine + conditional destroy, `core-ktx`, small icon, `POST_NOTIFICATIONS` request + honest copy, engine wiring (start/update/stop, `startFailed` handling), zombie reconcile, wake lock while active. Notification without action buttons yet. | Background/screen-off tracking with an honest notification | Dart channel/engine tests with a fake channel; device smoke: `dumpsys activity services` shows `foregroundServiceType=location`; screen-off run |
| **PR-4b** | IP-3.4 | Receiver + action `PendingIntent`s, `onNotificationAction`, chronometer/paused rendering, body tap → `onOpenWorkout` → tab 0; optional two-tap Finish. | Notification controls | Engine idempotency tests; device: actions with the app backgrounded, destroyed (swiped), and cold |
| **PR-5** | IP-3.4 evidence | `integration_test/` + `tool/device_test/` scripts (install, synthetic route hook behind a `--dart-define`, `am force-stop`, `input keyevent KEYCODE_SLEEP`, `dumpsys activity services`, `dumpsys notification`, `logcat` scan for coordinates); fill the IP-3 evidence log; STATUS; new `MC-3.x` items in ACTION-REQUIRED (Play Console FGS declaration, privacy-policy fact, device matrix). | None | The physical-device matrix (§9) |

IP-3.5 (long-session UI cost) follows and is unaffected by this design except that the engine
already keeps full-fidelity points in SQLite rather than in every state emission.

---

## 9. Tests (deliverable F)

**Unit / FFI (all in `flutter test`, no device):**

- DAO: upgrades from every supported version preserve completed workouts and create empty
  checkpoint tables; `foreign_key_check` clean; `UNIQUE(user_id)` rejects a second Start (two
  concurrent Starts ⇒ one checkpoint + one *already active*); `UNIQUE(checkpoint_id, sequence)`
  makes a re-issued point/event a no-op; sequence backfill deterministic and applied once;
  user-scoped reads hide other users' rows; teardown clearing deletes the user's checkpoint and
  cascades children.
- Engine (fake clock, fake position stream, FFI DAO, fake channel): checkpoint exists before the
  first point; per-point write and heartbeat cadence; retry after an injected error yields no
  duplicate sequence; pause/resume durable with zero points; resume anchor adds 0 m (existing
  IP-1.2 semantics preserved); pause stops the stream and sends `update(paused)` without
  `stop()`; fatal location error ⇒ durable auto-pause + `locationUnavailable` model; the model
  is derived only after commit and unchanged after a failed op; duplicate/late actions are
  no-ops; an action delivered with no `LiveTrackingNotifier` alive still commits; `startFailed`
  and stream-start failure delete the checkpoint and stop the service; account change aborts
  writes instead of relabeling; wall-clock ±5 min jump mid-workout (GPS audit F8).
- Finalization: injected failure before the point write, after it but before `finishing`, during
  the completed insert, after commit before acknowledgement — each leaves one checkpoint or one
  completed row; seeded completed-row-plus-checkpoint reconciles only on matching owner/identity;
  repeated Finish idempotent; sync starts only after commit.
- Recovery: kill/reopen after start, points, pause, resume, finishing; `starting` cannot yield a
  zero-data workout; interruption excludes downtime; paused stays open; account B cannot see or
  act on A's checkpoint; corrupt row preserved with an error; zombie service stopped at start.
- Widgets: recovery card actions; Track screen honest copy for notifications denied / service
  failed; `openWorkoutRequests` sets tab 0 only when authenticated with a session or orphan.
- Kotlin stays thin on purpose; no Robolectric (it would add a new test-dependency chain to a
  repository that deliberately minimizes dependencies). It is verified on device.

**Physical device (`integration_test` + `tool/device_test/`; emulator-only evidence is
insufficient per IP-3.4):**

| Scenario | Expected |
| --- | --- |
| Screen locked ≥30 min; one multi-hour session | Notification visible; points and heartbeats continue; no gap in the route beyond the acceptance policy's own rules |
| Swipe from Recents during active | Engine survives; notification and tracking continue; reopen shows the same workout |
| Task Manager Stop; `am force-stop`; reboot; runtime location permission revoked mid-workout | No auto-restart; next launch offers Resume/Finish/Discard with the interruption at the last heartbeat |
| Battery saver; Samsung "sleeping apps"; Do Not Disturb | Documented outcome per device; any kill lands in recovery, never a silent lie |
| Airplane mode + reconnect | Local recording uninterrupted; sync stays queued |
| Notifications denied; channel muted | Workout starts; honest copy; FGS visible in Task Manager only |
| Location services toggled off, then on | Auto-pause with `interrupted`; Resume works without reopening the app |
| Lock-screen actions; rapid double taps; Pause then Resume within a second; Finish while the app is backgrounded, while destroyed, and then immediately swiped away | Idempotent single transitions; one completed row |
| Cold start via notification tap; tap after logout (should not exist) | Track tab shown only when allowed |
| Debug hot restart during a workout | Zombie service stopped; recovery card shown |
| Oldest supported API (24–28) | `startService`/no type/no `POST_NOTIFICATIONS` paths behave; `ServiceCompat` handles the differences |
| `logcat` scan and `dumpsys notification` | No coordinates/timestamps of fixes; `foregroundServiceType=location` in `dumpsys activity services` |

Matrix per IP-3.4: one stock/near-stock device, one Samsung with background restrictions, one
older supported API level; record device/OS/plugin versions in the evidence log.

---

## 10. Risks, rollback, Play policy (deliverable G)

**Risks and mitigations**

| Risk | Mitigation |
| --- | --- |
| Cached engine changes app-state semantics | Only while a workout runs; conditional destroy restores cold-start behavior otherwise (§4.3). Debug hot restart handled by reconcile. |
| OEM kills the FGS regardless (Samsung sleeping apps) | Recovery UX; `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is deliberately **not** requested (Play-restricted; not needed for a user-visible workout) |
| Wake lock battery cost | Held only while `active`; released on pause/finish/destroy; measured on the matrix |
| `startForeground` fails at Start (restricted background setting, missing runtime grant) | Fail closed: checkpoint deleted, honest error, no workout — never a "tracking" state without a service |
| Approximate-location grant | Pre-existing gap; surfaced |
| Wall-clock jumps still count as active time | Existing `WorkoutTimeline` semantics; monotonic clock would be an IP-1 change (GPS audit F8) |
| `SYNC-01` still deletes unsynced work at teardown | Unchanged; must land with or before PR-2b |
| Notification "Finish" tapped by accident | Rightmost action; optional two-tap confirm (§7.4, decision) |
| Two-writer SQLite (Kotlin + Dart) | Avoided by design: Kotlin never opens the database |
| Play review of the FGS video | The flow is a continuation of a user action and stops at Finish/Discard/teardown by construction |

**Rollback**

- Database is forward-only (additive v7); do not ship a lower-version binary against it.
- PR-4a/4b revert independently: without the FGS the durable engine still checkpoints and
  recovers, and nothing claims background tracking. PR-2/3 revert only by rebuilding the previous
  behavior on the same schema (IP-3 rollback plan).
- No runtime kill switch is proposed. It would add configuration surface, and IP-3 forbids
  falling back to memory-only tracking without explicit maintainer acceptance; if the maintainer
  wants one, it must **block Start with a message** rather than track without a service.
- The engine's `NoopWorkoutServiceChannel` exists for tests and for the PR-2a window only, not as
  a production toggle.

**Play / policy items (maintainer actions; to become `MC-3.x` in ACTION-REQUIRED)**

1. Play Console → App content → **Foreground service permissions**: declare the `location`
   type with a description ("continuous GPS recording of a workout the user explicitly started;
   the persistent notification shows elapsed time/distance and Pause/Finish controls") and the
   required demo video.
2. Location policy stance to keep in the store listing/declaration: no `ACCESS_BACKGROUND_LOCATION`;
   FGS as a continuation of a user-initiated in-app action, terminated at completion.
3. Data safety form: confirm the location entry still describes collection accurately (no
   change to purpose or sharing).
4. `docs/privacy-policy.md` (public legal text): engineering supplies the fact that location is
   recorded in the background only while a workout the user started is running, indicated by a
   persistent notification; the maintainer decides the wording. Not edited here.

---

## 11. Decisions that require maintainer approval before PR-1

| # | Decision | Recommendation |
| --- | --- | --- |
| 1 | Option C (own minimal native layer) over B (`flutter_foreground_task`) and A (geolocator's notification) | C; B is the fallback if C fails the device matrix |
| 2 | Cached-engine lifecycle change with conditional destroy | Accept |
| 3 | `POST_NOTIFICATIONS` request at first Start; use existing `permission_handler` vs 15 lines of Kotlin | Request at first Start; `permission_handler` (already in the lockfile, zero new deps) |
| 4 | Partial wake lock while `active` | Accept; measure |
| 5 | Direct headless Finish vs optional two-tap confirm in the notification | Direct for the first release; two-tap as an opt-in follow-up |
| 6 | Per-point synchronous write + 5-s heartbeat (vs ≤5-point buffer) | Per-point + heartbeat |
| 7 | Fold completed-point `sequence` backfill into the same v7 migration | Yes (one migration, needed by finalization and IP-4) |
| 8 | No runtime feature flag / kill switch | Accept; revert-and-rebuild is the rollback |
| 9 | Play Console declaration + privacy-policy fact recorded as `MC-3.x` | Yes |
| 10 | PR-0 build proof budget (disk) before any Android change | Yes |
| 11 | Two-step Finish, `ApplicationExitInfo` metric, and battery-optimization prompt stay out of scope | Yes |

---

## 12. Sources

Platform and policy statements above are taken from these pages (read 2026-08-17):

- Android — [Handle user-initiated stopping of apps running foreground services](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping) (Task Manager "Stop": no callback, app removed from memory, back stack cleared).
- Android — [Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission) (FGS runs without `POST_NOTIFICATIONS`; notice visible in Task Manager only when denied).
- Android — [Request location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions) (foreground location includes a running foreground service; `foregroundServiceType="location"` required on 10+; ABL definition).
- Android — [Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16) (no FGS/location/notification change relevant here).
- Google Play — [Understanding location in the background permissions](https://support.google.com/googleplay/android-developer/answer/9799150?hl=en) (FGS conditions: continuation of an in-app user-initiated action; terminated after the use case).
- Google Play — [Understanding foreground service and full-screen intent requirements](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en) (per-type declaration, description, and video in Play Console App content).
- Plugin sources read locally: `~/.pub-cache/hosted/pub.dev/geolocator_android-5.0.3` (`GeolocatorLocationService.java`, `BackgroundNotification.java`, `StreamHandlerImpl.java`, `GeolocatorPlugin.java`, `location/FusedLocationClient.java`, `AndroidManifest.xml`), `location-7.0.1/android/src/main/AndroidManifest.xml`, `flutter_foreground_task-10.0.0` (`AndroidManifest.xml`, Kotlin line count, `CHANGELOG.md`), `flutter_background_service_android-6.3.1/android/src/main/AndroidManifest.xml`.
- Flutter embedding: `javap -p -c` on `flutter_embedding_release-1.0.0-c416acfeb…jar` for `FlutterFragmentActivity` (`getCachedEngineId`, `shouldDestroyEngineWithHost`, `createFlutterFragment`, `configureFlutterEngine`), `FlutterFragment` (`shouldDestroyEngineWithHost`, `provideFlutterEngine`, `NewEngineFragmentBuilder.createArgs`), `FlutterActivityAndFragmentDelegate` (`isFlutterEngineFromHost`).

---

## Appendix A — explicitly not verified here

- No build, test, emulator, or device was run; every runtime claim is documentation- or
  source-inferred and must be proven by PR-0 (build) and PR-5 (device matrix).
- The exact wording of the current Play Console foreground-service and Data-safety entries for
  RythmRun was not inspected (maintainer-only).
- Battery/thermal impact of the wake lock and per-point writes: to be measured, not assumed.
- Behavior on Android 24–28 devices: reasoned from `ServiceCompat`/API-level rules, not run.
