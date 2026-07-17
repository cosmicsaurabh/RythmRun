---
published: false
---

# RythmRun–Samsung Health integration plan

- **Status:** Conditional go for one-way workout export through Health Connect
- **Document date:** 2026-07-16
- **Owner:** RythmRun engineering
- **Intended audience:** Product, engineering, privacy, security, QA, and release reviewers
- **Decision review trigger:** Any change to Samsung Health Data SDK eligibility, Samsung Health–Health Connect synchronization, Android Health Connect permissions or policy, the Google Play Health Apps declaration, or RythmRun's intended read/write scope

> This is an implementation and product plan, not legal advice. Health-platform behavior and store policy change over time. Re-check the cited official sources, installed SDK versions, and Play Console requirements immediately before implementation and again before release.

## Executive decision

RythmRun can integrate with Samsung Health on Android. The recommended production path is:

> RythmRun writes a completed, RythmRun-recorded workout to Android Health Connect. Samsung Health can then retrieve that workout if the user has separately enabled Samsung Health's Health Connect connection and granted Samsung Health the relevant read permissions.

This is technically feasible with the current Flutter application and does not require a RythmRun backend API, OAuth, a Samsung token, or a webhook. It is an on-device Android integration.

The first release should be deliberately narrow:

- Android only;
- RythmRun-to-Health Connect export only;
- manual sharing first;
- optional automatic sharing only after a pilot;
- only RythmRun-origin workouts;
- no Samsung Health or Health Connect import;
- no background or history read permissions;
- no medical data; and
- no claim that Samsung Health has consumed a record.

The trustworthy success message is **Shared with Health Connect**, not **Synced to Samsung Health**. RythmRun can know that Health Connect accepted its records. Health Connect exposes no acknowledgement that Samsung Health later read them.

There are two legitimate implementation paths:

1. **Android Health Connect — recommended MVP.** It is available without Samsung partnership approval, supports stable client-side idempotency, reaches Samsung Health and other compatible Android apps, and has official test tooling.
2. **Samsung Health Data SDK — partnership-gated alternative.** It writes directly to Samsung Health and documents a richer exercise model, including a route. Public distribution requires prior Samsung partnership approval plus registration of the package name and production signing certificate. Development-time writes also require an approved access code.

Run these two external-dependency tasks in parallel:

1. build a short physical-device Health Connect spike; and
2. submit a Samsung Health Data SDK partnership request if Samsung Health is a strategic integration.

Use Health Connect for production if the spike proves that session type, route, timing, distance, and deletion arrive acceptably in Samsung Health. If route or pause fidelity fails and Samsung approves the required write scope, reconsider the direct Data SDK behind the same RythmRun export abstraction. Never write the same workout through both paths; Samsung Health could ingest two copies.

Official decision sources:

- [Samsung: Accessing Samsung Health data through Health Connect](https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect)
- [Samsung Health Connect FAQ](https://developer.samsung.com/health/health-connect-faq.html)
- [Android Health Connect overview](https://developer.android.com/health-and-fitness/health-connect)
- [Health Connect availability](https://developer.android.com/health-and-fitness/health-connect/availability)
- [Health Connect 1.1.0 stable release notes](https://developer.android.com/jetpack/androidx/releases/health-connect)
- [Samsung Health Data SDK overview](https://developer.samsung.com/health/data/overview.html)
- [Samsung Health Data SDK app creation process](https://developer.samsung.com/health/data/process.html)

## Decision at a glance

| Question | Decision |
| --- | --- |
| Can RythmRun integrate? | Yes, conditionally |
| User-facing integration name | **Samsung Health via Health Connect** |
| Reliable receipt | **Shared with Health Connect** |
| Initial direction | RythmRun → Health Connect |
| Samsung Health path | Health Connect → Samsung Health, controlled by the user |
| Direct Samsung SDK | Partnership-gated fallback, not simultaneous |
| Backend work | None for the recommended MVP |
| OAuth, tokens, callbacks, webhooks | None |
| Production SDK | `androidx.health.connect:connect-client:1.1.0` stable |
| Runtime feature floor | Android 9 / API 28, Google Play services, non-work profile |
| Build-time SDK floor impact | Health Connect client supports API 26+, so RythmRun's current API 24 minimum would need review and likely elevation to 26 |
| MVP permissions | Write exercise, route, and distance; calories only after the semantic gate |
| Read permissions | None |
| Automatic history backfill | No |
| Source of truth | RythmRun local workout |
| Duplicate control | Stable `clientRecordId` plus monotonic `clientRecordVersion` |
| Core launch unknown | Samsung does not explicitly document `ExerciseRoute` synchronization |
| Release gate | Physical-device proof plus Play/privacy approval |

## What “Samsung Health integration” means

Three independent relationships are involved:

1. RythmRun receives permission to write selected record types to Health Connect.
2. Samsung Health separately receives permission to read selected record types from Health Connect.
3. Samsung Health decides when and how those records appear in its UI and synchronize with a paired Galaxy Watch or Samsung Cloud.

RythmRun controls only the first relationship.

The data path is:

```text
RythmRun workout stored in SQLite
        |
        v
RythmRun Health Connect exporter
        |
        v
Android Health Connect on-device store
        |
        | user separately enables Samsung Health read access
        v
Samsung Health on the smartphone
        |
        | Samsung-controlled synchronization timing
        v
Galaxy Watch / Samsung Cloud where applicable
```

Samsung states that Samsung Health has supported bidirectional Health Connect synchronization since Samsung Health 6.22.5. It also states that Galaxy Watch data reaches Health Connect indirectly through Samsung Health on the paired smartphone. Watch-to-phone timing can depend on reconnection, opening Samsung Health, or a manual refresh.

The product must not:

- label Samsung Health “connected” merely because it is installed;
- imply RythmRun can grant or inspect Samsung Health's permissions;
- promise immediate Samsung Health or Galaxy Watch appearance;
- promise that every Samsung Health version synchronizes the same fields; or
- use Samsung Health branding as if RythmRun were an approved direct partner.

## Relationship to the existing engineering program

This document does not supersede `docs/_engineering/improvement-plan/README.md` and does not authorize production enablement while that program's release blockers remain open.

Repository-only spike work can be selected independently. Public beta or production enablement must additionally wait for:

1. the applicable IP-0 deployment, containment, and incident gates;
2. Android migration and user-scope device evidence for the local database;
3. a real account-deletion flow;
4. revised privacy disclosures and Google Play Data safety answers;
5. the Google Play Health Apps declaration and permission approval;
6. physical-device Health Connect and Samsung Health acceptance evidence;
7. a minimum-SDK install-base decision;
8. evidence that health and route data do not reach advertising or unrelated analytics; and
9. closed-pilot rollback readiness.

The current Settings screen advertises account deletion but still ends in a “coming soon” path. That is a launch blocker because exported Health Connect records can only be removed on the Android device while RythmRun still has the necessary permissions.

Health-platform integration is listed as future work in the improvement program. It should not displace the lower-numbered security, identity, durability, restore, or deletion work unless the maintainer explicitly selects a contained spike.

## Goals

### MVP goals

1. Let an authenticated RythmRun user set up workout sharing with Health Connect on a supported Android phone.
2. Explain that Samsung Health needs its own Health Connect setup.
3. Let the owner manually share one completed RythmRun workout.
4. Write an exercise session with the correct workout type and original timestamps.
5. Write a filtered GPS route when route permission is granted and the route is valid.
6. Write distance when it is positive and permission is granted.
7. Preserve name and notes only after clear disclosure.
8. Use stable client IDs and versions so lost-response retries do not create duplicates.
9. Keep workout completion independent of Health Connect availability.
10. Store export and deletion state durably in owner-scoped SQLite.
11. Show provider, permission, partial-export, retry, and deletion states.
12. Let the user pause future sharing without silently deleting prior copies.
13. Let the user remove RythmRun-written records from Health Connect.
14. Stop and drain work safely during logout or account switch.
15. Operate without network connectivity.
16. Produce the Play, privacy, device, and test evidence needed for a controlled release.

### Post-pilot goal

Offer **Automatically share new workouts**. It must:

- default to off;
- apply only to workouts completed after opt-in;
- never silently backfill old history;
- use the same durable queue and idempotent record IDs;
- stop immediately when the account's local preference is disabled; and
- remain independent from RythmRun cloud synchronization.

### Partnership contingency goal

If Health Connect cannot meet the route, pause, or display acceptance criteria:

1. obtain Samsung partnership approval;
2. register the Play App Signing certificate and package name;
3. verify approved `EXERCISE` and `EXERCISE_LOCATION` write scope;
4. implement the Samsung Data SDK adapter behind the common export gateway; and
5. migrate only future exports unless a user explicitly requests a controlled re-export.

## Non-goals

The following are out of scope for the MVP:

- importing Samsung Health workouts;
- reading any Health Connect data type;
- importing Galaxy Watch heart rate, sleep, steps, blood oxygen, body composition, or medical data;
- historical backfill;
- bidirectional conflict resolution;
- background reads;
- history reads older than 30 days;
- route reads from other apps;
- creating steps from distance estimates;
- writing heart rate, cadence, power, VO2 max, or speed that RythmRun did not directly and reliably measure;
- making imported health data public or social;
- server-side Health Connect state;
- a Samsung cloud REST integration;
- claiming iOS Samsung Health support;
- writing the same workout through Health Connect and Samsung Data SDK;
- using exported or imported health data for advertising, profiling, AI, recommendations, or unrelated analytics; and
- treating a granted Android permission as consent for every RythmRun account used on that device.

## Integration option analysis

### Option A: Android Health Connect

Health Connect is an Android on-device health store. On Android 14 and later it is a system module. On Android 13 and lower the user installs or updates the Health Connect app from Google Play. The runtime requires Android 9/API 28 or later, Google Play services, and a normal phone user profile.

Advantages:

- no Samsung partnership dependency;
- supported by Samsung Health;
- reaches other compatible Android apps;
- stable AndroidX client 1.1.0;
- deterministic client IDs and version-based upsert;
- official Health Connect Toolbox;
- official fake client for unit tests;
- granular runtime permissions;
- no secret, token, callback, or server;
- works on Samsung and non-Samsung phones; and
- can operate while RythmRun is offline.

Limitations:

- the user must configure both RythmRun and Samsung Health;
- Samsung synchronization timing is outside RythmRun;
- no Samsung consumption acknowledgement exists;
- Samsung's published mapping does not explicitly list exercise routes;
- Health Connect has no direct `pausedDuration` field;
- route data is one ordered list, not RythmRun's separate active segments;
- the calorie record's semantics may not match RythmRun's estimate;
- support excludes work profiles;
- Android 8 can compile against the client but cannot use the provider; and
- store review and health-permission policy still apply.

### Option B: Samsung Health Data SDK 1.1.0

The Samsung Health Data SDK is a local Android AAR that talks directly to the installed Samsung Health application.

Advantages:

- direct Samsung Health destination;
- documented `Exercise` and `Exercise location` writes;
- richer exercise session fields;
- explicit duration, distance, calories, speed, elevation, logs, title, and comment fields where applicable;
- Samsung-assigned record ownership and direct update/delete APIs; and
- no dependence on Health Connect's route propagation.

Requirements and limitations:

- Samsung Health 6.30.2 or later;
- Android 10/API 29 or later;
- Java 17 or later;
- physical device only; emulators are unsupported;
- Samsung Health must be installed and initialized;
- manually downloaded AAR plus native Android wiring;
- public distribution requires Samsung partnership approval;
- package name and production signing SHA-256 registration are mandatory;
- development-time writes require an approved access code;
- user permissions are still required;
- blind insert retries are less safely deduplicated than Health Connect upserts;
- partnership SLA, cost, geography, quotas, and approval criteria are not public; and
- the SDK is for fitness and wellness, not diagnosis or treatment.

Developer mode is for testing only. RythmRun must never instruct ordinary users to enable it.

Do not confuse this SDK with the older **Samsung Health SDK for Android**. Samsung deprecated the older SDK on July 31, 2025 and announced an end-of-service path. New work should use only the current Samsung Health Data SDK.

### Option C: user-mediated file export

RythmRun could generate GPX, TCX, or FIT and ask the user to import it manually. This does not provide a reliable Samsung Health integration:

- Samsung Health import support and preserved fields vary;
- the flow is cumbersome;
- no durable destination receipt exists;
- deletion and update behavior are poor; and
- it does not solve user expectations around automatic sharing.

Keep file export as a separate portability feature, not the Samsung Health integration.

### Decision matrix

| Criterion | Health Connect | Samsung Health Data SDK | File export |
| --- | --- | --- | --- |
| Production eligibility now | Best | Blocked until Samsung approval | Available |
| Direct Samsung write | Indirect | Yes | Manual/variable |
| Route documented by sink | Health Connect yes; Samsung propagation unknown | Yes | Format/import dependent |
| Stable retry idempotency | Strong | Requires more reconciliation | Weak |
| Android coverage | API 28+ feature | API 29+ | Broad but manual |
| Other Android apps | Yes | No | Sometimes |
| Server required | No | No | No |
| User setup | RythmRun + Samsung permissions | RythmRun/Samsung permission | File handling |
| Emulator testing | Partly, plus tools | No | Yes |
| External review | Google Play | Google Play + Samsung partnership | Google Play/privacy |
| Recommendation | MVP | Contingency | Separate feature |

## Feasibility gates

The decision is **go** only if all required gates pass.

### Gate F1: Health Connect route proof

On a current Samsung phone:

1. write a RythmRun-origin `ExerciseSessionRecord` with `ExerciseRoute`;
2. verify the route in Health Connect;
3. grant Samsung Health read access;
4. verify whether Samsung Health displays the route;
5. restart both apps and repeat; and
6. repeat after Samsung Health and Health Connect updates.

If Samsung Health does not receive the route, product must choose one:

- ship sessions without promising a Samsung map;
- omit the Samsung-specific claim and remain a generic Health Connect feature; or
- wait for Samsung Data SDK partnership.

### Gate F2: timing and pause proof

Verify a workout containing at least two pauses:

- original wall-clock start and end;
- active duration;
- pause gaps in route timestamps;
- distance calculated only over active segments;
- Health Connect displayed duration;
- Samsung Health displayed duration; and
- average pace/speed behavior.

Do not compress timestamps to make the active duration fit. Timestamp rewriting would make the route historically false.

### Gate F3: calorie proof

Health Connect defines `TotalCaloriesBurnedRecord` as total energy including active and basal energy. RythmRun currently uses a MET estimate based on active duration and a hardcoded 70 kg weight.

Before calories can ship:

1. replace the hardcoded weight with a validated user/profile source or intentionally omit calories;
2. decide whether the estimate is semantically compatible with the Health Connect record;
3. compare RythmRun, Health Connect, and Samsung Health values;
4. disclose that the value is estimated; and
5. obtain product/privacy approval for the selected behavior.

The safe initial spike can omit calories.

### Gate F4: deletion proof

Verify that RythmRun can:

- delete its session;
- delete distance and any other separate metric records;
- remove the embedded route with the session;
- survive a lost delete acknowledgement;
- treat an already absent record as resolved after confirmation;
- queue deletion while permission is missing; and
- explain manual Health Connect deletion when automated cleanup is impossible.

### Gate F5: Play review proof

Manifest permissions, runtime requests, the privacy policy, Health Apps declaration, Data safety answers, screenshots, and user-facing copy must describe the same feature and data types.

## Current RythmRun fit

### Existing mobile data flow

1. Live tracking collects accepted GPS points and status transitions.
2. Completion calculates canonical active duration, distance, elevation, pace, and estimated calories.
3. The workout, route points, and status changes commit in one SQLite transaction.
4. Local commit is the user-visible success boundary.
5. Cloud synchronization runs asynchronously.
6. Each workout carries a stable `clientSyncId`.
7. Reads and mutations are owner-scoped.

This is a strong fit for a second, device-local export queue.

Relevant files:

- `rythmrun_frontend_flutter/lib/domain/entities/workout_session_entity.dart`
- `rythmrun_frontend_flutter/lib/domain/entities/tracking_point_entity.dart`
- `rythmrun_frontend_flutter/lib/domain/entities/status_change_event_entity.dart`
- `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/providers/live_tracking_provider.dart`
- `rythmrun_frontend_flutter/lib/core/tracking/workout_route_segmenter.dart`
- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/workout_repository_impl.dart`

### Existing Android fit

The Android project already has:

- compile SDK 36;
- target SDK 36;
- Java 17 source and target compatibility;
- Kotlin JVM target 17;
- a minimal `FlutterFragmentActivity`;
- fine and coarse location permissions; and
- Android as the only currently promised release platform.

Relevant files:

- `rythmrun_frontend_flutter/android/app/build.gradle`
- `rythmrun_frontend_flutter/android/app/src/main/AndroidManifest.xml`
- `rythmrun_frontend_flutter/android/app/src/main/kotlin/com/github/cosmicsaurabh/rythmrun/MainActivity.kt`

### Minimum-SDK impact

RythmRun currently resolves `flutter.minSdkVersion` to API 24. The Health Connect AndroidX client supports API 26 or later, while the Health Connect provider itself requires API 28 or later.

The recommended production configuration is:

- raise RythmRun's explicit `minSdkVersion` from 24 to 26;
- show the Health Connect feature as unavailable on API 26–27;
- enable it on API 28+ only after `getSdkStatus()` reports availability; and
- measure API 24–25 active installs in Play Console before making the change.

Do not use manifest `overrideLibrary` tricks to keep API 24. That creates an unsupported binary path around the library's declared floor.

If losing API 24–25 users is unacceptable, the product choices are:

- delay the integration;
- create and maintain separate build variants; or
- perform a deeper isolated-module spike.

The direct Samsung SDK would raise the usable floor to API 29 and may impose its own manifest minimum.

### Existing extension points

- Riverpod dependency assembly lives in `lib/core/di/injection_container.dart`.
- App resume is already observed in `lib/main.dart`.
- User-scope teardown already suspends and drains work before an account changes.
- Settings has a natural insertion point between Units and Account.
- Workout details already loads an owner-verified workout.
- SQLite already has migrations, foreign keys, queues, indexes, and owner checks.
- `TrackingPointEntity.toString()` already redacts coordinates.

### Gaps that must be addressed

- no Health Connect dependency;
- no native health bridge;
- no provider availability state;
- no health permission flow;
- no permissions-rationale activity;
- no Health Connect onboarding activity;
- no Connected Apps UI;
- no owner-scoped Health Connect preference;
- no health export/outbox tables;
- no Health Connect deletion queue;
- no account-switch integration for health writes;
- no real account deletion;
- no tested Samsung route behavior;
- no stable calorie semantics;
- no privacy disclosure for sharing routes with a health platform; and
- the current privacy policy explicitly says location data is not shared with third parties.

## Product terminology and truthfulness

Use:

- **Samsung Health via Health Connect**
- **Share workouts with Health Connect**
- **Choose data to share**
- **Shared with Health Connect**
- **Samsung Health can receive these workouts when you allow it to read Health Connect**
- **Manage Health Connect access**
- **Remove RythmRun data from Health Connect**

Avoid:

- Connect to Health Connect
- Samsung Health connected
- Synced to Samsung Health
- Sent to Galaxy Watch
- Two-way sync
- All health data
- Real-time Samsung synchronization

Google's current UX guidance specifically recommends benefit-focused language such as “set up,” “get started,” or “choose data to share,” rather than the awkward phrase “connect to Health Connect.”

## Product behavior

### User journey 1: set up sharing

1. The user opens **Settings → Connected Apps → Samsung Health via Health Connect**.
2. RythmRun checks the platform and `HealthConnectClient.getSdkStatus()`.
3. RythmRun shows one of:
   - Not supported on this device;
   - Health Connect unavailable in this profile;
   - Install Health Connect;
   - Update Health Connect;
   - Ready to set up;
   - Partial access;
   - Sharing enabled; or
   - Sharing paused.
4. Before Android's permission screen, RythmRun explains:
   - which workout fields it writes;
   - that the data stays in the phone's Health Connect store unless another authorized app reads it;
   - that Samsung Health needs separate permission;
   - that RythmRun imports nothing;
   - that routes can reveal home, work, timing, and health patterns;
   - that prior copies remain if future sharing is paused; and
   - how deletion works.
5. The user taps **Choose data to share**.
6. RythmRun requests only the write permissions needed by the enabled fields.
7. RythmRun re-reads granted permissions rather than trusting the callback alone.
8. RythmRun stores an account-specific opt-in and consent version.
9. RythmRun shows Samsung Health setup instructions:
   - open Samsung Health;
   - go to Settings → Health Connect;
   - grant Samsung Health read access to exercise and the relevant metrics; and
   - reopen or refresh Samsung Health if necessary.

RythmRun cannot verify that the user completed the Samsung Health steps. The screen must say so.

### User journey 2: manually share a workout

1. The user opens an owned, completed workout.
2. The action is **Share with Health Connect**.
3. If RythmRun sharing is not set up, the action opens the setup flow.
4. RythmRun summarizes the fields available for this workout:
   - type;
   - title and notes;
   - start and end;
   - route;
   - distance; and
   - calorie estimate only when approved.
5. The user confirms.
6. RythmRun creates or reuses a durable export row.
7. The UI shows **Queued**.
8. The Health Connect coordinator validates the owner, source state, provider, and current permissions.
9. The native adapter upserts the permitted record set.
10. Returned record IDs and the exact written-record mask are committed locally.
11. The UI shows:
    - **Shared with Health Connect**; or
    - **Shared without route** / **Shared without optional metrics**.
12. The UI explains that Samsung Health appearance may be delayed and depends on Samsung Health permissions.

The workout does not need a RythmRun backend `remoteActivityId`. Health Connect is local and can receive a locally committed workout while the phone is offline.

### User journey 3: automatic sharing

This is post-pilot.

1. The user enables **Automatically share new workouts**.
2. The preference is bound to the current RythmRun user, not merely the app installation.
3. New completion transactions create a queued export row.
4. The local workout commit remains the success boundary.
5. Export starts after the transaction commits.
6. If the process stops, the queue resumes on the next foreground launch.
7. If permissions were revoked, the queue pauses without repeated prompts.
8. No historical rows are enqueued automatically.

### User journey 4: partial permissions

Health Connect allows the user to grant only some requested permissions.

Required for any workout export:

- write exercise.

Optional:

- write route;
- write distance;
- write total calories; and
- future approved data types.

If exercise is granted but route is denied:

- write the session and permitted metrics;
- never treat the route as written;
- show **Shared without route**; and
- offer **Manage access**, without nagging.

If exercise is denied:

- do not write orphan metric records;
- transition to `permission_required`; and
- preserve the queue for explicit retry.

### User journey 5: pause future sharing

The connection page includes a **Sync with Health Connect** toggle to follow Android's UX guidance.

Turning it off:

- stops new writes and retries;
- leaves Android permissions unchanged unless the user chooses Manage access;
- leaves already written records in Health Connect;
- leaves cleanup jobs visible; and
- does not imply Samsung Health was disconnected.

Provide separate actions:

- **Manage access**
- **Remove RythmRun data from Health Connect**
- **Turn off future sharing**

### User journey 6: delete a workout

When the user deletes a RythmRun workout:

1. the same SQLite transaction captures every Health Connect record/client ID into the cleanup queue;
2. normal RythmRun local/backend deletion state is committed;
3. local deletion is not blocked on Health Connect;
4. the cleanup coordinator deletes each RythmRun-owned Health Connect record;
5. route removal occurs with the exercise session;
6. separate distance/calorie records are deleted explicitly;
7. retries are bounded and durable; and
8. permission loss becomes a visible `delete_permission_required` state.

Google's synchronization guidance says data deleted from the source app should also be removed from Health Connect.

### User journey 7: account switch and logout

Health Connect permissions belong to the Android app installation, not to a RythmRun account.

Therefore:

- every RythmRun account must opt in separately;
- a granted permission does not silently enable sharing for a newly signed-in account;
- the Health Connect coordinator must suspend and drain before active-user state changes;
- in-flight results must validate the same user lease before committing;
- user A's queue must never run under user B;
- logout pauses A's future exports; and
- logout must not automatically revoke app-wide Health Connect permission.

The setup screen should explain the shared-device limitation: Health Connect represents the Android profile's health store, so multiple RythmRun accounts used in the same phone profile write to the same destination.

### User journey 8: app or web account deletion

For in-app account deletion:

1. offer removal of the account's RythmRun-written Health Connect records;
2. attempt cleanup while permission and local record IDs still exist;
3. clearly report unresolved local-provider cleanup;
4. provide a deep link to Health Connect data management;
5. continue the RythmRun account deletion contract without retaining route data solely for cleanup; and
6. purge owner-scoped export preferences and state.

A web deletion request cannot reach the phone's on-device Health Connect store. The web flow and support documentation must tell the user how to remove RythmRun data directly from Health Connect.

Uninstalling RythmRun revokes its permissions but does not guarantee deletion of records already written to Health Connect. This limitation must be disclosed.

### User journey 9: troubleshooting Samsung Health

The connection page can offer a checklist:

- update Samsung Health;
- update or enable Health Connect;
- confirm RythmRun write permissions;
- confirm Samsung Health read permissions;
- open Samsung Health after granting permissions;
- pull down to refresh Samsung Health;
- reconnect the Galaxy Watch if applicable; and
- remember that work profiles are unsupported.

Never tell users to enable Samsung Health developer mode.

## User-visible states

### Provider state

```text
unsupported_platform
unsupported_android_version
unsupported_profile
provider_missing
provider_update_required
provider_available
```

### Account preference state

```text
not_configured
enabled_manual
enabled_automatic
paused
```

### Workout export state

```text
not_shared
queued
writing
shared
shared_partial
permission_required
provider_update_required
retrying
permanent_failure
delete_queued
deleting
delete_permission_required
deleted
```

Do not create a `samsung_synced` state. RythmRun has no evidence for it.

## Proposed system design

### High-level flow

```text
Workout completion
    |
    +-- SQLite transaction
    |      +-- workout + route + status changes
    |      +-- Health Connect export intent, if auto-share is enabled
    |
    +-- HealthConnectSyncCoordinator
           |
           +-- load immutable workout snapshot
           +-- validate and map records
           +-- call the Android native bridge
           +-- persist each returned Health Connect record ID
           +-- mark shared, partial, retryable, or permanent failure
                         |
                         v
                  Android Health Connect
                         |
                         v
          Samsung Health reads supported records
          after the user grants it read access
```

The source of truth remains RythmRun's SQLite workout. The export tables are an outbox and receipt ledger, not a second workout model.

### Component boundaries

| Component | Responsibility | Must not do |
|---|---|---|
| `HealthConnectAvailabilityService` | Detect platform, SDK status, profile support, and provider update requirements | Request permissions or mutate preferences |
| `HealthConnectPermissionService` | Read permission state, launch the native permission contract, and open Health Connect settings | Infer that Samsung Health consumed data |
| `HealthConnectRecordMapper` | Produce deterministic, validated record drafts from a workout snapshot | Perform platform calls or database writes |
| `HealthConnectGateway` | Narrow Dart interface implemented by the Android bridge | Own retries or product policy |
| `HealthConnectSyncCoordinator` | Claim outbox rows, write/delete records, classify failures, and persist receipts | Depend on internet reachability |
| `HealthConnectExportRepository` | User-scoped preferences, export rows, record IDs, retry state, and transactional enqueue | Duplicate route payloads |
| Settings and workout UI | Explicit consent, state, troubleshooting, retry, and deletion actions | Promise Samsung Health delivery |

Keep Health Connect independent from the backend synchronization path. The existing `OnlineOperationGuard` protects operations that actually require the network; a local Health Connect write must continue while the phone is offline.

### Suggested source layout

The final names can follow the repository's conventions, but ownership should be visible:

```text
rythmrun_frontend_flutter/lib/
  core/health_connect/
    health_connect_availability.dart
    health_connect_error.dart
    health_connect_record_mapper.dart
    health_connect_sync_coordinator.dart
  domain/entities/
    health_connect_export.dart
    health_connect_preference.dart
  domain/repositories/
    health_connect_export_repository.dart
  data/repositories/
    health_connect_export_repository_impl.dart
  presentation/features/integrations/
    providers/health_connect_provider.dart
    screens/health_connect_settings_screen.dart

rythmrun_frontend_flutter/android/app/src/main/kotlin/<package>/
  healthconnect/
    HealthConnectBridge.kt
    HealthConnectAvailability.kt
    HealthConnectRecordFactory.kt
    PermissionsRationaleActivity.kt
```

Use a private in-repository bridge for production. A third-party Flutter package is acceptable for the feasibility spike only if it proves all required behaviors: client record IDs and versions, route writes, partial permission handling, returned Health Connect IDs, and record deletion. The production decision should favor the small native surface over adopting a broad package whose update cadence controls a sensitive integration.

### Flutter-to-Android contract

Prefer a typed Pigeon API or an equivalently narrow, tested platform interface. Do not pass database maps directly across the channel.

```dart
abstract interface class HealthConnectGateway {
  Future<HealthConnectAvailability> availability();

  Future<Set<HealthConnectPermission>> grantedPermissions();

  Future<Set<HealthConnectPermission>> requestPermissions(
    Set<HealthConnectPermission> permissions,
  );

  Future<HealthConnectWriteReceipt> writeWorkout(
    HealthConnectWorkoutDraft draft,
  );

  Future<HealthConnectDeleteReceipt> deleteRecords(
    List<HealthConnectRecordRef> records,
  );

  Future<void> openSettings();
}
```

`HealthConnectWorkoutDraft` should contain only validated primitives:

- opaque client record IDs and a positive client record version;
- UTC instants plus explicit start and end zone offsets;
- mapped exercise type;
- title and optional notes;
- distance in meters;
- zero or more normalized route locations; and
- optional calories only when the calorie gate has passed.

Return one receipt per record type. A session write succeeding while the distance write fails is a partial success, not a generic exception.

### Native bridge lifecycle

Permission requests need an Android Activity. Implement the bridge as Activity-aware and handle these cases:

- the Flutter engine exists before an Activity attaches;
- configuration changes detach and reattach the Activity;
- a permission request is already in flight;
- the app is backgrounded during a request;
- Health Connect sends the user back through the rationale or onboarding intent; and
- the calling Dart future is cancelled because the account scope was disposed.

Only one permission request should be active. Concurrent callers should share the result or receive a typed `request_in_progress` outcome.

## Android integration setup

### Dependency choice

For implementation planning, use the stable AndroidX Health Connect client:

```groovy
dependencies {
    implementation "androidx.health.connect:connect-client:1.1.0"
}
```

Recheck the stable version when implementation begins. Do not ship an alpha merely because a newer alpha exists unless a required, tested fix is unavailable in stable.

### Minimum SDK decision

The AndroidX client supports API 26+, while Health Connect itself is usable from Android 9/API 28. RythmRun currently inherits Flutter's minimum SDK, which resolves to API 24 in the inspected project.

The clean production configuration is:

```groovy
defaultConfig {
    minSdkVersion 26
}
```

This has two implications:

1. API 24 and 25 devices can no longer install the next release.
2. API 26 and 27 devices can install RythmRun but must see the integration as unsupported.

Before changing `minSdk`, record the API 24/25 share from Play Console. If retaining those users is material, isolate the dependency in a compatible module and verify class loading carefully; that additional complexity is unlikely to be justified for a small install segment.

### Manifest permissions and discovery

The initial production manifest should request write access only:

```xml
<uses-permission android:name="android.permission.health.WRITE_EXERCISE" />
<uses-permission android:name="android.permission.health.WRITE_EXERCISE_ROUTE" />
<uses-permission android:name="android.permission.health.WRITE_DISTANCE" />

<queries>
    <package android:name="com.google.android.apps.healthdata" />
</queries>
```

Add the following only after Gate F3:

```xml
<uses-permission
    android:name="android.permission.health.WRITE_TOTAL_CALORIES_BURNED" />
```

Do not add read permissions, background-read permission, or history permission for a write-only MVP.

The application also needs a rationale entry point. The exact class/alias arrangement should follow the current Health Connect publishing guide:

```xml
<activity
    android:name=".healthconnect.PermissionsRationaleActivity"
    android:exported="true">
    <intent-filter>
        <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
    </intent-filter>
</activity>

<activity-alias
    android:name=".ViewHealthPermissionsUsageActivity"
    android:exported="true"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE"
    android:targetActivity=".healthconnect.PermissionsRationaleActivity">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
        <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
    </intent-filter>
</activity-alias>
```

Verify this on both Android 13 and Android 14+ because Health Connect is a Play-installed app on Android 13 and lower but a system component on Android 14 and higher. An onboarding activity or alias is also recommended so Health Connect can launch RythmRun into a meaningful setup screen.

### Availability rules

The availability service should return a product state, not a Boolean:

| Condition | Result | UI action |
|---|---|---|
| iOS, web, desktop | `unsupported_platform` | Explain Android-only availability |
| Android below API 28 | `unsupported_android_version` | Hide connect action |
| Managed/work profile | `unsupported_profile` | Explain profile limitation |
| API 28–33, provider absent | `provider_missing` | Link to Health Connect in Play |
| Provider installed but obsolete | `provider_update_required` | Link to update |
| Android 14+ component unavailable or disabled | Provider-specific unavailable state | Open system settings when possible |
| Client usable | `provider_available` | Show setup or current permission state |

Do not decide support from Samsung device manufacturer. Health Connect works on supported Samsung and non-Samsung phones; the downstream Samsung Health experience is a separate concern.

## Permission model

### Core permission set

Request the smallest set that can deliver a useful workout:

| Health Connect permission | Why RythmRun needs it | MVP |
|---|---|---:|
| `WRITE_EXERCISE` | Exercise session, type, time, title, and embedded route | Yes |
| `WRITE_EXERCISE_ROUTE` | GPS coordinates associated with the exercise session | Yes |
| `WRITE_DISTANCE` | Explicit workout distance record | Yes |
| `WRITE_TOTAL_CALORIES_BURNED` | Optional calorie record | Only after Gate F3 |

Permissions are app-wide at the Android level, while RythmRun sharing preference is account-specific. These are different state machines:

- Android permission means the installed app may write.
- RythmRun preference means this signed-in user has chosen whether and how to share.

Never infer account consent merely because permissions remain granted after logout.

### Request strategy

On setup:

1. show RythmRun's pre-permission explanation;
2. name the data types and the on-device destination;
3. explain that Samsung Health requires its own Health Connect read access;
4. launch the system permission contract;
5. re-read the granted set after it returns; and
6. allow sharing with any useful subset.

Do not repeatedly prompt after denial. Keep a visible `Review permissions` button and deep-link to Health Connect settings.

### Partial permission behavior

| Granted subset | Export behavior | User state |
|---|---|---|
| Exercise + route + distance | Write complete core export | `shared` |
| Exercise + distance, no route | Write session and distance, omit route | `shared_partial` |
| Exercise + route, no distance | Write routed session, omit distance record | `shared_partial` |
| Exercise only | Write a basic session | `shared_partial` |
| No exercise permission | Do not attempt any workout write | `permission_required` |
| Calories denied | Omit calories without blocking core export | Core result plus optional warning |

A later permission grant does not silently enrich old workouts in MVP. Offer an explicit retry/update action so a user deletion or deliberate omission is not overridden.

### Permission revocation

Permissions can be revoked outside RythmRun at any time. Check immediately before each write or delete. Treat revocation as a durable user-action-required state, not a transient retry:

```text
SecurityException or missing required permission
    -> persist permission_required/delete_permission_required
    -> stop automatic retries
    -> show Review permissions
```

## Workout-to-Health-Connect mapping

### Record set

One RythmRun workout maps to a related record bundle:

| RythmRun data | Health Connect record | Core? | Notes |
|---|---|---:|---|
| Session identity, activity type, start/end | `ExerciseSessionRecord` | Yes | Parent record |
| Active GPS samples | `ExerciseRoute` on the exercise session | Yes when permitted | Embedded, not a standalone receipt |
| Total distance | `DistanceRecord` | Yes when permitted | Use authoritative stored meters |
| Calories | `TotalCaloriesBurnedRecord` | No initially | Requires semantic correction |
| Elevation gain | `ElevationGainedRecord` | Future | Validate Samsung Health propagation |
| Sampled speed | `SpeedRecord` | Future | Avoid deriving a noisy series for MVP |
| Steps | None | No | RythmRun does not measure trustworthy steps |

Samsung's published Health Connect synchronization table explicitly includes exercise sessions, distance, total calories, speed, and related workout data. It does not explicitly guarantee exercise-route propagation. Therefore a successful Health Connect route write does not close Gate F1; it must be observed in supported Samsung Health versions on real devices.

### Exercise type mapping

| `WorkoutType` | Health Connect exercise type |
|---|---|
| `running` | `EXERCISE_TYPE_RUNNING` |
| `walking` | `EXERCISE_TYPE_WALKING` |
| `cycling` | `EXERCISE_TYPE_BIKING` |
| `hiking` | `EXERCISE_TYPE_HIKING` |

Unknown future RythmRun types must fail mapping explicitly. Do not silently label them as `OTHER_WORKOUT` without a product decision.

### Session fields

Map:

- `startTime` to the real workout start instant;
- `endTime` to the real workout end instant;
- the offsets captured for those instants, falling back to the device zone only for legacy workouts;
- a localized title such as `RythmRun Run`;
- a short optional note identifying RythmRun as the recording app; and
- `Metadata.manualEntry` or `Metadata.activelyRecorded` according to the actual origin.

Normal tracked workouts should be actively recorded. A manually created or imported workout must not be relabeled as actively recorded just to make the UI look better.

Device metadata may contain phone type, manufacturer, and model. Do not include IMEI, Android ID, advertising ID, account ID, or another durable hardware identifier.

### Time and pause semantics

Keep the session interval equal to elapsed wall time. Do not subtract `pausedDuration` from the end timestamp or compress route timestamps; that would falsify when the workout occurred.

Health Connect does not expose a general paused-duration field for this use. `ExerciseSegment` represents exercise subtypes/segments and is not a proven pause marker. Do not misuse it.

RythmRun already has `WorkoutRouteSegmenter.activeSegments`. Export points from active segments only, retain their original timestamps, and preserve the gaps between segments. Validate how Samsung Health calculates displayed duration in Gate F2. If its duration presentation is materially wrong, document the limitation or hold launch rather than rewriting time.

### Route normalization

Build the exported route from a copy of the stored data:

1. use active segments only;
2. flatten and sort by timestamp;
3. drop a point unless `startTime <= point.time < endTime`;
4. reject non-finite values;
5. reject latitude outside -90…90 or longitude outside -180…180;
6. collapse exact duplicate timestamps deterministically;
7. include altitude only when finite and plausible;
8. map positive finite horizontal accuracy;
9. map heading to bearing only within 0…360; and
10. preserve the stored route unchanged.

Health Connect's exercise route is a flat sequence. Samsung Health may draw a line across a pause gap even when RythmRun retained separate active segments. This is another physical-device acceptance check.

The backend accepts large routes and the local app can retain thousands of points. Test the bridge with the repository's practical upper bound, including a 12,000-point route. If memory or binder/channel pressure is unacceptable, downsample only the exported copy with a deterministic algorithm that preserves:

- first and last point;
- the ends around every pause;
- sharp changes in direction;
- representative altitude extrema; and
- timestamps in ascending order.

Record whether downsampling occurred for diagnostics, but never store the route or coordinates in logs.

### Distance

Use the persisted workout distance in meters. Do not recalculate it from the flattened route because doing so could reconnect pauses and diverge from the number shown in RythmRun.

Write one `DistanceRecord` over the same session interval. A zero-distance workout can retain a session but should omit the distance record unless tests establish that a zero record has useful semantics.

### Calories

Do not ship calorie export with the current implementation. The live-tracking provider uses a MET estimate and a hard-coded 70 kg weight, while `TotalCaloriesBurnedRecord` represents total calories and may include basal energy. Sending the current value would be precise-looking but semantically unreliable.

Gate F3 requires:

- a real, user-controlled weight source with units and freshness rules;
- a documented decision between active and total energy;
- tests against known examples;
- product copy that calls the value an estimate; and
- verification that Samsung Health does not double-count it with its own calculations.

If these are not complete, leave calorie permission out of the manifest and Play declaration.

## Identity, idempotency, and update rules

### Stable record identity

Health Connect can use `Metadata.clientRecordId` and `clientRecordVersion` to make writes idempotent. Each related record needs its own ID.

Do not use the raw RythmRun user ID or `clientSyncId` as a cross-app identifier. Derive an opaque deterministic ID:

```text
namespace = installation-held integration namespace
material  = version + userId + clientSyncId + recordKind
id        = UUIDv5(namespace, SHA-256(material))
```

Equivalent cryptographically strong deterministic construction is acceptable. Requirements:

- same user, workout, and record kind always produces the same ID;
- two RythmRun accounts with the same workout identifier cannot collide;
- record kinds cannot collide with each other;
- the value reveals no user, email, workout time, or activity type; and
- changing implementation language does not change the algorithm.

Use distinct IDs for:

```text
exercise_session
distance
total_calories_burned
elevation_gained
speed
```

Version the derivation itself. If a future algorithm changes, retain support for deleting IDs created by the old version.

### Client record version

Start at version 1. Retries of the same mapped snapshot use the same version. Increment only when RythmRun intentionally changes the exported content, for example after the user explicitly retries with route permission newly granted.

Persist the version before the native call. Never derive it from retry count: a timeout must not become a logical update.

### Lost-response safety

The write can succeed in Health Connect while RythmRun is killed before storing the receipt. The next run must resend the same client ID and version. Health Connect then treats it as the same logical record instead of creating a duplicate.

The coordinator should:

1. claim a queued row with its already-persisted version;
2. construct exactly the same record bundle;
3. call `insertRecords`;
4. persist returned IDs by record type; and
5. mark the export complete in one local transaction.

If Health Connect returns fewer IDs than expected, preserve any successful IDs and record a partial outcome. Do not discard evidence of a successful record.

### User deletion inside Health Connect

Health Connect users can delete a record outside RythmRun. The MVP must not continuously scan and recreate records marked `shared`. Only these events may write an already-shared workout again:

- the user explicitly taps `Retry/update shared data`;
- a deliberate RythmRun edit feature increments the record version; or
- support directs a user through a clearly explained repair action.

This respects deletion intent and avoids a write/recreate loop.

## Local persistence design

### Why SQLite, not global preferences

The existing app has multiple authenticated users sharing one installation and already enforces user-scoped workout ownership. A global `SharedPreferences` flag could allow one user's automatic-sharing choice to affect another account.

Store integration preferences and export receipts in the same SQLite database as the workout. The current schema is version 6; implementation should add a version 7 migration, or the next available version if another migration lands first.

### Proposed tables

The following is a design contract, not copy-paste-final SQL. Match existing migration helpers and constraint checks.

```sql
CREATE TABLE health_connect_preferences (
  user_id INTEGER PRIMARY KEY,
  sync_enabled INTEGER NOT NULL DEFAULT 0
    CHECK (sync_enabled IN (0, 1)),
  auto_export INTEGER NOT NULL DEFAULT 0
    CHECK (auto_export IN (0, 1)),
  consent_version INTEGER NOT NULL DEFAULT 1,
  enabled_at TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE health_connect_exports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  workout_id INTEGER,
  client_sync_id TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT 'health_connect'
    CHECK (provider = 'health_connect'),
  state TEXT NOT NULL,
  record_version INTEGER NOT NULL DEFAULT 1
    CHECK (record_version > 0),
  intended_record_mask INTEGER NOT NULL,
  written_record_mask INTEGER NOT NULL DEFAULT 0,
  attempt_count INTEGER NOT NULL DEFAULT 0
    CHECK (attempt_count >= 0),
  next_attempt_at TEXT,
  last_error_code TEXT,
  last_error_detail TEXT,
  claimed_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  shared_at TEXT,
  deleted_at TEXT,
  FOREIGN KEY (workout_id) REFERENCES workouts (id) ON DELETE SET NULL,
  UNIQUE (user_id, client_sync_id)
);

CREATE TABLE health_connect_records (
  export_id INTEGER NOT NULL,
  record_type TEXT NOT NULL,
  client_record_id TEXT NOT NULL,
  health_connect_record_id TEXT,
  deletion_state TEXT NOT NULL DEFAULT 'not_requested',
  updated_at TEXT NOT NULL,
  PRIMARY KEY (export_id, record_type),
  UNIQUE (client_record_id),
  FOREIGN KEY (export_id)
    REFERENCES health_connect_exports (id) ON DELETE CASCADE
);

CREATE INDEX idx_health_connect_exports_due
  ON health_connect_exports (state, next_attempt_at);

CREATE INDEX idx_health_connect_exports_user
  ON health_connect_exports (user_id, updated_at);
```

`last_error_code` must be an allow-listed product code. `last_error_detail` should contain only sanitized, bounded diagnostics and can be omitted entirely if it cannot be made safe. Never persist native stack traces, permission intent payloads, route data, coordinates, account tokens, email, or device identifiers in these tables.

### Record masks

A compact mask can represent intended and successful records:

| Bit | Record |
|---:|---|
| 1 | exercise session |
| 2 | route embedded on session |
| 4 | distance |
| 8 | total calories |
| 16 | elevation |
| 32 | speed |

Keep the named record rows even if masks are used. Masks make state comparisons cheap; rows hold the identifiers required for deletion.

### Transactional enqueue

When automatic sharing is enabled, enqueue the export in the same SQLite transaction that saves the completed workout, route, and status changes. This closes the crash window between workout durability and export intent.

The existing `saveWorkoutInLocalDatabase` transaction should accept an optional callback/value or be refactored into a repository transaction that:

1. resolves the stable `clientSyncId`;
2. inserts or validates the workout;
3. inserts its route and status changes;
4. inserts the export and deterministic record rows with `INSERT OR IGNORE`; and
5. commits before any platform call.

Never call Health Connect while the SQLite transaction is open.

For manual sharing, insert the same outbox shape in its own transaction after the user action. The uniqueness constraint makes double taps safe.

### Workout deletion and receipt retention

The current delete behavior can hard-delete some unsynced local workouts, cascading their route. Health Connect receipts must survive long enough to clean up external records.

Before deleting or hiding a workout:

1. load its export and record references under the same `user_id`;
2. mark every written record `delete_queued`;
3. detach the export with `workout_id = NULL` if the workout will be hard-deleted;
4. retain `client_sync_id`, record IDs, and record types; and
5. then apply the existing local/backend deletion rules.

After all external records are confirmed deleted, retain a minimal tombstone for a bounded audit period or delete the export row according to the privacy retention policy.

### Migration requirements

Migration tests must cover:

- clean creation at the newest schema version;
- upgrade from each supported historical version, especially v6;
- foreign keys enabled before migration;
- idempotent/open-time verification;
- no global preference copied into every user;
- uniqueness of `(user_id, client_sync_id)`;
- `ON DELETE SET NULL` preserving cleanup receipts;
- rollback behavior if table or index creation fails; and
- a database containing two users with overlapping local workout IDs.

Do not destructively rebuild the workout tables to add this integration.

## Export coordinator

### Trigger points

Drain the Health Connect outbox:

- immediately after a completed workout commits;
- after the user grants permissions;
- when the app resumes;
- after a manual retry;
- after a connectivity-independent retry timer becomes due; and
- before logout/account scope teardown, only for already-started local bookkeeping—not as a reason to block logout.

Health Connect is local, so network state is irrelevant. Android background execution is not guaranteed; MVP can use foreground/resume draining. Add WorkManager later only if product requirements demand prompt export after the app is killed and the bridge has been proven safe headlessly.

### Account-scope safety

The current authenticated user ID must be captured at claim time and checked again before every local state mutation. On account switch:

1. stop accepting new work for the old scope;
2. cancel or allow the one native call in flight to finish;
3. write its receipt only if its captured owner still matches the export row;
4. release stale claims;
5. dispose providers/coordinators; and
6. initialize the new user's preference and queue.

Never select export work without `user_id = ?`. A platform response must not be applied to whichever user happens to be active when it returns.

### Claim protocol

Use an atomic transaction to select and claim one due row. A state transition can be:

```text
queued/retrying
  -- atomic claim --> writing(claimed_at, attempt_count + 1)
  -- success ------> shared/shared_partial
  -- transient ----> retrying(next_attempt_at)
  -- permission ---> permission_required
  -- permanent ----> permanent_failure
```

Recover `writing` rows whose `claimed_at` is older than a conservative timeout. Resend with the same IDs and version.

### Write order

Prefer one `insertRecords` call containing the complete authorized bundle if the AndroidX client and test matrix demonstrate useful per-record receipts. If a single invalid optional record makes the whole batch opaque, use this order:

1. exercise session with embedded route, if route is permitted;
2. distance;
3. optional calories; and
4. future optional series.

Persist after each successful call. The parent session is the minimum useful result.

Before writing, the native bridge should validate:

- non-empty record IDs;
- positive record version;
- `start < end`;
- all route points inside the session interval;
- sorted route timestamps;
- valid distance units/value;
- no record whose permission is absent; and
- request size below the measured safe bound.

### Failure classification

| Failure | Classification | Action |
|---|---|---|
| Missing/revoked permission, `SecurityException` | User action required | Stop retries; show permission state |
| Health Connect unavailable or update required | User action required | Stop retries; show install/update action |
| Invalid interval, route, type, or unit | Permanent mapping failure | Sanitize code; surface retry only after app update/data repair |
| Transaction too large / memory pressure | Deterministic transformation needed | Downsample exported copy once, same logical version if content was not previously accepted |
| Process death or unknown lost response | Ambiguous transient | Retry same client IDs and version |
| Temporary provider/internal error | Transient | Exponential backoff with jitter |
| Account scope disposed | Cancelled locally | Release claim without attributing result to another user |

Suggested retry delays are approximately 15 seconds, 1 minute, 5 minutes, 30 minutes, and 2 hours, capped thereafter. Retry only while the same account is active unless a safe background owner scope is deliberately implemented.

Use stable error codes such as:

```text
permission_missing
provider_unavailable
provider_update_required
invalid_time_range
invalid_route
unsupported_exercise_type
request_too_large
native_transient
lost_response
unknown_safe
```

## Deletion and disconnect semantics

### Delete one workout

Deletion must remove every record RythmRun wrote:

- delete the exercise session using its returned Health Connect ID when available, or its client ID/time range fallback;
- the embedded route is removed with its session;
- delete the separate distance record;
- delete calories/elevation/speed if those features were enabled; and
- track deletion separately for every record type.

Do not mark the bundle deleted because only the session deletion succeeded. A distance record can otherwise remain orphaned.

### Pause future sharing

Turning off `Share new workouts automatically` changes only the account preference. It must not:

- revoke Android permissions;
- delete previous records;
- clear receipts needed for later deletion; or
- imply Samsung Health has disconnected.

Offer separate, clearly worded actions for `Pause future sharing`, `Open Health Connect permissions`, and `Delete previously shared RythmRun workouts`.

### Bulk deletion

Bulk deletion should enumerate receipts for the signed-in user, not query or delete by a broad time range. Broad deletion risks removing records created by other apps.

Process in bounded batches, persist progress, and support resume after process death. Show counts for deleted, permission-required, and failed records without showing sensitive workout detail in diagnostics.

### Logout and account deletion

Logout must stop new exports immediately. It should not automatically delete Health Connect data unless product policy says logout means disconnect-and-delete and the UI has made that consequence explicit.

For account deletion initiated in the app:

1. explain that Health Connect data is on the device;
2. offer or require cleanup before revoking account scope, according to policy;
3. run receipt-based cleanup while permissions still exist;
4. show any unresolved records and a Health Connect settings route;
5. then continue the existing backend/local deletion flow.

For deletion requested on the website or another device, the server cannot reach the phone's Health Connect store. The public deletion page and confirmation email must instruct the user to delete RythmRun data in Health Connect. If the app is opened before its local account data is removed, it can offer receipt-based cleanup.

Uninstall revokes permissions but may leave previously written records. State this in help/privacy copy.

## Privacy, security, and store compliance

### Privacy-policy change is a launch blocker

The current `docs/privacy-policy.md` says that location data is not shared with third parties. Exporting a GPS route to Health Connect, from which Samsung Health may read it, conflicts with that statement.

Before any internal or public build writes real user data:

- revise `docs/privacy-policy.md` to name Health Connect and explain the user-directed disclosure;
- explain that exercise time, type, distance, route/location, and any future calorie data may be written;
- distinguish Google's Health Connect store from Samsung Health as a separate reader selected by the user;
- state the purpose: workout interoperability and user-requested sharing;
- explain how to stop future writes, revoke permissions, and delete existing data;
- cover retention of minimal local receipts needed for deletion;
- disclose that uninstalling may not erase data already written to Health Connect; and
- keep the in-app rationale and Play-facing privacy URL consistent.

Do not revise the public policy until the feature has a confirmed release date, but do not write production user data before it is revised.

### Google Play Health Apps declaration

Health Connect access requires a Play Console Health Apps declaration. The expected category is `Activity and Fitness`, with each requested data type justified by an actual user-facing function.

The submission package should include:

- exact write permissions from the production manifest;
- screenshots or a short video of setup and the feature in use;
- the public privacy-policy URL;
- a concise explanation for exercise, route, and distance;
- calorie justification only if calories actually ship;
- evidence that the app does not request unrelated read access; and
- a Data Safety form consistent with the app's actual local, backend, analytics, and advertising flows.

Use the same plain-language purpose everywhere. A sample justification:

> RythmRun writes workouts the user records—including activity type, time, distance, and an optional GPS route—to Health Connect so the user can make those workouts available to compatible fitness apps they choose, including Samsung Health.

Do not claim that Health Connect data is never shared if the user's purpose is precisely to make it available to Samsung Health.

### Data minimization

For MVP:

- write only completed workouts the user explicitly authorized;
- request no read access;
- do not upload Health Connect record IDs to the backend;
- keep route transformation and platform writes on-device;
- do not add Samsung account authentication;
- do not collect Samsung Health data;
- do not attach free-form internal diagnostics to notes; and
- avoid calorie, elevation, speed-series, and heart-rate permissions until their user value and semantics are proven.

### Advertising and analytics isolation

The app contains or anticipates advertising integrations. Health Connect data must not be used for advertising, profiling, audience building, attribution, or sale.

Enforce architectural separation:

- no route, workout type, duration, distance, calories, permission state, Health Connect ID, or Samsung Health state in ad requests;
- no sensitive values in analytics event properties;
- no screen recording or session replay on health integration, workout detail, map, or permission screens;
- no crash breadcrumbs containing coordinates or record payloads; and
- telemetry limited to coarse product events such as `health_connect_setup_completed` and safe error codes, subject to consent and policy.

Review the current analytics and crash-reporting configuration rather than assuming default SDK redaction is sufficient.

### Logging

Allowed production diagnostics:

- build version;
- Android API level bucket;
- Health Connect SDK availability state;
- requested/granted record-type names;
- safe result code;
- number of route points, bucketed;
- elapsed operation time, bucketed; and
- retry attempt count.

Prohibited:

- latitude/longitude or encoded route;
- exact start/end timestamps;
- title or notes;
- raw user/workout/client record IDs;
- Health Connect record IDs;
- email, access tokens, or account payloads;
- native exception messages that may embed inputs; and
- body dumps across the platform channel.

### Threat and abuse cases

| Risk | Control |
|---|---|
| User A's workout exported while User B is active | User-keyed rows, captured scope, owner check on every mutation |
| Double tap or retry creates duplicates | Deterministic client IDs, fixed record version, unique local constraints |
| Lost native response causes duplicates | Replay same client ID/version |
| Broad delete erases another app's data | Delete only stored RythmRun record receipts |
| Permission denial causes prompt loop | Explicit user action required to request again |
| Route leaks through telemetry | Allow-list fields; no payload logging |
| Samsung Health is falsely shown as connected | Truthful Health Connect state and conditional wording |
| App recreates a user's manual deletion | No periodic read/reconciliation in MVP |
| Direct SDK developer mode escapes to production | Separate build gate and partnership/signing checklist |
| An account deletion leaves on-device data | Pre-deletion cleanup plus Health Connect instructions |

## UI and copy specification

### Settings entry

Recommended navigation:

```text
Settings
  -> Integrations
      -> Health Connect
```

On a supported Samsung phone, the subtitle may say `Share workouts with Health Connect for use in Samsung Health and other compatible apps.` On other Android phones, omit the Samsung-specific emphasis.

### Setup-screen content

The screen should contain:

- status: unavailable, setup needed, enabled, partial, or permission required;
- a short explanation of the two-app permission model;
- list of data RythmRun intends to write;
- manual vs automatic sharing choice;
- `Set up Health Connect` / `Review permissions` action;
- `Open Health Connect` action when supported;
- Samsung Health troubleshooting link;
- pause future sharing action; and
- delete previously shared data action.

Suggested copy:

> RythmRun shares the workouts you choose with Health Connect on this phone. To see supported data in Samsung Health, allow Samsung Health to read it in Health Connect. Availability and timing are controlled by those apps.

### Workout detail

Show one compact status row:

```text
Health Connect
Not shared | Queued | Shared | Shared without route | Action required | Failed
```

Actions depend on state:

- `Share with Health Connect`;
- `Retry`;
- `Review permissions`;
- `Update shared data`; or
- `Delete from Health Connect`.

Do not add a Samsung logo next to a generic Health Connect success without Samsung brand approval and evidence of consumption.

### Error copy

| Code | User copy |
|---|---|
| `permission_missing` | `RythmRun needs Health Connect permission before it can share this workout.` |
| `provider_update_required` | `Update Health Connect, then try again.` |
| `invalid_route` | `This workout's route could not be shared. The workout may still be shared without its map.` |
| `request_too_large` | `This route could not be prepared for Health Connect yet.` |
| `native_transient` | `Health Connect is temporarily unavailable. RythmRun will retry.` |
| `delete_permission_required` | `Allow RythmRun in Health Connect to finish deleting its shared records.` |

Avoid displaying exception class names or suggesting that Samsung Health is broken when RythmRun only observed a Health Connect error.

### Accessibility and localization

- Do not communicate export state by color alone.
- Give icons semantic labels.
- Support large text without hiding the permission action.
- Localize workout titles and all rationale text.
- Use locale-aware dates in the UI but ISO/UTC internally.
- Keep `Health Connect` and `Samsung Health` product names unchanged unless their brand guidance says otherwise.

## Test strategy

### Dart unit tests

Test the mapper with:

- all four `WorkoutType` values;
- unknown/future workout type;
- UTC and non-UTC zone offsets;
- daylight-saving boundary workouts;
- missing legacy offsets;
- zero and negative duration;
- missing end time;
- active/paused/active route segments;
- points exactly at start and end;
- unsorted and duplicate timestamps;
- invalid coordinates and non-finite numbers;
- absent/invalid altitude, accuracy, and heading;
- zero and large distance;
- no route;
- 1, 2, 5,000, and 12,000 route points;
- downsampling determinism and pause-boundary preservation; and
- calories disabled/enabled by feature gate.

Snapshot the complete native draft for representative fixtures so accidental field changes are reviewed.

### Coordinator tests

Use a fake gateway to cover:

- successful core write;
- partial permission sets;
- partial record success;
- native timeout after an accepted write;
- process death after call and before receipt commit;
- stale `writing` recovery;
- deterministic retry with same ID/version;
- explicit update with incremented version;
- permanent mapping failure;
- exponential backoff;
- manual retry;
- no retry for permission-required state;
- duplicate button taps;
- workout deletion during a write;
- logout during a write;
- account switch to a second user;
- no work selected for a different owner; and
- manual Health Connect deletion not being recreated automatically.

### SQLite tests

In addition to migration cases:

- enqueue workout and export atomically;
- rollback both when either insert fails;
- unique export per user and `clientSyncId`;
- same `clientSyncId` allowed for different users;
- workout hard-delete leaves export/records;
- export delete cascades record receipts;
- due-row claim is exclusive;
- stale claims recover;
- error text is bounded and sanitized;
- preference is account-specific;
- logout does not mutate another user's setting; and
- bulk cleanup resumes at the correct record.

### Android native tests

Use AndroidX's `FakeHealthConnectClient` where supported to test:

- SDK availability mapping;
- permission set construction;
- every exercise-type mapping;
- record metadata and version;
- exercise route construction;
- per-record returned ID mapping;
- deletion by stored IDs;
- `SecurityException` classification;
- invalid argument classification;
- no route permission path;
- Activity detach/reattach during permission requests; and
- one in-flight permission request.

Keep a smaller instrumentation suite for behavior the fake cannot reproduce.

### Manual tools

Use the official Health Connect Toolbox to insert, inspect, and remove test data. Follow Android's published Health Connect test cases for:

- onboarding;
- permission denial and revocation;
- rationale navigation;
- record write;
- route consent/display;
- data deletion; and
- provider update/unavailability.

Do not treat Toolbox success as Samsung Health interoperability proof.

### Physical-device matrix

At minimum:

| Device class | OS | Purpose |
|---|---|---|
| Samsung Galaxy phone | Android 14+ | System Health Connect, Samsung Health route/timing |
| Samsung Galaxy phone | Android 9–13 | Play-installed Health Connect path |
| Non-Samsung phone | Android 14+ | Generic Health Connect behavior |
| Non-Samsung phone | Android 9–13 | Provider install/update behavior |
| Galaxy phone + Galaxy Watch | Supported current versions | Watch-to-phone timing and visibility |
| Managed/work-profile device | Supported Android | Confirm unsupported messaging |

Test the lowest supported Samsung Health version in the launch declaration and the current production version. Repeat route checks after meaningful Samsung Health updates because the published synchronized scope can change.

### End-to-end scenarios

1. Fresh install, no Health Connect, then install and grant.
2. Health Connect available, Samsung Health not linked.
3. RythmRun granted; Samsung Health read denied.
4. Samsung Health read granted before and after RythmRun write.
5. New run with pauses and GPS route.
6. Walking, cycling, and hiking mappings.
7. Offline phone throughout completion and export.
8. App killed immediately after workout save.
9. App killed immediately after native write.
10. Permission revoked before retry.
11. Route permission denied, then granted.
12. Health Connect record deleted manually.
13. RythmRun workout deleted locally.
14. RythmRun account switch with an in-flight write.
15. App logout, login as another user.
16. App account deletion with cleanup.
17. Web account deletion with on-device instructions.
18. Samsung Health refresh and watch reconnection timing.
19. Very long route and low-memory device.
20. App upgrade across the SQLite migration.

### Required evidence for Gate F1/F2

For each test combination, capture:

- app versions and Android version;
- granted permissions in both apps;
- RythmRun workout summary;
- Health Connect record inspection;
- Samsung Health workout summary and map;
- timing until first appearance;
- duration/distance differences;
- behavior around pauses;
- whether refreshing/opening Samsung Health was needed; and
- whether a Galaxy Watch connection changed timing.

Use synthetic routes and test accounts for screenshots and logs.

## Observability and support

### Safe metrics

Useful aggregate metrics:

- setup screen viewed;
- setup completed;
- automatic sharing enabled/disabled;
- export result by safe state;
- permission subset, expressed as record-type flags;
- retry count bucket;
- route point-count bucket;
- Android API and app-version bucket; and
- deletion result.

Do not send exact workout measures or identifiers.

### Health indicators

Launch dashboards should answer:

- What percentage of opted-in workout exports become `shared` or `shared_partial`?
- How many reach `permission_required`?
- Are transient errors concentrated on an OS/app version?
- How often do users choose route permission?
- How often does cleanup fail?
- Does a release increase duplicate complaints?

RythmRun cannot directly measure Samsung Health consumption through the Health Connect write API. Do not manufacture a “Samsung delivery rate.” Pilot feedback and controlled-device checks are the only valid evidence unless a later supported API provides more.

### Support playbook

Support should request only:

- RythmRun version;
- phone model;
- Android version;
- Samsung Health and Health Connect versions;
- coarse export state/error code;
- whether both apps have the expected permissions; and
- whether opening/refreshing Samsung Health helped.

Support must not ask for Health Connect database exports, full diagnostic logs containing routes, Samsung credentials, or screenshots exposing a user's map unless strictly necessary and handled under an approved privacy process.

## Delivery plan

### Phase 0: product, policy, and install-base decision — 2–4 developer days

- Confirm write-only Android scope and terminology.
- Check Play Console API 24/25 install share.
- Draft privacy and Play declaration changes.
- Define synthetic pilot workouts and acceptance tolerances.
- Submit the Samsung Health Data SDK partnership inquiry in parallel.

Exit: stakeholders accept the Health Connect truth boundary and minimum-SDK impact.

### Phase 1: physical feasibility spike — 3–5 developer days

- Add the stable AndroidX client on a spike branch.
- Prove availability and permission flow on Android 13 and 14+.
- Write running/walking/cycling/hiking sessions.
- Write distance and a paused synthetic route.
- Observe Samsung Health on two supported Samsung phones.
- Test deletion and ambiguous retry.
- Measure 12,000-point route performance.

Exit: Gates F1, F2, and F4 are evidenced. If route is a launch requirement and does not propagate reliably, pause the primary implementation while evaluating the direct SDK contingency.

### Phase 2: durable export core — 7–10 developer days

- Add user-scoped SQLite migration and repositories.
- Add deterministic ID derivation and record versions.
- Implement mapper and typed gateway.
- Build the Kotlin bridge.
- Add foreground/resume coordinator and failure classification.
- Integrate atomic auto-enqueue with workout save.

Exit: crash-safe duplicate-free export works offline with automated tests.

### Phase 3: UI, permissions, deletion, and account lifecycle — 4–6 developer days

- Add integration settings and workout-detail status.
- Add rationale/onboarding entry points.
- Implement partial permissions and manual retry/update.
- Add per-workout and bulk cleanup.
- Add account-switch/logout safeguards.
- Update in-app account deletion and help content.

Exit: all user journeys are usable and truthful.

### Phase 4: compliance and hardening — 5–8 developer days

- Finalize privacy-policy and deletion-page changes.
- Submit/complete Play Health Apps declaration.
- Run unit, database, native, instrumentation, and accessibility tests.
- Execute physical-device matrix.
- Perform privacy/logging review and threat-model sign-off.
- Prepare support playbook and release notes.

Exit: automated suite passes, policy approval exists, and physical evidence satisfies launch gates.

### Phase 5: controlled pilot — at least 1 week

- Start with internal and invited Samsung users.
- Enable automatic export only after manual export proves stable.
- Watch safe error, duplication, and cleanup metrics.
- Revalidate with the current Samsung Health production release.
- Gather explicit feedback about route, duration, and appearance latency.

Exit: acceptance thresholds hold for the agreed sample and no unresolved privacy/deletion defect remains.

### Estimated effort

Primary Health Connect implementation: approximately 3–5 developer weeks, excluding external Play review time and the pilot observation window.

If the Samsung direct SDK becomes necessary and partnership access is approved, add approximately 2–4 developer weeks plus unpredictable partnership lead time and extra device/release validation.

## Rollout and rollback

### Feature gates

Use at least:

- a compile/build-time availability gate so unfinished native code is not exposed;
- a product gate controlling settings discovery and new exports;
- a separate automatic-export gate; and
- independent optional-record gates for calories/elevation/speed.

A remote product gate may help staged rollout but cannot be the only safety mechanism because local Health Connect writes work offline. The coordinator must honor the last safely persisted gate/account preference and the app must always expose a local pause control.

### Rollout sequence

1. Internal build: manual export only.
2. Small Samsung-device pilot: manual export and deletion.
3. Broader Android pilot: include non-Samsung Health Connect behavior.
4. Enable automatic export for a small opted-in cohort.
5. Expand only after route, duplicate, and cleanup metrics remain healthy.

### Rollback behavior

If a defect appears:

1. stop creating new automatic export intents;
2. allow in-flight writes to finish or safely retry the same version;
3. retain receipts;
4. keep `Delete from Health Connect` available;
5. do not revoke permissions programmatically as a substitute for deletion;
6. communicate the affected record types and versions; and
7. ship mapper/data repair only through explicit versioned updates.

Never “roll back” by dropping export tables; that destroys the IDs needed to remove already-written records.

## Launch acceptance criteria

The Android Health Connect path may launch only when all applicable items pass.

### Functional

- [ ] A supported completed workout can be manually shared without internet.
- [ ] Running, walking, cycling, and hiking have verified type mappings.
- [ ] Session start/end, distance, and route match RythmRun within agreed tolerances.
- [ ] Pauses do not add paused GPS points or corrupt timestamps.
- [ ] A route denied by permission produces a truthful partial success.
- [ ] Automatic sharing enqueues atomically with workout persistence.
- [ ] Repeated taps, process death, and ambiguous responses do not create duplicate records.
- [ ] Individual and bulk deletion remove every record type RythmRun wrote.
- [ ] Account switch cannot export or mutate another user's queue.
- [ ] Turning sharing off does not falsely claim to delete existing data.

### Samsung interoperability

- [ ] Supported records appear in current Samsung Health after the documented user configuration.
- [ ] Route behavior satisfies Gate F1, or product explicitly launches without a Samsung Health map and says so.
- [ ] Duration/pause behavior satisfies Gate F2.
- [ ] Appearance latency and refresh behavior are documented.
- [ ] Galaxy Watch-to-phone behavior is tested and described as indirect, not guaranteed real-time delivery.
- [ ] No UI claims confirmation that Samsung Health consumed a workout.

### Privacy and policy

- [ ] Privacy policy accurately describes route/location disclosure.
- [ ] Account-deletion help covers on-device Health Connect data.
- [ ] Play Health Apps declaration is approved for every manifest permission.
- [ ] Data Safety answers match actual data flows.
- [ ] No health/route values reach ads, analytics, or unsafe logs.
- [ ] Permission rationale, public policy, and store copy agree.
- [ ] Users can pause future writes and delete past writes independently.

### Quality

- [ ] Dart, SQLite, native, and instrumentation suites pass.
- [ ] Android 9–13 and Android 14+ paths pass on physical devices.
- [ ] Current supported Samsung Health versions pass the matrix.
- [ ] Accessibility and localization reviews pass.
- [ ] 12,000-point route test meets the agreed memory/time budget.
- [ ] Support playbook and safe diagnostics are ready.
- [ ] Rollback preserves cleanup capability.

## Risk register

| Risk | Probability | Impact | Mitigation / decision |
|---|---|---|---|
| Samsung Health does not import/display Health Connect routes consistently | Medium–high until proven | High if maps are promised | Gate F1; truthful no-map launch or direct SDK contingency |
| Samsung Health sync timing is delayed or requires refresh | Medium | Medium | Pilot measurements and troubleshooting copy |
| Android API 24/25 loss is material | Unknown | Medium | Play install-base check before min-SDK change |
| Current calorie estimate is misleading or double-counted | High | High | Exclude until Gate F3 |
| Health Connect permission/store review delays launch | Medium | High | Early Play declaration and minimal permissions |
| Partial batch leaves orphaned related records | Medium | High | Per-record receipts and deletion state |
| Process death produces duplicate workouts | Medium without design | High | Deterministic client IDs/version and outbox |
| Account switch crosses data ownership | Medium without design | Critical | User-keyed scope and race tests |
| Privacy policy contradicts route disclosure | Certain without update | Critical | Policy launch blocker |
| Direct Samsung SDK partnership is denied or delayed | Medium–high | High for fallback | Treat as contingency, not critical-path promise |
| Samsung changes synchronized record scope | Medium | Medium | Supported-version matrix and release revalidation |
| Generic Flutter plugin lacks required identity/delete behavior | Medium | High | Private narrow native bridge |
| User deletes data in Health Connect and app recreates it | Medium with reconciliation | High trust cost | No background reconciliation/recreate |
| Uninstall/account deletion leaves external data | Medium | High | Explicit cleanup flow and disclosures |

## Direct Samsung Health Data SDK contingency

### When to use it

Use the direct SDK only if all are true:

1. a must-have requirement—most likely route fidelity—fails through Health Connect;
2. Samsung approves the partnership and production access;
3. RythmRun accepts a Samsung-specific implementation and release process;
4. security/privacy/store review covers the new data path; and
5. the adapter prevents double-writing workouts through both providers.

Do not build it simply to display a “connected to Samsung” label.

### Current SDK constraints to revalidate

Samsung's current Health Data SDK documentation describes:

- Android 10/API 29 or higher;
- Samsung Health 6.30.2 or higher;
- Java 17;
- physical-device testing rather than emulator use;
- Samsung and non-Samsung Android phones with Samsung Health;
- development writes gated by an access code/developer process;
- production distribution gated by Samsung partnership approval;
- registration of package name and signing certificate SHA-256; and
- special handling for Play App Signing.

The older Samsung Health SDK for Android was deprecated on July 31, 2025. Do not start new work against that legacy SDK.

Requirements and versions can change; recheck Samsung's release notes and app-verification guide before implementation.

### Adapter boundary

Keep provider-specific native code behind the same product coordinator:

```dart
abstract interface class WorkoutExportProvider {
  String get providerKey;

  Future<ProviderAvailability> availability();
  Future<Set<ExportPermission>> requestPermissions(
    Set<ExportPermission> requested,
  );
  Future<WorkoutExportReceipt> write(WorkoutExportDraft draft);
  Future<WorkoutDeleteReceipt> delete(List<ProviderRecordRef> records);
}
```

The preference must choose one write provider per account/workout:

```text
health_connect
samsung_health_data_sdk
```

Never run both automatically for the same workout. Samsung Health may already import the Health Connect copy, so a direct copy would likely duplicate it.

### Direct record mapping

At minimum, evaluate Samsung's:

- Exercise record for time, type, duration, distance, calorie, and summary fields; and
- Exercise location record for time-series coordinates and related route fields.

The direct model may require fields RythmRun does not currently model with the same semantics. In particular:

- distinguish elapsed and active duration;
- confirm whether calories are mandatory and what zero/unknown means;
- confirm coordinate/altitude units;
- confirm location timestamp boundaries;
- confirm pause handling and route segmentation;
- map the four activity types against Samsung's current exercise constants; and
- avoid inventing heart rate, cadence, power, or steps.

The physical spike must inspect the written workout in Samsung Health, not merely an SDK success callback.

### Direct identity and lost acknowledgements

Use Samsung's client data identity field, if supported for the target records, as the provider-specific equivalent of Health Connect client record ID. Preserve the same opaque derivation principle and a separate namespace.

If the direct API does not provide a true upsert:

1. query by client data identity before insert/update;
2. record Samsung IDs after success;
3. on an ambiguous response, query before retrying;
4. serialize work per logical workout; and
5. prove the behavior with process-death tests.

Do not assume the Health Connect version algorithm directly transfers to Samsung semantics.

### Packaging and signing

The implementation checklist must include:

- obtain the SDK from Samsung's official channel;
- store its AAR according to license and repository policy;
- document checksum and upgrade process;
- keep development access code out of source control;
- register the exact Android application ID;
- register the correct upload/app-signing SHA-256 values;
- verify debug, internal, and Play production signing separately;
- disable developer mode and test credentials in production; and
- add a CI check that a release cannot contain development-only configuration.

Partnership approval is an external dependency. Never present the direct path as scheduled until Samsung confirms access for RythmRun's distribution configuration.

### Direct permissions and UX

Request only the Samsung record permissions needed for Exercise and Exercise location. Present a separate consent screen because data is now exchanged directly with Samsung Health, not through Health Connect.

Copy must explain:

- which app RythmRun writes to;
- which exercise/location data is shared;
- how the user changes Samsung Health permissions;
- how to delete previously written records; and
- that this direct path is available only on compatible Android/Samsung Health versions.

Update the privacy policy and Play Data Safety review again if the data controller/processor path differs from the Health Connect release.

### Direct path launch gates

- [ ] Written workout and map appear correctly on supported Samsung/non-Samsung phones.
- [ ] Partnership and app verification work with Play production signing.
- [ ] Developer access code/mode is absent from release.
- [ ] Idempotency survives lost acknowledgement and process death.
- [ ] Delete removes Exercise and Exercise location data.
- [ ] Health Connect and direct provider cannot both write one workout.
- [ ] Samsung Health upgrades do not break the supported matrix.
- [ ] Privacy/store copy names the direct Samsung path.

## Future inbound Samsung Health import

Inbound import is deliberately outside MVP. It changes the product from user-directed export to health-data ingestion, expands permissions, creates duplicate/loop risks, and may affect cross-platform policy.

If pursued later:

1. define a specific user benefit that needs imports;
2. request only required read permissions;
3. source-filter Samsung-origin records by verified `DataOrigin` on real devices rather than a guessed package constant;
4. attribute imported data to Samsung Health in the UI;
5. store per-record-type change tokens and handle token expiry;
6. use Health Connect record IDs plus source origin for identity;
7. never re-export an imported workout back into Health Connect;
8. define precedence for edits/deletes;
9. keep imported health data private and out of advertising/analytics;
10. assess Health Connect background/history permissions separately; and
11. clarify whether any backend/iOS mirroring is permitted before uploading imported data.

Exercise-route reads have additional user-consent behavior and permission details that have evolved in Android documentation. Revalidate the current `READ_EXERCISE_ROUTES` flow at design time rather than copying the write-only permission model.

## Open decisions

These do not block writing the plan but must be closed before implementation or launch:

1. Is a route visible in Samsung Health a hard launch requirement, or is session/distance sufficient?
2. What percentage of active installs are API 24/25, and what loss is acceptable?
3. Should MVP allow both manual and automatic export, or pilot manual first?
4. Should deleting a RythmRun workout default to deleting its Health Connect copy, with an explicit choice?
5. How long should minimal deletion receipts/tombstones be retained?
6. What Samsung Health versions and device families will RythmRun officially support?
7. Is appearance latency acceptable if the user must open/refresh Samsung Health?
8. Who owns Play Health Apps declaration, privacy review, and Samsung partnership communication?
9. What are the numeric tolerances for distance, duration, and route comparison?
10. Will calories remain excluded until user weight and energy semantics are fixed?
11. Is a remote rollout service available, and how does it interact with offline local safety?
12. If direct SDK access is approved, what criterion justifies its maintenance cost over a no-route Health Connect launch?

## Implementation work breakdown

### Epic SH-1: feasibility and compliance

- SH-1.1: measure Android API 24/25 install share;
- SH-1.2: build Health Connect route/timing/deletion spike;
- SH-1.3: test current and minimum Samsung Health versions;
- SH-1.4: draft Play Health Apps declaration;
- SH-1.5: draft privacy/deletion/help changes; and
- SH-1.6: submit Samsung Data SDK partnership inquiry.

### Epic SH-2: persistence and mapping

- SH-2.1: add versioned SQLite tables/indexes;
- SH-2.2: add repository and user ownership queries;
- SH-2.3: add atomic workout/auto-export enqueue;
- SH-2.4: implement opaque deterministic record IDs;
- SH-2.5: implement record mapper and validation;
- SH-2.6: implement safe error taxonomy; and
- SH-2.7: add migration/unit tests.

### Epic SH-3: Android bridge

- SH-3.1: add stable AndroidX dependency and min-SDK decision;
- SH-3.2: add availability/provider checks;
- SH-3.3: add rationale/onboarding manifest entries;
- SH-3.4: add typed Activity-aware permission flow;
- SH-3.5: add record write and per-record receipts;
- SH-3.6: add receipt-based deletion;
- SH-3.7: add fake-client and instrumentation tests; and
- SH-3.8: benchmark long routes.

### Epic SH-4: coordinator and lifecycle

- SH-4.1: implement due-row claim/recovery;
- SH-4.2: implement write/partial/retry transitions;
- SH-4.3: wire workout-completion trigger;
- SH-4.4: wire resume/manual retry triggers;
- SH-4.5: enforce account switch/logout disposal;
- SH-4.6: integrate workout deletion;
- SH-4.7: implement bulk cleanup; and
- SH-4.8: add concurrency/process-death tests.

### Epic SH-5: product surface

- SH-5.1: integration settings screen;
- SH-5.2: supported/unavailable/setup states;
- SH-5.3: workout detail status/actions;
- SH-5.4: partial permission UX;
- SH-5.5: Samsung Health troubleshooting;
- SH-5.6: account-deletion cleanup;
- SH-5.7: accessibility/localization; and
- SH-5.8: support documentation.

### Epic SH-6: launch

- SH-6.1: privacy and deletion pages published with release timing;
- SH-6.2: Play declaration approved;
- SH-6.3: physical-device matrix completed;
- SH-6.4: privacy/logging review;
- SH-6.5: internal/manual pilot;
- SH-6.6: automatic-sharing pilot;
- SH-6.7: safe dashboards/support readiness; and
- SH-6.8: launch/rollback decision.

## Official references

These links were reviewed for this plan. Recheck them when implementation starts because SDK versions, permissions, policies, and Samsung interoperability can change.

### Samsung

- [Accessing Samsung Health data through Health Connect](https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect)
- [Samsung Health and Health Connect FAQ](https://developer.samsung.com/health/health-connect-faq.html)
- [Samsung Health Data SDK overview](https://developer.samsung.com/health/data/overview.html)
- [Samsung Health Data SDK development process](https://developer.samsung.com/health/data/process.html)
- [App verification and signing](https://developer.samsung.com/health/data/guide/app-verification.html)
- [Data permission guide](https://developer.samsung.com/health/data/guide/features/data-permission.html)
- [Samsung Health Data SDK FAQ](https://developer.samsung.com/health/data/faq.html)
- [Samsung Health Data SDK release notes](https://developer.samsung.com/health/data/release-note.html)
- [Samsung Health partnership contact](https://developer.samsung.com/health/partnerships/contact-us)

### Android Health Connect

- [Check Health Connect availability](https://developer.android.com/health-and-fitness/health-connect/availability)
- [Get started with Health Connect](https://developer.android.com/health-and-fitness/health-connect/get-started)
- [AndroidX Health Connect release notes](https://developer.android.com/jetpack/androidx/releases/health-connect)
- [Workouts in Health Connect](https://developer.android.com/health-and-fitness/health-connect/experiences/workouts)
- [Exercise routes](https://developer.android.com/health-and-fitness/health-connect/features/exercise-routes)
- [Write data](https://developer.android.com/health-and-fitness/health-connect/write-data)
- [Synchronize data](https://developer.android.com/health-and-fitness/health-connect/sync-data)
- [Delete data](https://developer.android.com/health-and-fitness/health-connect/delete-data)
- [Health Connect metadata](https://developer.android.com/health-and-fitness/health-connect/metadata)
- [Health Connect UI guidelines](https://developer.android.com/health-and-fitness/health-connect/ui/guidelines)
- [Promote Health Connect](https://developer.android.com/health-and-fitness/health-connect/ui/promote)
- [Permission UX](https://developer.android.com/health-and-fitness/health-connect/ui/permissions)
- [Onboard users](https://developer.android.com/health-and-fitness/health-connect/ui/onboard-users)
- [Publish a Health Connect app](https://developer.android.com/health-and-fitness/health-connect/publish)
- [Health Connect Toolbox](https://developer.android.com/health-and-fitness/health-connect/test/health-connect-toolbox)
- [Unit tests](https://developer.android.com/health-and-fitness/health-connect/test/unit-tests)
- [Health Connect test cases](https://developer.android.com/health-and-fitness/health-connect/test/test-cases)

### Google Play policy

- [Health apps declaration form](https://support.google.com/googleplay/android-developer/answer/14738291)
- [Android Health permissions guidance and FAQ](https://support.google.com/googleplay/android-developer/answer/12991134)
- [Google Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311)
- [Google Play Data Safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Google Play app account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)

## Repository references

The recommendations are grounded in the current repository, especially:

- `rythmrun_frontend_flutter/lib/domain/entities/workout_session_entity.dart` — activity types, stable client ID, metrics, and pause duration;
- `rythmrun_frontend_flutter/lib/domain/entities/tracking_point_entity.dart` — route point fields;
- `rythmrun_frontend_flutter/lib/core/tracking/workout_route_segmenter.dart` — active and paused route boundaries;
- `rythmrun_frontend_flutter/lib/core/tracking/workout_timeline.dart` — elapsed/paused/active timing;
- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart` — SQLite v6 schema, ownership, transactional workout save, and deletion queue;
- `rythmrun_frontend_flutter/lib/data/repositories/workout_repository_impl.dart` — local/backend workout synchronization;
- `rythmrun_frontend_flutter/lib/presentation/features/live_tracking/providers/live_tracking_provider.dart` — completion flow and current calorie calculation;
- `rythmrun_frontend_flutter/android/app/build.gradle` — Android SDK and Java/Kotlin configuration;
- `rythmrun_frontend_flutter/android/app/src/main/AndroidManifest.xml` — existing platform permissions/activity;
- `rythmrun_frontend_flutter/android/app/src/main/kotlin/com/github/cosmicsaurabh/rythmrun/MainActivity.kt` — current Android host;
- `docs/privacy-policy.md` — current location-sharing representation; and
- `docs/delete-account.md` — current external account-deletion instructions.

## Final recommendation

Proceed with an Android-only, outbound, opt-in Health Connect integration, beginning with a physical-device spike. Ship exercise session, GPS route, and distance only; keep calories out until RythmRun fixes their source and semantics. Treat “visible in Samsung Health” as a downstream interoperability outcome that must be physically tested, not as an acknowledgement RythmRun can observe.

Build the durable user-scoped outbox, deterministic IDs, partial receipts, and deletion path before enabling automatic sharing. Update privacy and Play declarations before production data is written. Submit the direct Samsung Health Data SDK partnership inquiry in parallel, but use that SDK only if a must-have route requirement fails through Health Connect and Samsung grants production access.
