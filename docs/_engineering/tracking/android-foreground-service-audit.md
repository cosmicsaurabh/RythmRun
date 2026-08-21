---
published: false
---

# Android Compatibility, Foreground-Service, Notification, and OEM Battery Audit — IP-3.4

| Field | Value |
| --- | --- |
| Audited | 2026-08-17, branch `auth-impr` at `d0e5b92` plus the staged-but-uncommitted docs (`gps-tracking-audit.md`, `android-background-tracking-design.md`, `sync-reliability-audit.md`, IP-3/IP-4/STATUS edits). Read, not modified. |
| Scope | Android compatibility (API 24 → 36), foreground-service reliability, notification behaviour, and OEM battery-management risk for user-started outdoor workouts that must survive screen-off/background. Nothing else. |
| Method | Static read of the Flutter app, the Android project, `MainActivity.kt`, the manifest contributions of every Android plugin in `pubspec.lock`, and the `geolocator_android 5.0.3`, `location 7.0.1`, `flutter_foreground_task 10.0.0`, `flutter_background_service_android 6.3.1` sources in the local pub cache; **one local build artifact** — the merged debug manifest and manifest-merger report under `rythmrun_frontend_flutter/build/app/…` (dated 2026-08-11, Gradle 8.14 caches), read to learn what transitive AARs add; the official Android and Google Play documentation listed in §15 (fetched 2026-08-17). **Commands run:** read-only `ls`, `cat`, `grep`, `sed`, `awk`, `flutter --version`, `git status/diff`. **Not run:** any build, `flutter test`, `flutter analyze`, emulator, physical device, CI, staging, production, Play Console. No code, dependency, or commit was changed. |
| Evidence classes | **[code]** read in this repository at the cited line · **[plugin]** read in plugin source at the cited line · **[doc]** quoted from an official Android/Play page in §15 · **[vendor]** vendor documentation · **[community]** dontkillmyapp.com or similar, unverified · **[inferred]** reasoned from the above, not observed · **[unknown]** cannot be known without a device. |
| Related | [IP-3 workout durability](../improvement-plan/IP-3-workout-durability.md) · [Android background tracking design (proposal)](./android-background-tracking-design.md) · [GPS tracking audit](./gps-tracking-audit.md) · [Sync reliability audit](../sync/sync-reliability-audit.md) (`SYNC-01`) |
| Verdict | **Screen-off/background tracking does not exist today and cannot be switched on by configuration alone.** The manifest, Kotlin, and Dart layers all lack the pieces Android 12–16 require. The staged design proposal is the right shape; this audit confirms it against the platform docs and adds seven corrections (§0.4). **Nothing about background tracking is proven until the §12 device matrix runs.** |

Line references use `file:line`. `manifest` = `rythmrun_frontend_flutter/android/app/src/main/AndroidManifest.xml`; `gradle` = `rythmrun_frontend_flutter/android/app/build.gradle`; `MainActivity` = `rythmrun_frontend_flutter/android/app/src/main/kotlin/com/github/cosmicsaurabh/rythmrun/MainActivity.kt`; `service` = `rythmrun_frontend_flutter/lib/core/services/live_tracking_service.dart`; `provider` = `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/providers/live_tracking_provider.dart`; `main` = `rythmrun_frontend_flutter/lib/main.dart`; `track_screen` = `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/screens/track_screen.dart`; `geo/*` = `~/.pub-cache/hosted/pub.dev/geolocator_android-5.0.3/android/src/main/java/com/baseflow/geolocator/*`.

---

## 0. Executive verdict

### 0.1 What currently works (verified in code)

| Works | Evidence |
| --- | --- |
| Foreground, screen-on GPS workouts: permission gate, GPS start, acceptance policy, pause/resume, finish, atomic idempotent SQLite save, save-failure recovery UI | `service:35-96`, `provider:155-515`, GPS audit §0/§2 **[code]** |
| The manifest is valid for the app's *current* foreground-only behaviour on target 36: fine/coarse location, `INTERNET`, ad-ID permissions removed, `allowBackup=false`, single `singleTop` activity | `manifest:4-6,9-20,23,28-36` **[code]** |
| Turning location services on from inside the app via the system dialog (`location` plugin `requestService`) | `service:190-224` **[code]** |
| Denied-permission and services-disabled states are shown truthfully on the Track tab | `track_screen:468-472,476-560` **[code]** |
| Wall-clock elapsed time self-corrects after any stall (matters once the CPU sleeps) | `provider:720-740`; `lib/core/tracking/workout_timeline.dart` **[code]** |
| Play-relevant hygiene already right for later: no `ACCESS_BACKGROUND_LOCATION`, no boot receiver, no exact alarms, no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` in the app manifest | `manifest` (absent) **[code]** |

### 0.2 What definitely does not work (verified in code against platform docs)

| Does not work | Why | Evidence |
| --- | --- | --- |
| Tracking with the screen off, app in background, or after swipe-away | No foreground service, no `foregroundServiceType` component owned by the app, no notification, no `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_LOCATION`/`POST_NOTIFICATIONS`; the geolocator stream is a plain `getPositionStream` with generic `LocationSettings`. Android considers location "foreground" only while an Activity is visible **or a foreground service runs** — neither holds once the screen is off. The Flutter engine dies with `MainActivity` on swipe-away (default `FlutterFragmentActivity`), taking the Dart isolate, timers, GPS stream, and the in-memory workout with it | `manifest:4-6`; `MainActivity:7-12`; `service:81-90`; `provider:57-72`; [S8] **[code][doc]** |
| Switching on geolocator's built-in foreground mode *today* on Android 14+ | Its service is declared by the plugin with `foregroundServiceType="location"`, but nothing declares `FOREGROUND_SERVICE_LOCATION`: on API 34+ `startForeground()` throws `SecurityException`. (On 28–33 it would likely start, because `FOREGROUND_SERVICE` reaches the merged manifest **transitively** from `androidx.work:work-runtime:2.7.0` — a permission the app neither declares nor controls, see G-01.) Even where it starts it has no controls and an `IMPORTANCE_NONE` channel (§5) | `geo/GeolocatorLocationService.java:147`; plugin manifest `:5-9`; app `manifest`; merged debug manifest `:65-66` + merger report `:760-767`; [S1][S2] **[plugin][code][doc]** |
| Notification-panel controls, notification-tap, headless Pause/Resume/Finish | No notification, receiver, `PendingIntent`, or channel exists anywhere in the app | `grep` over `lib/`, `android/` (no matches) **[code]** |
| Surviving process death, Task Manager "Stop", force-stop, reboot, permission revocation | Active workout is memory-only until Finish; no checkpoint tables (IP-3.1–3.3 not built) | `provider:57-72,495`; STATUS "IP-3 0 of 5" **[code]** |
| Honest handling of an approximate-only ("Approximate location") grant | Any of fine/coarse counts as granted; a coarse-only workout starts and then accepts nothing (50 m accuracy ceiling) — a silent zero-route workout | `service:56-62`; `geo/permission/PermissionManager.java:44-85`; policy accuracy ceiling (GPS audit §1.3) **[code][plugin]** |
| "Open App Settings" for a permanently denied permission | The button calls `checkPermissions()`, which cannot re-prompt for `deniedForever`; `Geolocator.openAppSettings()` is never called | `track_screen:537-546`; `service:45-54`; `grep openAppSettings` (none) **[code]** |
| Recovery from location services being turned off mid-workout | Stream error sets a message; the timer keeps counting; nothing re-subscribes or pauses | `provider:706-717`; `service:116-118` (GPS audit F4) **[code]** |
| Detecting a user-applied **Restricted** battery state or a Battery-Saver location mode that stops screen-off location | Not read anywhere; on Android 9+ a restricted app's "existing foreground services are removed from the foreground" once it goes to the background — the FGS approach fails silently on such a device unless detected | [S13][S14] **[doc]**; app **[code]** (absent) |

### 0.3 Unknown until supported-device testing

Every runtime statement below is inferred from documentation or plugin source. In particular: whether a given OEM keeps a `location` FGS alive for 30+ minutes and multi-hour sessions; whether GPS fixes stall without an app-held wake lock; the device's Battery-Saver location mode; the effect of "sleeping apps"/"autostart"/"lock in recents"; notification visibility and re-posting after user dismissal; the exact battery cost per hour; whether the notification content intent reuses the existing task with `taskAffinity=""`; and the behaviour on API 24–28 devices. Emulator evidence is insufficient for the OEM rows (IP-3.4 item 9).

### 0.4 Assessment of the staged design proposal

The proposal (`android-background-tracking-design.md`) is architecturally correct against the platform facts checked here — one Dart isolate on a cached engine, an app-owned started `location` FGS that owns only the notification, no `ACCESS_BACKGROUND_LOCATION`, `START_NOT_STICKY`, user-driven recovery. This audit adds or corrects the following; each is expanded in the section noted.

| # | Correction / addition | Section |
| --- | --- | --- |
| C1 | **Do not hold a continuous partial wake lock while active.** Google's own wake-lock guidance for location says the location callback already wakes the device and a separate continuous wake lock is redundant; app-held partial wake locks held while running an FGS count toward Play's "excessive partial wake locks" threshold (2 h/24 h, >5 % of sessions ⇒ store visibility impact). Rely on fused-provider callbacks; write each point in the callback; measure first; add a *bounded* wake lock only if the matrix shows stalls | §8 |
| C2 | Detect `ActivityManager.isBackgroundRestricted()` (API 28+) at Start and `PowerManager.getLocationPowerSaveMode()` / `isPowerSaveMode()` and say so honestly before claiming background tracking; the FGS is *removed from the foreground* for a restricted app when it leaves the screen | §9 |
| C3 | Treat the FGS notification as **user-dismissible** (Android 13+, and `FLAG_ONGOING_EVENT` on 14+ for all apps): controls can vanish while tracking continues; re-post only on state transitions; keep in-app controls authoritative | §7 |
| C4 | Approximate-only grants need `Geolocator.getLocationAccuracy()` (reduced/precise) and an upgrade prompt or a refusal to start; "Only this time" grants survive exactly as long as the FGS runs | §9 |
| C5 | On location-services-off, use geolocator's Android `getServiceStatusStream()` to auto-pause with an `interrupted` event instead of a passive error message | §7, §9 |
| C6 | Notification-tap task reuse with `taskAffinity=""` and the 10-second FGS notification delay exemption (`FOREGROUND_SERVICE_IMMEDIATE`) are correct in the proposal but are device-test items, not facts | §7, §12 |
| C7 | Play Console: declaring `FOREGROUND_SERVICE_LOCATION` on target 34+ triggers the "Foreground service permissions" declaration (description, deferral impact, demo video). The two *plugin-contributed* `location`-type services already sit in today's merged manifest without that permission — worth knowing when the console form appears | §10 |
| C8 | The proposal's §2.1 says enabling geolocator's foreground mode today "would fail with `SecurityException` on API 28+". Only the 34+ half holds: the locally built merged debug manifest already carries `FOREGROUND_SERVICE` and `WAKE_LOCK` **transitively** from `androidx.work:work-runtime:2.7.0` (pulled in by the GMS ads/measurement stack). Declare both intentions explicitly in the app manifest (`FOREGROUND_SERVICE` yes; `WAKE_LOCK` only if C1 ever changes) so a dependency change cannot silently remove a permission the service relies on | §1, §4 |

Minor: the proposal's `build.gradle` line references (`150,155,153`) are stale; the current file has `compileSdk 36` at `gradle:113`, `minSdkVersion flutter.minSdkVersion` at `gradle:132`, `targetSdk = 36` at `gradle:133`.

---

## 1. Verified current state (facts with evidence)

| Fact | Evidence |
| --- | --- |
| `compileSdk 36`, `targetSdk 36`, `minSdkVersion flutter.minSdkVersion` (= 24 on the local Flutter 3.44.9; CI pins 3.44.1, same major), Java/Kotlin 17, `minifyEnabled false`, `shrinkResources false`, only extra dependency `androidx.activity:activity-ktx:1.8.0` | `gradle:113,132,133,116-123,152-153,174`; `$FLUTTER/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:26` **[code]** |
| `proguard-rules.pro` is referenced but does not exist in `android/app/` (inert while `minifyEnabled false`; verify in PR-0's release build) | `gradle:154-157`; `ls android/app` **[code]** |
| Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 declared; `android.builtInKotlin=false`, `android.newDsl=false`. STATUS records no build against them; however a merged **debug** manifest and merger report dated 2026-08-11 exist under `build/app/…` and reference Gradle 8.14 caches — so at least a debug manifest merge ran on the bumped toolchain, unrecorded; the release configuration remains unproven | `android/gradle/wrapper/gradle-wrapper.properties:5`; `android/settings.gradle.kts:21-22`; `android/gradle.properties:5,7`; `build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml` (mtime 2026-08-11); `build/app/outputs/logs/manifest-merger-debug-report.txt:761` **[code]** |
| App manifest permissions: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`; four ad permissions removed with `tools:node="remove"`; **no** `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `WAKE_LOCK`, `ACCESS_BACKGROUND_LOCATION`, `RECEIVE_BOOT_COMPLETED` | `manifest:4-20` **[code]** |
| App manifest components: one activity (`.MainActivity`, `exported=true`, `singleTop`, `taskAffinity=""`, MAIN/LAUNCHER); **no** `<service>`, `<receiver>` | `manifest:28-49` **[code]** |
| **Merged** manifest (plugin sources + the local debug merge artifact) additionally carries: `com.baseflow.geolocator.GeolocatorLocationService` (`exported=false`, `foregroundServiceType="location"`), `com.lyokone.location.FlutterLocationService` (same), `ACCESS_NETWORK_STATE` (connectivity_plus), `USE_BIOMETRIC`/`USE_FINGERPRINT` (flutter_secure_storage), and — **transitively from `androidx.work:work-runtime:2.7.0`** — `WAKE_LOCK`, `FOREGROUND_SERVICE`, WorkManager's `SystemForegroundService` (no type) and a disabled `BOOT_COMPLETED` `RescheduleReceiver`. **Nothing adds `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, or `RECEIVE_BOOT_COMPLETED`.** `minSdkVersion=24`, `targetSdkVersion=36` in the merged result | `geolocator_android-5.0.3/android/src/main/AndroidManifest.xml:5-9`; `location-7.0.1/…/AndroidManifest.xml:3-11`; `connectivity_plus-6.1.5/…:3`; merged debug manifest `:7-9,15-18,62-66,146-160,266-281,327-336`; merger report `:760-767` **[plugin][code]** |
| `MainActivity` is a 10-line `FlutterFragmentActivity` (`enableEdgeToEdge()` then `super.onCreate`); no cached engine, no `getCachedEngineId`, no intent handling | `MainActivity:7-12` **[code]** |
| Tracking source: `Geolocator.getPositionStream(LocationSettings(accuracy: best, distanceFilter: 5))`; no `AndroidSettings`, no `foregroundNotificationConfig`, no interval (plugin default 5000 ms, `minUpdateInterval` = interval, `PRIORITY_HIGH_ACCURACY`) | `service:81-90`; `geo/location/LocationOptions.java:23,59`; `geo/location/FusedLocationClient.java:97-113` **[code][plugin]** |
| Permission model: `whileInUse` **or** `always` ⇒ granted; geolocator reports `whileInUse` when *either* fine or coarse is granted and no ABL is in the manifest; `denied` triggers one `requestPermission()`; `deniedForever` returns a status only | `service:35-63`; `geo/permission/PermissionManager.java:44-85` **[code][plugin]** |
| Map initialisation requests the current location (and therefore the permission) at app open, before any Start | `lib/presentation/features/Map/screens/live_map_feed.dart:76-81` → `service:121-127` → `service:43-50` **[code]** |
| Active workout state lives in `LiveTrackingNotifier` memory; first durable write is `_persistCompletedWorkout` after Finish; pause keeps the GPS stream running at high accuracy | `provider:57-72,300-339,495` **[code]** |
| Stream error path: message only, no pause, no re-subscribe | `provider:706-717`; `service:116-118` **[code]** |
| `main.dart` lifecycle: `resumed` ⇒ `syncAll()`; no `paused`/`detached`/`hidden` handling, no checkpoint | `main:57-61,75` **[code]** |
| `permission_handler 12.0.3` is declared and registered but unused in `lib/`; `location 7.0.1` is used only for the enable-services dialog | `pubspec.yaml:63-64`; `GeneratedPluginRegistrant.java:64,74`; `grep` **[code]** |
| Plugin versions in the lockfile: geolocator 14.0.2 / geolocator_android 5.0.3 / geolocator_platform_interface 4.2.8, location 7.0.1, permission_handler 12.0.3 / permission_handler_android 13.0.1, sqflite_android 2.4.3, google_mobile_ads 5.3.1, flutter_secure_storage 10.3.1 | `pubspec.lock` **[code]** |
| geolocator's foreground mode (not used): service is **bound** at engine attach (`BIND_AUTO_CREATE`), `START_STICKY`, `startForeground(id, notification)` with the manifest type, channel `IMPORTANCE_NONE` + `VISIBILITY_PRIVATE`, `PRIORITY_HIGH` builder, **no action buttons**, content intent = package launch intent, optional untimed `PARTIAL_WAKE_LOCK` + Wi-Fi lock; the plugin's own doc says it "does not run your service in the background … does not prevent Android from killing the activity" | `geo/GeolocatorPlugin.java:148-158`; `geo/GeolocatorLocationService.java:56-58,135-151,194-215`; `geo/location/BackgroundNotification.java:36-38,46-61,63-74,85-90`; `geolocator_android-5.0.3/lib/src/types/android_settings.dart:49-56` **[plugin]** |
| No test in `test/` exercises app lifecycle, notifications, foreground service, or a stream error while active (only after dispose) | `test/presentation/features/live_tracking/providers/live_tracking_provider_test.dart` (18 tests, `:391`) **[code]** |

---

## 2. Compatibility by Android version (API 24 → 36)

"Today" = the app as at `d0e5b92`. "Proposed" = the design proposal amended by §0.4. Requirements are **[doc]** unless marked.

| Android / API | Platform requirement or behaviour that matters here | Today | Proposed design |
| --- | --- | --- | --- |
| **7.0–7.1 / 24–25** (minSdk) | No notification channels; `startService` + `startForeground(id, notif)`; no `FOREGROUND_SERVICE` permission; no FGS types; Doze (6.0+) exists — FGS keeps the app out of App Standby | Foreground-only tracking | Works via `ContextCompat.startForegroundService` / `ServiceCompat.startForeground` (compat handles both). **[inferred]** — no 24–25 device is in the matrix; test at least once |
| **8.0–8.1 / 26–27** | Channels required; background execution limits: after `startForegroundService()` "the service must call its startForeground() method within five seconds" [S12]; background location for apps *without* an FGS is "delivered only a few times an hour" [S23] — an FGS is exempt (Android 8 background-location-limits page, not re-fetched **[inferred]**) | Foreground-only | Requires channel ≥ `IMPORTANCE_LOW` [S9]. Fine |
| **9 / 28** | `FOREGROUND_SERVICE` permission or `SecurityException` [S1]; **user "Restricted" battery state**: "Can't launch foreground services / Existing foreground services are removed from the foreground" for apps in the background [S13]; App Standby buckets; Battery Saver may disable location when the screen is off (mode is OEM/version specific) [S14] | Foreground-only | Needs `FOREGROUND_SERVICE` (missing today, G-01). Must detect `isBackgroundRestricted()` (C2). Battery-Saver mode read where available |
| **10 / 29** | `foregroundServiceType="location"` mandatory for location FGS [S1][S8]; `ACCESS_BACKGROUND_LOCATION` introduced ("Allow all the time") — **not needed**: a running FGS is foreground location ("retains access when … turns their device's display off") [S8] | Foreground-only | Type declared on the app's own service; no ABL |
| **11 / 30** | One-time permission ("Only this time"): access lasts while an Activity is visible, briefly after backgrounding, or **"until the foreground service stops"** if the FGS was launched while visible; revocation "terminates" the process [S10]; while-in-use FGS restriction: an FGS started from the background cannot access location unless exempt (notification interaction is exempt) [S3]; auto-reset of unused apps' permissions (Android 11 feature, not re-fetched **[inferred]**) | Foreground-only; a one-time grant lapses shortly after backgrounding | FGS started only from a visible Start/Resume; kept alive across Pause so no background start is ever needed |
| **12–12L / 31–32** | FGS start from background throws `ForegroundServiceStartNotAllowedException` except exemptions (visible activity; user interaction with a notification/widget; battery optimisations off; …) [S3]; FGS notification may be **delayed 10 s** unless immediate ([S5]; opt in with `setForegroundServiceBehavior(FOREGROUND_SERVICE_IMMEDIATE)` or action buttons — exemption list from the API reference, **[inferred]** not re-fetched); `PendingIntent` mutability mandatory; notification trampolines banned (no `startActivity` from a receiver/service after a tap) [S6]; **approximate location** option [S6][S8] | Approximate grant is silently accepted as "granted" (G-11) | `FLAG_IMMUTABLE`, `FOREGROUND_SERVICE_IMMEDIATE`, body tap = the notification's own content `PendingIntent`, actions = broadcast receiver; approximate detection (C4) |
| **13 / 33** | `POST_NOTIFICATIONS` runtime permission; "Apps don't need to request the POST_NOTIFICATIONS permission in order to launch a foreground service" but with it denied users "see notices related to foreground services in the Task Manager but don't see them in the notification drawer"; notifications are **off by default for new installs** targeting 33+ until requested [S4]; **Task Manager "Stop"**: entire app removed from memory, back stack cleared, notification removed, **no callback**, jobs/alarms preserved [S7]; FGS notifications **dismissible by default** [S11] | N/A | Request at first Start with rationale; workout still starts if denied; honest copy; recovery card after Stop; C3 |
| **14 / 34** | Every FGS must declare a type; type-specific permission `FOREGROUND_SERVICE_LOCATION` or `SecurityException` [S1][S2]; `location` runtime prerequisites checked **at creation**: services enabled + coarse or fine granted; from the background this fails unless exempt [S2][S3]; `FLAG_ONGOING_EVENT` notifications dismissible for **all apps** (except locked screen, "Clear all", CallStyle, DPC, media) [S11]; Play Console FGS declaration [S15] | N/A | Manifest permission (G-02); start only when visible; catch `SecurityException`; C3; C7 |
| **15 / 35** | `dataSync`/`mediaProcessing` timeouts and `BOOT_COMPLETED` restrictions — **not applicable** to `location`; `SYSTEM_ALERT_WINDOW` exemption narrowed [S1]; edge-to-edge enforced for target 35 (already `enableEdgeToEdge()`) | N/A | No additional FGS work |
| **16 / 36** (target) | Behaviour-changes page (fetched) lists **no** new foreground-service, location, or notification restriction; FGS page adds only "background jobs started from a foreground service now must adhere to their respective runtime quotas" — the app schedules no jobs [S1][S16]. Non-FGS target-36 items to verify in PR-0: predictive back on by default, edge-to-edge opt-out removed, large-screen orientation restrictions ignored [S16] | Builds for 36 (unproven since the toolchain bump) | No additional FGS work; PR-0 proves the build |

Conclusion for target SDK 36: the required set is `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` + `POST_NOTIFICATIONS` (+ `WAKE_LOCK` only if a wake lock is ever held), an app-owned `<service android:foregroundServiceType="location" android:exported="false">`, `ServiceCompat.startForeground(…, FOREGROUND_SERVICE_TYPE_LOCATION)` called from a service started while an Activity is visible with location services on and a location permission granted, on a channel of importance ≥ LOW, with `FOREGROUND_SERVICE_IMMEDIATE`, immutable `PendingIntent`s, and no notification trampolines. **`ACCESS_BACKGROUND_LOCATION` is not required** for anything in scope [S8][S15].

### 2.1 Startup and shutdown order that satisfies target 36 (from the docs above)

1. User taps **Start** (or **Resume** on the recovery card) while `MainActivity` is visible — the always-permitted case for FGS creation [S3].
2. Preconditions, in this order: location services enabled; `ACCESS_FINE_LOCATION` granted (if only coarse: warn/refuse per C4); (API 33+) request `POST_NOTIFICATIONS` once with rationale — **do not block Start on the answer** [S4]; read `isBackgroundRestricted()` and the Battery-Saver location mode for honest copy (C2).
3. Write the durable `starting` checkpoint (IP-3.1; R1 in the proposal).
4. `ContextCompat.startForegroundService(intent)`; inside `onStartCommand` **immediately** build the notification and call `ServiceCompat.startForeground(id, notification, FOREGROUND_SERVICE_TYPE_LOCATION)` in a `try` that catches `SecurityException`, `ForegroundServiceStartNotAllowedException` and, on 34+, the missing/invalid-type exceptions; report `started`/`startFailed` to Dart. Channel created in `onCreate` with `IMPORTANCE_LOW`. Must complete well inside the five-second window [S12].
5. Only after `started`: `Geolocator.getPositionStream(...)`; commit `active`; render the real notification.
6. Any failure ⇒ stop the service, delete the checkpoint, show an honest error, no "tracking" state.
7. Shutdown (Finish/Discard/teardown): stop GPS → finalize → `stopForeground(STOP_FOREGROUND_REMOVE)` → `stopSelf()`. Pause keeps the service and stops GPS.

---

## 3. Compatibility by OEM category

Ranking is from vendor documentation where it exists and otherwise from community reports; **none of it is device-verified for RythmRun**.

| OEM category | Documented / reported behaviour | Risk to a `location` FGS workout | Mitigation that is in scope | Evidence |
| --- | --- | --- | --- | --- |
| **Pixel / stock-like** (Pixel, Motorola, HMD, Sony) | Platform rules only: FGS survives screen-off, swipe-away and Doze while moving; user "Restricted" battery state demotes the FGS [S13]; Battery Saver location mode is device-configured, on 12+ `LOCATION_MODE_FOREGROUND_ONLY` keeps FGS location "even if the screen is off" [S14]; Task Manager Stop kills the whole app [S7] | Low; failure modes are the platform ones (Restricted, Battery Saver mode, Task Manager) | Detect and explain (C2); recovery card; never claim tracking without a running service | **[doc]** |
| **Samsung One UI** | Vendor doc: apps unused ~3 days "causing poor system health" become **sleeping** — "Job, Alarm, and Foreground-service are restricted"; unused 16 days become **deep sleeping** — "only become active when the user opens them, and become inactive when they go into the background"; exceptions at *Settings › Device care › Battery › Background usage limits* ("Never sleeping apps") [S17]. Community reports of FGS kills after minutes on some One UI versions | Medium–high: an app used every few days is unlikely to be sleeping; a comeback after weeks may start a workout as a sleeping app | Recovery card; a Samsung-specific *help* text pointing to "Never sleeping apps" only if the matrix shows kills; **do not** request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | **[vendor]** [S17], **[community]** [S18] |
| **Xiaomi / Redmi / POCO** (MIUI / HyperOS) | Community: "Autostart" permission, per-app battery saver "No restrictions", app must be **locked in Recents** or clearing recents kills it including services, "MIUI optimization" developer toggle | High for swipe-away and long sessions | Recovery card; optional in-app help page listing those settings; never assume swipe-away is survivable on this OEM | **[community]** [S18] |
| **OnePlus / Oppo / Realme** (OxygenOS / ColorOS) | Community: "Battery optimization → Don't optimize" (system dialog), "Allow background activity", "Allow auto-launch", lock in Recents; historically aggressive killers | High | As Xiaomi | **[community]** [S18] |
| **Generic / GMS-less** (Huawei/Honor EMUI, AOSP forks) | geolocator falls back to `LocationManagerClient` when Play services are unavailable; vendor battery managers ("App launch" on EMUI) kill background work | Unknown; also outside D-008's promised platform in practice (Google Sign-In, AdMob assume GMS) | Out of the matrix; document as unsupported unless a device is available | **[plugin]** `geo/location/GeolocationManager.java:77-88`, **[community]** |

Common to all: the app cannot programmatically exempt itself; the only honest tools are (a) an FGS started correctly, (b) detection of the platform states that are readable (`isBackgroundRestricted`, `isPowerSaveMode`, `getLocationPowerSaveMode`, `areNotificationsEnabled`), (c) durable checkpoints plus a truthful recovery card, and (d) a help page with vendor settings names that is **not** wired to vendor-specific intents (they change per release and crash on absence).

---

## 4. Manifest / service / notification gap table

`Sev`: **H** blocks background tracking or violates a platform requirement · **M** correctness/UX under a common condition · **L** hygiene.

| ID | Sev | Gap | Evidence | Platform requirement | Smallest fix (design PR) |
| --- | --- | --- | --- | --- | --- |
| G-01 | M | `FOREGROUND_SERVICE` is not declared by the app; it reaches the merged manifest only transitively via `androidx.work:work-runtime:2.7.0` (from the GMS ads/measurement stack) | `manifest:4-6` (absent); merged debug manifest `:66`; merger report `:766-767` | API 28+: `SecurityException` without it [S1] | Declare explicitly (PR-4a) so a dependency change cannot remove it |
| G-02 | H | No `FOREGROUND_SERVICE_LOCATION` permission | `manifest` (absent) | API 34+: `SecurityException` for a `location`-type FGS without it [S1][S2] | Add (PR-4a); triggers Play declaration (§10) |
| G-03 | H | No `POST_NOTIFICATIONS` permission or request flow | `manifest` (absent); `grep` (none) | API 33+: notifications off by default for new installs; FGS notice visible only in Task Manager when denied [S4] | Add + request at first Start with rationale (PR-4a); `permission_handler` already in the lockfile |
| G-04 | H | No app-owned foreground service; the only `location`-type services in the merged manifest are two dormant plugin services (one from a plugin used only for a dialog) | plugin manifests (§1); `service:190-224` | API 29+: location FGS must declare type [S8]; a bound-only plugin service that dies with the engine cannot carry controls | Own started service `exported=false`, `foregroundServiceType="location"`, `START_NOT_STICKY` (PR-4a) |
| G-05 | H | Flutter engine destroyed with `MainActivity` (default `FlutterFragmentActivity`): swipe-away ends tracking even if a service existed | `MainActivity:7-12`; proposal §2.4 items 7–8 (embedding bytecode) | Not a platform rule; Flutter embedding behaviour **[inferred]** | Cached `FlutterEngine` with conditional destroy (PR-4a); device-test swipe-away |
| G-06 | H | Generic `LocationSettings`; no `AndroidSettings` / no explicit `intervalDuration` | `service:81-84` | — | Keep geolocator as source; set an explicit interval (5 s to start; see GPS audit F14 on the 12,000-point cap) (PR-4a) |
| G-07 | H | No notification, channel, actions, receiver, `PendingIntent`s, body-tap handling | `grep` (none) | API 26+ channel; API 31+ immutability/no trampolines; API 33/34 dismissibility [S6][S11] | PR-4a (notification) / PR-4b (actions) |
| G-08 | H | Active workout memory-only; no checkpoint; process death (Task Manager Stop, force-stop, reboot, permission revocation, OEM kill) loses it | `provider:57-72,495`; STATUS IP-3 0/5 | Task Manager Stop sends no callback [S7]; permission revocation "terminates" the process [S10] | IP-3.1–3.3 (PR-1…PR-3) — prerequisite for honest background tracking |
| G-09 | M | Approximate-only grant counted as granted; no `getLocationAccuracy()`; no upgrade prompt | `service:56-62`; `geo/permission/PermissionManager.java:44-85` | Android 12+ approximate option; "your app should still work when the user grants only approximate" [S6][S8] — for GPS tracking that means refuse/warn, not silently record nothing | Check `Geolocator.getLocationAccuracy()`; on `reduced` block Start with an upgrade action (PR-4a or earlier) |
| G-10 | M | `deniedForever` button labelled "Open App Settings" re-runs `checkPermissions()`; `openAppSettings()` never called | `track_screen:537-546`; `service:45-54` | — | Call `Geolocator.openAppSettings()` for `deniedForever` (any PR) |
| G-11 | M | Location services toggled off mid-workout: message only, timer runs, no re-subscribe/auto-pause | `provider:706-717`; `service:116-118` | — | Auto-pause with `interrupted` via `Geolocator.getServiceStatusStream()` (Android) (PR-2a/PR-4a) |
| G-12 | M | No detection of user "Restricted" battery state, Battery-Saver location mode, or notification enablement ⇒ cannot warn honestly | absent | [S13][S14][S4] | Kotlin `isBackgroundRestricted()`, `getLocationPowerSaveMode()`, `areNotificationsEnabled()` behind the channel (PR-4a) |
| G-13 | M | Pause keeps GPS at high accuracy | `provider:300-339` | — | Stop the stream on Pause; keep the FGS (PR-2a/4a) |
| G-14 | M | Lifecycle: only `resumed` ⇒ sync; sync also runs mid-workout | `main:57-61,75` | — | Skip sync while a workout is active; no lifecycle checkpoint needed once writes are per-point (PR-2a) |
| G-15 | M | Map init prompts for permission at app open (`getCurrentLocation` → `requestPermission`) | `live_map_feed.dart:76-81`; `service:121-127,43-50` | Play/UX: out-of-context prompt (GPS audit F10) | Check-only in `getCurrentLocation`; request only on Start |
| G-16 | L | `WAKE_LOCK` not declared by the app (present transitively via work-runtime 2.7.0 / play-services-measurement) — **correct** if C1 is followed; declare only with a measured need | `manifest` (absent); merged debug manifest `:65`; merger report `:760-762` | Vitals wake-lock metric [S19][S20] | Do not hold one by default; if ever needed, declare explicitly and keep it timed |
| G-17 | L | `location` plugin contributes a second `location`-type service and duplicate permissions solely for `requestService()` | `location-7.0.1` manifest `:3-11`; `service:190-224` | — | Optional later cleanup (Kotlin `SettingsClient` dialog or `Geolocator.openLocationSettings()`); not required for IP-3.4 |
| G-18 | L | `permission_handler` registered but unused | `pubspec.yaml:63`; `GeneratedPluginRegistrant.java:74` | — | Use it for `POST_NOTIFICATIONS`, or drop it |
| G-19 | L | Toolchain bump unproven; `proguard-rules.pro` referenced but absent | STATUS; `gradle:154-157` | — | PR-0 build proof records both |
| G-20 | L | No test covers lifecycle, notification, service failure, or stream error while active | `live_tracking_provider_test.dart:391` | — | Engine/channel fakes in PR-2a/4a; device harness PR-5 |

---

## 5. Recommended lowest-cost architecture

**Adopt option C from the design proposal — an app-owned minimal Kotlin foreground service that owns only the notification, with one Dart isolate on a cached `FlutterEngine` owning the workout state machine, geolocator as the position source, SQLite checkpoints, and no new pub dependency — amended by C1–C7.** Reasons, in the order the maintainer cares about:

1. **Cost.** ~250 lines of Kotlin on stable AndroidX APIs already on the classpath (`ServiceCompat`, `NotificationCompat`, `PendingIntentCompat` via `androidx.core`, `FlutterEngineCache` from the embedding); no paid service; no plugin fork.
2. **Correctness on 12–16.** Every platform rule in §2 is satisfied by construction: FGS created only from a visible Activity, kept across Pause so no background start is needed, immutable `PendingIntent`s, no trampolines, immediate notification, type-specific permission, `START_NOT_STICKY`, no ABL.
3. **Local-first invariants.** Kotlin never touches SQLite or coordinates; every action is applied to durable, user-scoped state by the Dart engine; recovery is user-scoped by construction (proposal §7.6).
4. **Why not the alternatives.** *Geolocator's built-in foreground mode* cannot show elapsed/paused state or action buttons, uses an `IMPORTANCE_NONE` channel (contradicts the "PRIORITY_LOW or higher" notification requirement [S9]; on 13+ likely Task-Manager-only visibility **[inferred]**), holds an untimed wake lock when enabled, and — per its own docs — dies with the Activity unless the engine is cached anyway. *`flutter_foreground_task` / `flutter_background_service`* solve the engine-lifetime problem with a second isolate, but bring an **exported** `BOOT_COMPLETED`/`MY_PACKAGE_REPLACED` receiver, `RECEIVE_BOOT_COMPLETED`, auto-restart semantics that must be neutralised with `tools:node="remove"`, two SQLite writers, and 2.6 k lines of third-party Kotlin (`flutter_foreground_task-10.0.0` manifest `:4-20`; `flutter_background_service_android-6.3.1` manifest `:10-33`). Keep B as the fallback only if C fails the matrix.

### 5.1 Kotlin vs Flutter responsibility split

| Concern | Kotlin (app module) | Flutter/Dart |
| --- | --- | --- |
| FGS lifecycle | `WorkoutTrackingService`: `startForeground` with type, `START_NOT_STICKY`, `stopForeground(REMOVE)`; report `started/startFailed/stopped`; `isRunning` | Decides *when* (Start/Resume from a visible screen; stop on Finish/Discard/teardown/fatal); waits ≤5 s for `started`; fails closed |
| Notification | Channel (`IMPORTANCE_LOW`, `VISIBILITY_PUBLIC`), builder from a **model** (state, type, elapsed base, formatted distance, action list), chronometer, `FOREGROUND_SERVICE_IMMEDIATE`, `setOngoing`, `setOnlyAlertOnce`, `setDeleteIntent` (dismissal signal), content intent = launcher-style intent to `MainActivity` | Derives the model from **committed durable state** only; formats distance with the IP-1 formatter; never sends coordinates |
| Actions | Non-exported `BroadcastReceiver` (explicit-component `PendingIntent.getBroadcast`, `FLAG_IMMUTABLE`), forwards `pause/resume/finish` to the engine via the plugin; if no engine, sends `ACTION_STOP` | `ActiveWorkoutEngine.applyAction()` — idempotent, single-flight, re-reads state in the transaction; UI adapter never in the path |
| Body tap | `MainActivity.onNewIntent/onCreate` reads `EXTRA_OPEN_WORKOUT`; **no** activity start from receiver/service | Navigates to the Track tab only if authenticated **and** this user has a live session or an orphan checkpoint |
| Engine lifetime | `MainActivity`: get-or-create cached engine before `super.onCreate`, `getCachedEngineId()`, destroy engine in `onDestroy` only when the service is not running | `stopIfRunning()` at isolate start (zombie reconcile); engine is a root Provider, not the UI notifier |
| Honesty inputs | `isBackgroundRestricted()`, `isPowerSaveMode()`, `getLocationPowerSaveMode()`, `areNotificationsEnabled()` + channel importance | Copy on the Track screen; blocks or warns before Start; never shows "tracking" without `started` |
| Wake lock | **None by default** (C1). If the matrix proves a need: a *timed* partial wake lock (seconds) around point processing, released in `finally`, only while `active` | Nothing |
| Location | Nothing (geolocator's plugin does it in-process; the running `location` FGS grants the process foreground-location capability [S8]) | `getPositionStream` with explicit `AndroidSettings(intervalDuration, distanceFilter, accuracy)`; `getServiceStatusStream` for auto-pause; `getLocationAccuracy` at Start |
| Persistence / recovery | Nothing | SQLite v7 checkpoints, per-point durable write, finalize-exactly-once, user-scoped recovery card (IP-3.1–3.3) |
| Privacy | Logs at most action names, service events, stable failure codes | No coordinates/timestamps of fixes on any log path (IP-1.2 discipline) |

---

## 6. Wake locks — needed or not?

**Verdict: not by default; measure before adding; never hold one continuously for a whole workout.**

- Google's wake-lock guidance for location APIs: `LocationManager`/`FusedLocationProviderClient` "use wake locks to acquire and deliver the device location. The wake locks are attributed to the app" and — recommendation — "Avoid acquiring a separate, continuous wake lock for caching location data, as this is redundant … the system automatically triggers a device wake-up during the location event callback" [S20]. That is exactly RythmRun's pattern: process each fix in the callback, write it, return.
- Android vitals counts partial wake locks "held when the app is in the background **or is running a foreground service**"; it exempts wake locks *created by* the audio/location/JobScheduler APIs (i.e., the system's `*location*` locks), **not an app's own lock**; "2 or more hours in a 24-hour period" is excessive and ">5% of app sessions … in a 28-day period … can affect your app's visibility on Play" [S19]. Play began applying store treatments for this in March 2026 [S21]. A fitness app that holds a lock for every multi-hour workout is precisely the profile that trips it.
- What a wake lock would buy: precise Dart timers (1-s elapsed tick, 5-s heartbeat) while the CPU would otherwise sleep between fixes. Neither needs it: elapsed time is wall-clock derived (`provider:720-740`), and the heartbeat's only job is bounding unknown downtime — between fixes there are no accepted points to lose, and each fix wakes the process. **[inferred]**
- Where a wake lock might still be needed: an OEM that stalls fused updates for a sleeping process even with a running location FGS. That is a device finding, not an assumption. If it occurs, prefer (a) checking that the OEM has not demoted the FGS (`dumpsys activity services`), (b) a *timed* `PARTIAL_WAKE_LOCK` acquired in the location callback for the duration of the write (seconds) — invisible to the 2 h threshold, (c) only as a last resort a continuous lock, gated by a per-device decision, documented as such.
- geolocator's `enableWakeLock` (option A) is an untimed continuous lock (`geo/GeolocatorLocationService.java:194-204`) — another reason not to use option A.
- The dominant battery cost is `PRIORITY_HIGH_ACCURACY` GPS at a 5 s interval, not the wake lock. The matrix (§12, T-20) measures mAh/hour with `dumpsys batterystats`; the interval and `setMaxUpdateDelayMillis` batching are the levers, constrained by the ≤5 s loss objective and the 12,000-point sync cap (GPS audit F14).

---

## 7. Notification-action state machine (Flutter UI may be absent)

Rules that hold in every state: the notification exists **only while** `WorkoutTrackingService` is in the foreground; its content is derived from **committed** durable state; every action is idempotent against that state (a duplicate, late, or wrong-state action is a no-op that leaves the notification untouched); actions never start an Activity (trampoline rule); the body tap opens `MainActivity` and, in Dart, only navigates when the current user owns a live or orphan checkpoint; the notification never contains coordinates, fix timestamps, or route shape.

| State | Durable truth | Notification (channel `workout_tracking`, LOW, public) | Actions | Body tap | Leaves state on |
| --- | --- | --- | --- | --- | --- |
| **starting** | checkpoint `starting` | "Starting workout…" (must be posted immediately at `startForeground`; no chronometer) | none | opens Track tab | `started` + GPS up ⇒ **active**; any failure ⇒ service stopped, checkpoint deleted, notification removed, in-app error |
| **active** | `active`, `last_flushed_at` ≤ 5 s old | "RythmRun · Running — Tracking · 3.2 km", chronometer from `now − activeElapsed`; `setOngoing`, `FOREGROUND_SERVICE_IMMEDIATE`, silent | **Pause**, **Finish** | opens Track tab | Pause ⇒ **paused**; Finish ⇒ **finishing**; location error/services off ⇒ **paused (locationUnavailable)** with `interrupted` event; permission revoked ⇒ process killed ⇒ **recoverable**; Task Manager Stop / force-stop / OEM kill ⇒ **recoverable**; logout/switch ⇒ D-011 dialog in app (headless: no change until the user decides) |
| **paused** | `paused`, `pause_started_at` set; GPS stream stopped; **service kept** | "Paused · 3.2 km · 00:23:15" (static); variant "Paused — location unavailable" | **Resume**, **Finish** | opens Track tab | Resume ⇒ **active** (GPS restarted from inside the running FGS — no background FGS start; first point anchors 0 m); Finish ⇒ **finishing** |
| **finishing** | `finishing`; metrics recomputed from durable rows | "Saving workout…" | none (actions removed so a double-tap cannot re-enter) | opens Track tab | commit ⇒ **completed**; failure ⇒ **recoverable (finishing)** — service stopped, checkpoint kept, one *regular* (non-FGS) notification "Workout not saved yet — open RythmRun" if notifications are enabled, else nothing (recovery card shows at next launch) |
| **completed** | `workouts` row exists, checkpoint deleted | none — `stopForeground(REMOVE)` + `stopSelf()`; no "saved" toast notification (avoid a second notification) | — | — | terminal; repeated Finish/actions are no-ops (`workouts` row found by `(user_id, client_sync_id)`) |
| **recoverable** (derived at next launch, not stored) | orphan checkpoint for the current user in `starting/active/paused/finishing`; process was dead or the service is a zombie | **none** — never auto-post, never auto-resume; `stopIfRunning()` clears a zombie service | — | — | Recovery card: **Resume** (visible Start of the FGS again) / **Finish** (at last durable boundary) / **Discard** (confirm) |

Cross-cutting events:

| Event | Expected handling |
| --- | --- |
| Notification dismissed by the user (13+/14+ default) | Service and tracking continue; `deleteIntent` fires ⇒ Dart records `notificationDismissed`; **re-post only on the next state transition** (Pause/Resume/Finish) — no periodic re-posting; the Track screen remains the authoritative control surface. **[doc]** dismissibility [S11]; re-post behaviour **[unknown]** — T-11 verifies |
| Notification permission denied / channel muted | Workout starts; Track screen says once per workout that shade controls are unavailable; FGS visible in Task Manager only [S4] |
| Task Manager **Stop** | Whole app removed, no callback [S7]; checkpoint ≤5 s stale; next launch ⇒ recovery card; optional `ApplicationExitInfo.REASON_USER_REQUESTED` privacy-safe count |
| Swipe from Recents (`onTaskRemoved`) | Service keeps running (`stopWithTask` default false); cached engine keeps the isolate; **on Xiaomi/Oppo-class devices expect a kill** ⇒ recoverable (T-04) |
| Reboot | No `BOOT_COMPLETED` receiver by design ⇒ recoverable at next launch |
| Runtime location permission revoked mid-workout | Process terminated by the platform [S10] ⇒ recoverable; on relaunch the permission gate shows before Resume |
| Location services turned off | `getServiceStatusStream` ⇒ auto-pause + `interrupted`; notification "Paused — location unavailable" with Resume/Finish; turning services back on does **not** auto-resume |
| Battery Saver / Restricted state entered mid-workout | Not observable as an event; detected at Start and shown as a warning; if the OEM demotes the FGS the outcome is a kill ⇒ recoverable |
| Voluntary logout / account switch while a notification exists | D-011 dialog (Finish or Discard) inside the app; teardown stops the service **before** `invalidateUserState`; user B never sees A's notification |
| Debug hot restart | `stopIfRunning()` at isolate start kills the zombie service; recovery card appears |

Optional (maintainer decision, proposal §11 item 5): two-tap Finish inside the notification.

---

## 8. Backgrounding, screen-off, swipe-away, reboot, force-stop, Task Manager — expected outcomes

| Scenario | Today (`d0e5b92`) | With the amended design | Evidence class |
| --- | --- | --- | --- |
| Home button / other app in front | Activity invisible ⇒ location no longer "foreground" ⇒ updates stop (fused client is app-context, so a few may still arrive briefly); timer keeps counting; the process is an ordinary cached background process that Android may freeze or kill **[inferred]** | FGS keeps foreground-location capability; updates continue | **[doc]** [S8]; today's exact cadence **[unknown]** |
| Screen off (locked) 30+ min | As above; route ends, time continues; on return the >30 s gap becomes a zero-distance bridge | Continues; per-point writes; battery per §6 | **[doc]** + **[unknown]** OEM |
| Swipe from Recents | Activity + engine destroyed ⇒ workout lost | Stock: service + cached engine survive; Xiaomi/Oppo-class: likely killed ⇒ recoverable | G-05; **[community]** |
| Task Manager Stop (13+) | App killed ⇒ workout lost | Recoverable ≤5 s loss | [S7] |
| Force-stop / OEM kill / OOM | Lost | Recoverable | [S7]-like; **[unknown]** frequency |
| Reboot | Lost | Recoverable; no auto-resume | IP-3.3 policy 6 |
| Restricted battery state | Foreground-only anyway | FGS demoted when backgrounded ⇒ tracking stops ⇒ recoverable; **must warn at Start** (C2) | [S13] |
| Battery Saver on | Depends on device mode | 12+ `FOREGROUND_ONLY`: continues with screen off; other modes: **[unknown]** per device | [S14] |
| Doze while stationary (long stop without Pause) | n/a | Motion sensor keeps a moving device out of deep Doze; a stationary 30+ min stop may enter it — measure; Pause stops GPS anyway | **[inferred]** |

---

## 9. Permission edge cases

| Case | Platform behaviour | App today | Required handling |
| --- | --- | --- | --- |
| **Approximate location** granted (12+) | App gets ~3 km estimates regardless of declared permissions; "your app should still work" [S8] | Counted as granted (`service:56-62`); every fix fails the 50 m accuracy ceiling ⇒ silent empty workout | `Geolocator.getLocationAccuracy()` at Start; on `reduced` block Start with "Precise location is required to record a route" + an upgrade request (`requestPermission` again shows the precise toggle) or app-settings link. Never start a workout that cannot accept points |
| **"Only this time"** (11+) | Valid while an Activity is visible, briefly after backgrounding, or "until the foreground service stops" if the FGS was launched while visible; revocation "terminates" the process [S10] | Foreground-only, so it lapses shortly after backgrounding | Start the FGS while visible ⇒ the grant lasts the whole workout; next Start prompts again — acceptable |
| **Revoked in Settings mid-workout** | Process terminated [S10] | Workout lost | Checkpoint ⇒ recovery card; on relaunch the permission gate precedes Resume; the notification vanished with the process — nothing to clean |
| **Permanently denied** | Dialog will not show again | Button cannot open settings (G-10) | `Geolocator.openAppSettings()`; keep the truthful copy |
| **GPS / location services disabled mid-workout** | Provider stops delivering; geolocator surfaces a service-status change and/or stream error | Message only (G-11) | Auto-pause + `interrupted`; Resume requires services on (the existing `requestLocationService` dialog) |
| **Notification permission denied** (13+) | FGS still allowed; drawer hides it; Task Manager shows it [S4] | n/a | Start anyway; honest copy; `areNotificationsEnabled()` for truthfulness; offer settings link, never gate |
| **Notification channel muted later** | Notification hidden; service continues | n/a | Same as denied |
| **Restricted battery** (9+) | FGS removed from foreground when the app leaves the screen [S13] | n/a | Warn at Start; do not claim background tracking; recovery |
| **Battery Saver** | Location mode device-specific; 12+ `FOREGROUND_ONLY` fine [S14] | n/a | Read and warn when the mode is not foreground-friendly (`getLocationPowerSaveMode()`), otherwise say nothing |
| **Auto-reset of unused app permissions** | Location permission may be reset after months of non-use | Handled by the normal permission gate | None beyond the gate |

---

## 10. Google Play policy and disclosure

| Item | Requirement | Status / action | Evidence |
| --- | --- | --- | --- |
| Foreground service declaration | Apps targeting 14+ that use FGS types must, per type, "Provide a description of the app functionality", "Describe the user impact if the task is deferred … and/or interrupted", "Include a link to a video demonstrating each foreground service feature", and pick a use case; `TYPE_LOCATION` is covered ("user-initiated location sharing, navigation…"); use must be user-perceptible — "Users can be considered aware if they initiate the action themselves" [S15] | Becomes mandatory the moment `FOREGROUND_SERVICE_LOCATION` is declared (PR-4a). **Maintainer action in Play Console → App content → Foreground service permissions.** Video: Start → lock screen → notification with controls → Finish. Note the merged manifest already contains two plugin `location`-type services; the console may already list them | [S15] **[doc]** |
| Background location declaration & prominent disclosure | Required only when `ACCESS_BACKGROUND_LOCATION` is in the manifest [S22]; FGS is permitted when "initiated as a continuation of an in-app, user-initiated action" and "terminated immediately after the application completes the intended use case" [S22] | Not requesting ABL keeps the app out of that review; the design satisfies both FGS conditions by construction (Start/Resume are user actions; Finish/Discard/teardown stop the service). **Do not** add ABL for OEM-kill workarounds — it would not help and would trigger the review | [S22] **[doc]** |
| Data safety form | Location (precise) collected, purpose "app functionality", stored on device and (when synced) on the server | Confirm the existing entry still describes background collection during a workout accurately | maintainer **[unknown]** |
| Privacy policy (`docs/privacy-policy.md`, public legal text) | Engineering supplies the fact: location is recorded in the background **only** while a workout the user started is running, indicated by a persistent notification; no ABL | Record the fact for IP-5.6; **do not edit** the page in an engineering change | CLAUDE.md doc rules |
| Battery / wake locks | Vitals excessive-partial-wake-lock threshold and store treatments [S19][S21] | Follow C1 | **[doc]** |
| Target API | targetSdk 36 is at the current ceiling; the 2026 Play target-API deadline text was **not** verified here | none | **[unknown]** |

---

## 11. Compatibility risks of the current Flutter / geolocator setup

| Risk | Detail | Evidence |
| --- | --- | --- |
| geolocator 14.0.2 / geolocator_android 5.0.3 as the position source | Fine: `LocationRequest.Builder` on 33+, deprecated builder below; `PRIORITY_HIGH_ACCURACY`; app-context fused client (survives Activity loss while the engine lives). Its *foreground mode* is not fit for controls (§5) and its `startForeground` passes no explicit type (uses the manifest type — legal, but any future second type would need care) | `geo/location/FusedLocationClient.java:97-113`; `geo/GeolocatorLocationService.java:147` **[plugin]** |
| geolocator's `IMPORTANCE_NONE` channel (only if option A were used) | Contradicts the "notification priority PRIORITY_LOW or higher" requirement for FGS notifications; on 8–12 the system may show its own "running in the background" notice; on 13+ likely Task-Manager-only | `geo/location/BackgroundNotification.java:69`; [S9] **[plugin][doc][inferred]** |
| Permission model conflates coarse and fine | G-09 | **[plugin][code]** |
| Two plugin `location`-type services in the merged manifest | Harmless at runtime while unused; visible to Play/App-content tooling; the `location` plugin exists only for one dialog | **[plugin]** |
| Transitive `androidx.work:work-runtime:2.7.0` (via GMS ads/measurement): adds `WAKE_LOCK`, `FOREGROUND_SERVICE`, `SystemForegroundService` without a type, a disabled `BOOT_COMPLETED` receiver | The app schedules no WorkManager work, so nothing runs; but the permissions the FGS relies on must be declared by the app, not inherited; and if the ads SDK ever ran foreground work on 34+ it would be its problem, not ours. Note for the Play FGS declaration | merged debug manifest `:65-66,266-281,327-336`; merger report `:760-767` **[code]** |
| Cached-engine change interacts with every `ActivityAware` plugin (geolocator `setActivity(null)` on detach, image_picker, url_launcher, google_sign_in, ads) | Activity-bound operations must only be invoked while attached (they are: all are user-initiated on screen); position updates do not need the Activity | `geo/GeolocatorPlugin.java:120-126` **[plugin][inferred]** |
| Toolchain bump (Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20) never built | Any Kotlin FGS work sits on an unproven build; PR-0 first | STATUS **[code]** |
| Predictive back on by default for target 36 | Flutter 3.44's embedding is expected to handle it; the app uses `PopScope(canPop:false)` in the exit dialog — verify back-gesture behaviour in PR-0 | [S16]; `main:230-231` **[inferred]** |
| Play 16 KB page-size requirement (target 35+) and native libs (`jni` package brings `libdartjni.so`) | Out of this audit's scope; the last release (`1.2.0+21`) presumably passed Play's check — not verified here | **[unknown]** |

---

## 12. Physical-device test matrix

**Devices (minimum):** D1 Pixel on Android 15 or 16 (stock; also the target-36 reference); D2 Samsung Galaxy on One UI 6/7 (Android 14/15) with default battery settings; D3 one Xiaomi/Redmi/POCO (HyperOS) **or** OnePlus/Oppo (ColorOS/OxygenOS); D4 (if available) an Android 8–9 device for the API 26–28 code paths (`startService`, no type, no `POST_NOTIFICATIONS`); an emulator may cover D4's API-path checks only, never OEM rows. Record device model, OS build, Play services version, app build, plugin versions in the IP-3 evidence log; capture `adb logcat` (scanned for coordinates/timestamps of fixes — must be absent), `dumpsys activity services <pkg>` (must show `foregroundServiceType=location`), `dumpsys notification --noredact | grep <pkg>`, and `dumpsys batterystats --charged <pkg>` for T-20.

| ID | Scenario | Steps | Expected | Devices |
| --- | --- | --- | --- | --- |
| T-01 | Baseline screen-on 20 min walk | Start, walk, Pause 2 min, Resume, Finish | Correct metrics; one completed row; notification present with correct state throughout | D1–D3 |
| T-02 | Screen off ≥ 30 min | Start, lock screen, walk/run 30 min, unlock, Finish | Notification visible with running chronometer; route continuous within policy rules; heartbeat gaps ≤ 5 s in the checkpoint; no `>30 s` zero-bridge segments | D1–D3 |
| T-03 | Multi-hour (2–3 h), screen mostly off | As T-02 for 2–3 h with two pauses | Same; memory/frame stable (IP-3.5); battery per T-20 | D1, D2 |
| T-04 | Swipe from Recents while active | Start, background, swipe away, wait 5 min, reopen | Stock: tracking continued, same in-memory screen; OEM D3: either continued or **recovery card with interruption at last heartbeat** — no silent lie | D1–D3 |
| T-05 | Task Manager Stop | Start, lock, open shade, Stop RythmRun, relaunch | Recovery card offers Resume/Finish/Discard; interruption at last heartbeat; no auto-restart | D1–D3 (13+) |
| T-06 | `adb shell am force-stop <pkg>` at each boundary (`starting`, active with points, paused, `finishing`) | Per IP-3.3 | Deterministic reconciliation; one checkpoint or one completed row | D1 |
| T-07 | Reboot mid-workout | Start, reboot, relaunch | Recovery card; no service after boot | D1, D2 |
| T-08 | Notification actions with the app backgrounded, destroyed (swiped), and after a cold start (should not exist) | Pause/Resume/Finish from the shade and the lock screen; rapid double taps; Pause then Resume within 1 s | Idempotent single transitions; Finish while destroyed yields one completed row; no duplicate task; lock-screen actions work with public visibility | D1–D3 |
| T-09 | Body tap: app in background / destroyed / process dead | Tap notification body | Same task brought to front (`dumpsys activity activities` shows one task); Track tab; cold start ⇒ recovery card | D1–D3 |
| T-10 | Notification permission denied / channel muted | Deny at first Start; later mute channel | Workout starts; honest copy once; FGS visible in Task Manager only; no crash | D1 (13+) |
| T-11 | User dismisses the FGS notification | Swipe it away while active; then Pause from the app | Tracking continues; notification re-appears on the next transition; no periodic re-posting | D1, D2 (13+/14+) |
| T-12 | Approximate-only grant | Grant approximate at first prompt | Start blocked with upgrade prompt; after precise grant Start works | D1 (12+) |
| T-13 | "Only this time" grant | Grant once, Start, lock 10 min | Tracking continues for the workout; next Start prompts again | D1 (11+) |
| T-14 | Runtime location permission revoked mid-workout | Revoke in Settings during T-02 | Process terminated; relaunch shows permission gate then recovery card | D1 |
| T-15 | Location services toggled off, then on | During active | Auto-pause "location unavailable"; Resume works from the shade without reopening the app | D1–D3 |
| T-16 | Battery Saver on | Enable before Start; screen off 20 min | Record `getLocationPowerSaveMode()`; on `FOREGROUND_ONLY` tracking continues; otherwise document the honest warning and outcome | D1–D3 |
| T-17 | Restricted battery state | Set app battery to Restricted; Start; lock 10 min | Warning shown at Start; document whether the FGS is demoted (`dumpsys activity services`) and that recovery follows | D1–D3 |
| T-18 | OEM defaults | D2: app unused 3+ days before the run; D3: default autostart/battery settings, then with the recommended settings | Record kills and their timing; recovery card after any kill; write the vendor settings that made the difference into the help text | D2, D3 |
| T-19 | Airplane mode + reconnect; Do Not Disturb | During T-02 | Recording uninterrupted; sync stays queued; DND does not hide the ongoing notification | D1 |
| T-20 | Battery cost | `dumpsys batterystats --reset`; T-02; `dumpsys batterystats --charged <pkg>` | mAh/h, GPS time, wake-lock time (app-attributed vs `*location*`) recorded; used to decide interval/batching and whether any wake lock is ever needed | D1–D3 |
| T-21 | Zombie service (debug hot restart) | Hot restart during active | Service stopped at isolate start; recovery card | D1 |
| T-22 | Privacy scan | `logcat` + `dumpsys notification` after any run | No coordinates, fix timestamps, or route shape; only stable codes | all |
| T-23 | API 26–28 path | Emulator or D4 | `startForegroundService` on 26+, channel, `FOREGROUND_SERVICE` on 28; API 24–25 `startService` path (emulator acceptable for API paths only) | D4/emulator |

Acceptance for IP-3.4 (from the phase file): a visible service runs during tracking; route and checkpoints continue under screen-off within documented accuracy/battery bounds; every kill lands in recovery. Emulator-only evidence is insufficient.

---

## 13. Staged implementation plan (small PRs) with rollback conditions

Sequenced to keep every intermediate state honest: nothing claims background tracking before the service exists, and no service exists before durable checkpoints do. This is the proposal's §8 with the amendments of §0.4 folded in.

| PR | Package | Content | User-visible change | Verification | Rollback condition |
| --- | --- | --- | --- | --- | --- |
| **PR-0** | IP-3.4 item 1 | Toolchain proof only: debug + **release** configuration/build on Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 (a debug manifest merge already ran locally on 2026-08-11 but was never recorded — record it and add the release half); note `proguard-rules.pro` and predictive-back/edge-to-edge findings; keep the merged release manifest as evidence of the transitive permission set | none | build logs; `flutter build apk --release` (ads off); merged manifest diff | If the build fails: fix the toolchain first; nothing else proceeds |
| **PR-1** | IP-3.1 | SQLite v7 checkpoint tables + indexes + `sequence` backfill + `_onOpen` checks + teardown clearing; DAO with no production caller | none (schema bump) | FFI migration tests v1–v6→v7; `foreign_key_check` | Forward-only schema; revert = ship nothing on top; never a lower-version binary |
| **PR-2a** | IP-3.1 | `ActiveWorkoutEngine` (durable start/pause/resume, per-point write, heartbeat, snapshots), notifier as adapter, GPS stopped on Pause, `getServiceStatusStream` auto-pause (C5), approximate-location check (C4), `openAppSettings` for `deniedForever` (G-10), skip sync while a workout is active | Workouts are checkpointed; background still unsupported and **not claimed** | engine tests with fake clock/stream/DAO/channel | Behavioural regression in `flutter test` or MC-1.5 re-run ⇒ revert; checkpoints stay |
| **PR-2b** | IP-3.2 | Finalize-exactly-once, `finishing` reconciliation, discard, sync-after-commit; **`SYNC-01` (a)+(b) lands with or before this** | Finish durable across kills | failure-injection via wrapping `DatabaseFactory` | Any injected boundary yielding neither/duplicate rows ⇒ block release |
| **PR-3** | IP-3.3 | Startup reconcile after `activateUserScope`, orphan policy, recovery card Resume/Finish/Discard, teardown counts orphans, corrupt-row error | Recovery UI after kills | kill/reopen matrix (T-06 subset); teardown tests | Recovery offering the wrong user's data or auto-resuming ⇒ revert PR-3 only |
| **PR-4a** | IP-3.4 | Manifest (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`; service + receiver stubs), `WorkoutTrackingService` (no actions yet), `WorkoutServicePlugin`/`WorkoutServiceChannel`, cached engine + conditional destroy, `POST_NOTIFICATIONS` request + honest copy, `isBackgroundRestricted`/battery-saver/notification-enabled honesty inputs (C2), **no wake lock** (C1), `AndroidSettings` with explicit interval, small icon, `startFailed` fail-closed, zombie reconcile | Screen-off tracking with an honest notification | Dart tests with fake channel; device T-01/T-02/T-04/T-05/T-10/T-16/T-17/T-22 on D1 at least | `startForeground` failure on any matrix device that is not explained by a detected state ⇒ hold rollout; a "tracking" UI ever shown without `started` ⇒ block; PR-4a reverts independently (engine + recovery keep working) |
| **PR-4b** | IP-3.4 | Receiver + action `PendingIntent`s, `onNotificationAction`, chronometer/paused rendering, `deleteIntent` handling (C3), body tap → `onOpenWorkout`, optional two-tap Finish | Shade controls | engine idempotency tests; device T-08/T-09/T-11/T-15 | Duplicate transitions or a second task ⇒ revert PR-4b only (notification remains, controls gone) |
| **PR-5** | IP-3.4 evidence | `integration_test/` + `tool/device_test/` scripts (`am force-stop`, `input keyevent KEYCODE_SLEEP`, `dumpsys`, `logcat` scan); full §12 matrix; IP-3 evidence log; STATUS; new `MC-3.x` items (Play declaration, privacy fact, matrix) | none | the matrix | Matrix failures on D2/D3 that no in-scope mitigation fixes ⇒ document the OEM as "recovery-only", or evaluate fallback B — a maintainer decision, not a silent downgrade |
| **PR-6** (optional) | IP-3.4 | In-app "Keep tracking reliable" help text with vendor settings names (no vendor intents), shown only after a detected kill/interruption | Help copy | widget test | Pure UI; revert |

Kill switch: none by default (proposal §10). If the maintainer wants one it must **block Start with a message**, never fall back to memory-only tracking (IP-3 rollback plan).

---

## 14. Items requiring maintainer approval, Play Console action, or physical-device evidence

**Maintainer approval (before PR-1/PR-4a):**

1. Adopt option C (own minimal Kotlin FGS + cached engine) with amendments C1–C7; keep B (`flutter_foreground_task`) as the fallback only if C fails the matrix.
2. **No continuous wake lock** by default (C1); any wake lock later is timed and justified by a device finding.
3. Approximate-only grants block Start with an upgrade prompt (C4) rather than recording an empty workout.
4. Auto-pause with `interrupted` on location-services-off (C5); no auto-resume.
5. Notification dismissal policy: re-post on transitions only (C3).
6. `POST_NOTIFICATIONS` requested at first Start; `permission_handler` (already in the lockfile) vs ~15 lines of Kotlin.
7. Whether to show battery-state warnings (Restricted / Battery Saver) as blocking or advisory (recommended: advisory, with the honest consequence spelled out).
8. Optional two-tap Finish; optional `ApplicationExitInfo` count; optional OEM help page (PR-6).
9. Confirm the phase-file position: IP-3.4 remains gated on IP-3.1–3.3 (no service before checkpoints).

**Play Console actions (maintainer only):**

10. App content → **Foreground service permissions**: declare `location` with description, deferral/interruption impact, use case, and a demo video (once PR-4a is in a release track) [S15].
11. Confirm the Data safety location entry still describes collection during a workout accurately.
12. Confirm no `ACCESS_BACKGROUND_LOCATION` declaration is triggered (there must be none).
13. Supply the verified fact for `docs/privacy-policy.md` wording (background recording only during a user-started workout, shown by a persistent notification) — maintainer decides the wording (IP-5.6).

**Physical-device evidence (nothing in this audit is proven without it):**

14. The §12 matrix on at least D1 (Pixel), D2 (Samsung), D3 (Xiaomi/OnePlus-class), with recorded device/OS/plugin versions — becomes `MC-3.x` items in `ACTION-REQUIRED.md`.
15. T-20 battery numbers to fix the interval/batching decision and to confirm no wake lock is needed.
16. T-09 task-reuse with `taskAffinity=""`, T-11 re-post after dismissal, T-16/T-17 platform-state behaviour — the three places where this audit's expectations are inferred rather than documented.

---

## 15. Sources

Official Android / Google Play pages read on 2026-08-17 (quotes above are from these pages):

- [S1] Android — [Changes to foreground services](https://developer.android.com/develop/background-work/services/fgs/changes) (per-version list: 9 `FOREGROUND_SERVICE`; 10 `location` type; 12 background-start restriction; 14 types + type permissions, `SecurityException`; 15 timeouts/`BOOT_COMPLETED`/`SYSTEM_ALERT_WINDOW`; 16 job quotas from FGS).
- [S2] Android — [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types) (`location`: `FOREGROUND_SERVICE_LOCATION`, `FOREGROUND_SERVICE_TYPE_LOCATION`, runtime prerequisites, while-in-use note).
- [S3] Android — [Restrictions on starting a foreground service from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start) (`ForegroundServiceStartNotAllowedException`; exemptions incl. "The user performs an action on a UI element … notification"; while-in-use section; exemptions incl. "The service starts by interacting with a notification").
- [S4] Android — [Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission) (FGS without `POST_NOTIFICATIONS`; Task Manager only when denied; off by default for new installs targeting 33+).
- [S5] Android — [Android 12 behavior changes: all apps](https://developer.android.com/about/versions/12/behavior-changes-all) ("can delay the display of foreground service notifications by 10 seconds, with a few exceptions"; approximate location).
- [S6] Android — [Android 12 behavior changes: apps targeting 12](https://developer.android.com/about/versions/12/behavior-changes-12) (`PendingIntent` mutability; notification trampolines; approximate location).
- [S7] Android — [Handle user-initiated stopping of apps running foreground services](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping) (Task Manager Stop behaviour; no callbacks; `REASON_USER_REQUESTED`).
- [S8] Android — [Request location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions) (foreground = visible Activity **or** running FGS, "turns their device's display off"; `foregroundServiceType="location"` required on 10+; background = "any situation other than"; approximate/precise; Battery-Saver note under "Foreground location").
- [S9] Android — [Launch a foreground service](https://developer.android.com/develop/background-work/services/fgs/launch) (notification priority `PRIORITY_LOW` or higher; `ServiceCompat.startForeground`).
- [S10] Android — [Request runtime permissions](https://developer.android.com/training/permissions/requesting) (one-time permissions; "if the user revokes your app's one-time permission, your app's process terminates").
- [S11] Android — [Android 13 behavior changes: all apps](https://developer.android.com/about/versions/13/behavior-changes-all) (FGS notifications dismissible; Task Manager; `POST_NOTIFICATIONS`) and [Android 14 behavior changes: all apps](https://developer.android.com/about/versions/14/behavior-changes-all) (`FLAG_ONGOING_EVENT` dismissible; exceptions).
- [S12] Android — [Services overview](https://developer.android.com/develop/background-work/services) ("Starting a service": "Once the service has been created, the service must call its startForeground() method within five seconds").
- [S13] Android — [Background optimization / user-initiated restrictions](https://developer.android.com/topic/performance/background-optimization) ("Can't launch foreground services / Existing foreground services are removed from the foreground"; temporary unrestriction while the user interacts).
- [S14] Android — [Request location permissions (Battery Saver note)](https://developer.android.com/develop/sensors-and-location/location/permissions?hl=en) (`getLocationPowerSaveMode()`, `LOCATION_MODE_FOREGROUND_ONLY`, "even if the screen is off") and [Power management resource limits](https://developer.android.com/topic/performance/power/power-details) (App state / Device state tables).
- [S15] Google Play — [Understanding foreground service and full-screen intent requirements](https://support.google.com/googleplay/android-developer/answer/13392821) (App content declaration: description, deferral impact, video; `TYPE_LOCATION`; user-perceptible).
- [S16] Android — [Android 16 behavior changes: apps targeting 16](https://developer.android.com/about/versions/16/behavior-changes-16) (no FGS/location/notification restriction; predictive back; edge-to-edge; large-screen orientation; health permissions).
- [S17] Samsung Developers — [App management](https://developer.samsung.com/mobile/app-management.html) (sleeping / deep sleeping apps; "Job, Alarm, and Foreground-service are restricted"; Background usage limits).
- [S18] dontkillmyapp.com — [Samsung](https://dontkillmyapp.com/samsung), [Xiaomi](https://dontkillmyapp.com/xiaomi) and OEM pages — **community-maintained, not vendor documentation**.
- [S19] Android — [Excessive partial wake locks (Android vitals)](https://developer.android.com/topic/performance/vitals/excessive-wakelock) (2 h/24 h; counts in background **or running a foreground service**; exempts wake locks created by audio/location/JobScheduler APIs; >5 % of sessions over 28 days affects Play visibility).
- [S20] Android — [Identify wake locks](https://developer.android.com/develop/background-work/background-tasks/awake/wakelock/identify-wls) (location APIs' wake locks attributed to the app; "Avoid acquiring a separate, continuous wake lock … the system automatically triggers a device wake-up during the location event callback").
- [S21] Android Developers Blog — [Battery technical quality enforcement is here](https://developer.android.com/blog/posts/battery-technical-quality-enforcement-is-here-how-to-optimize-common-wake-lock-use-cases) (store treatments rolling out from 2026-03-01).
- [S22] Google Play — [Understanding location in the background permissions](https://support.google.com/googleplay/android-developer/answer/9799150) (foreground vs background definition; FGS conditions "continuation of an in-app, user-initiated action" / "terminated immediately after"; declaration triggered by `ACCESS_BACKGROUND_LOCATION` in the manifest; prominent disclosure).
- [S23] Android — [About background location and battery life](https://developer.android.com/develop/sensors-and-location/location/battery) (Android 8.0: "Background location gathering is throttled and location is computed, and delivered only a few times an hour").

Plugin sources read locally: `geolocator_android-5.0.3` (`GeolocatorLocationService.java`, `GeolocatorPlugin.java`, `StreamHandlerImpl.java`, `location/BackgroundNotification.java`, `location/FusedLocationClient.java`, `location/LocationOptions.java`, `permission/PermissionManager.java`, `location/LocationAccuracyManager.java`, `AndroidManifest.xml`, `lib/src/types/android_settings.dart`), `location-7.0.1/android/src/main/AndroidManifest.xml`, `permission_handler_android-13.0.1`, `flutter_foreground_task-10.0.0` (manifest, `service/ForegroundService.kt`, `models/ForegroundServiceTypes.kt`), `flutter_background_service_android-6.3.1/android/src/main/AndroidManifest.xml`, plus the manifests of `connectivity_plus-6.1.5`, `google_mobile_ads-5.3.1`, `google_sign_in_android`, `sqflite_android-2.4.3`, `flutter_secure_storage-10.3.1`, `package_info_plus-9.0.1`.

---

## Appendix A — explicitly not verified here

- No build, test, emulator, device, CI, staging, production, or Play Console access. Every runtime statement is documentation- or source-inferred and labelled. The merged **debug** manifest artifact was read as found on disk; its build was not reproduced and the **release** merge may differ.
- Two sibling audits written the same day (`battery-durability-audit.md`, `gps-route-quality-audit.md`) were noticed in the working tree only after this document was drafted and were not used as sources; where they overlap (no default wake lock, GPS off on pause, the transitive `FOREGROUND_SERVICE`/`WAKE_LOCK`) the conclusions were reached independently from the same evidence.
- The 10-second-delay **exemption list** (`FOREGROUND_SERVICE_IMMEDIATE`, action buttons, specific types/categories) is quoted from platform knowledge of the `Notification` API reference; the delay itself is quoted from [S5]. Confirm on the reference page before relying on action buttons alone.
- The exact `PowerManager` API levels of the location power-save constants; the doc statement used is "Beginning with Android 12" [S14].
- Whether re-posting a dismissed FGS notification via `notify()` re-surfaces it on 13+/14+ (T-11).
- Whether `taskAffinity=""` + a launcher-style content intent reuses the running task on every OEM (T-09).
- Actual OEM kill behaviour, Battery-Saver modes, Doze effects, battery cost, and the need (if any) for a timed wake lock (T-16, T-17, T-18, T-20).
- The current Play Console App-content and Data-safety entries for RythmRun, and the 2026 Play target-API deadline.
- The Flutter embedding claims about `FlutterFragmentActivity` engine caching are taken from the design proposal's `javap` inspection; they were not re-derived here.
