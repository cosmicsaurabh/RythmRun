---
published: false
---

# Workout-Tracking UX and Accessibility Audit — RythmRun Android

| Field | Value |
| --- | --- |
| Date | 2026-08-18 |
| Tree audited | branch `auth-impr` at `d0e5b92` (Flutter app unchanged since); pinned `geolocator 14.0.2` / `geolocator_android 5.0.3`, `flutter_map 8.3.1`, `hugeicons 1.1.7`; Flutter framework `3.44.x` sources for Material defaults |
| Method | Static read only. No tests, builds, emulators, or devices were run. No code changed. Contrast ratios are computed from the hex values in `custom_app_colors.dart` and Flutter's Material 2 defaults, not measured on a screen. TalkBack order, large-text overflow, and every "on device" claim below are marked as such and must be verified per §9 |
| Scope | Live-tracking journey (Track tab, live map, recovery card, logout-with-workout dialogs), the notification controls proposed for IP-3.4, and the accessibility of all of it. Completed-workout history and sync UI are out of scope except where the tracking flow hands off to them |
| Companion audits | [GPS tracking audit](./gps-tracking-audit.md) (`F1`…`F14`), [battery/durability audit](./battery-durability-audit.md) (`B-xx`, `D-xx`), [foreground-service audit](./android-foreground-service-audit.md) (`G-xx`, §7–§9), [IP-3.4 design](./android-background-tracking-design.md) (§5.5, §7.4–7.7, §11), [sync audit](../sync/sync-reliability-audit.md) (`SYNC-01`). Where a finding overlaps, the ID is cited; this document does not re-derive engine, battery, or sync findings — it adds what the *user sees, hears, and can act on* |

File shorthand used below: `track` = `lib/presentation/features/live_tracking/screens/track_screen.dart`, `prov` = `…/live_tracking/providers/live_tracking_provider.dart`, `state` = `…/live_tracking/models/live_tracking_state.dart`, `card` = `…/live_tracking/widgets/workout_recovery_card.dart`, `svc` = `lib/core/services/live_tracking_service.dart`, `err` = `lib/core/utils/location_error_handler.dart`, `map` = `lib/presentation/features/Map/screens/live_map_feed.dart`, `theme` = `lib/theme/app_theme.dart`, `colors` = `lib/const/custom_app_colors.dart`, `main` = `lib/main.dart`, `profile` = `lib/presentation/features/profile/screens/profile_screen.dart`, `manifest` = `android/app/src/main/AndroidManifest.xml`, `PM.java` = `geolocator_android-5.0.3/…/permission/PermissionManager.java`.

---

## 0. Executive UX verdict

**Not release-honest off the happy path; not accessible on any path.**

- The screen-on, precise-permission, clear-sky run is coherent: Start → live time/distance/pace → Pause/Resume with correct arithmetic (IP-1.2 tests) → a confirmed Finish → local save → save-failure and cleanup-failure recovery that blocks a second workout instead of losing the first. That part earns trust.
- Every other state either **lies by omission** or **dead-ends**: a lost GPS stream, an indoor start, an "Approximate" grant, or location services switched off all leave the timer running and the **Pause** button showing after a 4-second snackbar (`prov:706-717`, `map:360-368`); a permanently denied permission shows a button labelled *Open App Settings* that only re-runs the check (`track:537-546`); once the "granted" flag goes stale, Start fails forever with *Failed to start workout. Please try again.* (`prov:208-228`, `:283-293`); a finished workout is never acknowledged as saved (`track:1132-1157`); and process death, screen-off loss, or force-stop erase the workout with **no message on relaunch** (`prov:57-72`, `track:227-255`; = `D-01`/`D-06`).
- Accessibility has not been started: there are **zero** `Semantics`, `semanticsLabel`, or `liveRegion` uses in `lib/`; the active-card expand toggle is forced to a 24 dp target (`track:712-713`); the card's "drag handle" is an unlabelled 40×4 dp tap target (`track:454-467`); the coloured snackbars used for Start and errors render white Material-2 text on `#B1CF5C` / `#73A7E0` / `#E6624A`, ≈ 1.8:1 / 2.5:1 / 3.4:1 (computed); pause and interruption are conveyed only by which button is present and by a red dashed line.
- Three developer debug `Text`s ("Session State: …", "Is Offline: …", "Expected: authenticatedOffline when backend down") have shipped in the Track screen since 2025-10-04 (`track:129-135`, blame `818d571`). The opaque map hides them from sighted users; they remain in the semantics tree for screen-reader users.
- Nothing above except the recovery journey itself needs IP-3's schema. Stage 0 and Stage 1 in §10 are pure Flutter/state changes with widget and provider tests and can land before IP-3.1.
- **No notification or background-service code exists** (`manifest:1-75`, `MainActivity.kt`, grep of `lib/`). Item 5 of the brief is therefore assessed against the IP-3.4 design proposal, and this document does not claim any background behaviour works.

Severity scale used here: **Critical** = the user loses data or is told something false about the workout · **High** = a journey dead-ends or a material outcome is never acknowledged · **Medium** = misleading, inaccessible, or laborious but recoverable · **Low** = polish.

---

## 1. Journey table (today, `d0e5b92`)

| Journey | What the user does | What the app shows (evidence) | What it implies vs. what is proven | Verdict |
| --- | --- | --- | --- | --- |
| **First open** | Logs in; Home builds all four tabs (`home_screen.dart:95,107`) | The live map's `initState` calls `getCurrentLocation()` → `checkPermissions()` → **OS permission dialog with no in-app rationale** (`map:76-81`, `svc:121-127`, `svc:43-50`) | Implies the app needs location "now"; nothing explains why. On Android 11+ a denial here spends one of the two prompts | High (UX-05, = `F10`/`B-08`) |
| **Start** | Taps *Ready to Track?* → card expands → taps a type | Green snackbar *Starting running workout...* (`track:72-78`); card collapses to *Ready to Track?* again while `isLoading` overlays a `CupertinoActivityIndicator` on top of it (`track:208-217`); map shows *Loading location...* (`map:469-492`); then the active card appears with `RUNNING`, timer, `0.00 km`, `--:--` pace | "Starting" is asserted before the outcome; three concurrent indicators; no *Waiting for GPS* state — the timer runs from `startTime` whether or not a fix ever arrives (`prov:239-282`, `:719-740`) | Medium (UX-13), Critical when no fix arrives (UX-01/02) |
| **Pause** | Taps *Pause* | Timer stops; button becomes *Resume*; movement draws as a red dashed line (`prov:299-339`, `track:734-745`, `map:197-210`); the *Pace* figure keeps its last value (`prov:328-338` never resets `currentPace`) | Correct arithmetic; state readable only from the control swap and colour; a stale pace looks current; no announcement for screen readers | Medium (UX-11) |
| **Resume** | Taps *Resume* | Timer continues from active time; pace `--:--`; first accepted point anchors zero distance (`prov:341-388`) | Correct and honest | Pass |
| **Finish** | Taps *Finish* → dialog *Finish Workout? … This action cannot be undone.* → red *Finish* (`track:1083-1111`) | Card shows *Finishing workout… Start controls will return when completion handling finishes.* (`track:257-275`); on success the ad gate runs (ads off) and the card silently collapses to *Ready to Track?*; the map clears (`track:1132-1157`, `map:340-347`) | Nothing says **saved**, or where. The retry path does say *Workout saved.* (`track:302-307`); the primary path never does | High (UX-07) |
| **Permission failure** | Denies once → taps *Grant Permission* → denies again (Android 11+: permanent) | Card: *Location Permission Required* → then *Location Permission Denied* with button *Open App Settings* which calls `checkPermissions()` again (`track:537-546`; `err:41-52`); every failed check also fires a red snackbar with the same sentence (`prov:113-118`, `map:360-368`) | The button promises Settings and delivers nothing; the description never names the Settings path; the copy for services-off says *restart the app* although the app has a one-tap *Turn on* dialog (`err:8-9`, `svc:190-224`) | High (UX-04, = `G-10`; UX-20) |
| **GPS interruption** (services toggled off, provider error, indoors, "Approximate" grant) | Keeps running | One 4-s snackbar *Location tracking was interrupted.* on stream error only (`prov:706-717`, `map:360-368`); for no-fix / approximate nothing at all (`svc:56-62`, `PM.java:54-64`, policy 50 m ceiling `gps_point_acceptance_policy.dart:86,140-144`); timer keeps counting; *Pause* still shown | **Implies tracking continues.** Unknown minutes are counted as active time with zero distance; the user finds out at the end | Critical (UX-01, UX-02; = `F4`/`D-04`/`G-11`) |
| **Failed save** | Finish → local write throws | Snackbar *Workout is not saved yet. Use Retry save or explicitly discard it.* (`track:1158-1166`); card *Workout not saved* / *Retry save* / *Discard unsaved workout* with a `cloud_off` icon (`card:22-35`); discard needs confirmation (`track:334-360`); starting another workout is blocked (`prov:170-186`) | Honest and safe. Wording is technical (*local save*, *Check storage*), the icon says "cloud", and the state is memory-only (a kill loses it, `D-05`) — *Keep this screen open* appears only in a vanishing snackbar | Medium (UX-12, UX-20, UX-21) |
| **Recovery after restart** (kill, Task-Manager stop, permission revoke, reboot, screen-off freeze) | Reopens the app | *Ready to Track?* — nothing else. No startup query, no acknowledgement (`prov:57-72`; `main:57-61` only syncs on resume; `track:227-255`) | The workout is gone and the app behaves as if it never existed | Critical (UX-03; = `D-01`/`D-06`/`F1`) |
| **Logout / account switch during a workout** | Taps Logout | Dialog *Workout in progress — Finish and save the active workout, or explicitly discard it before logout.* with *Stay signed in* / **Discard & logout** (one tap, no confirmation) / *Finish & logout* (`profile:945-1024`; same shape in `main:161-282`) | Discard here is unconfirmed while the Track-screen discard is confirmed; wording is internal ("account cleanup", "explicitly discard") | High (UX-08), Medium (UX-20) |
| **Forced authentication loss during a workout** | Session revoked/expired mid-run | Auto-finish, then teardown clears the local rows (`user_scope_teardown.dart:129-131,204-208,249`) — **`SYNC-01` P0** | Out of this audit's scope; the user is never told a workout was ended or that it was deleted | See sync audit |

---

## 2. Findings, severity-ranked

Columns: **Evidence** is `file:line` in the audited tree; **A11y requirement** names the accessibility rule the fix must satisfy (Android/Material 48 dp target, WCAG 1.4.3 contrast 4.5:1, WCAG 1.4.1 no colour-only meaning, WCAG 4.1.3 status messages, WCAG 1.4.4 text resize 200 %, WCAG 2.3.3 motion, WCAG 4.1.2 name/role/value); **Test** is what must exist before the fix is called done. Wording proposals in the "Recommended" column are the short form; §3 has the exact strings.

| ID | Sev | Finding | Evidence | User impact | Recommended wording / interaction | A11y requirement | Test required |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **UX-01** | **Critical** | Loss of GPS mid-workout (stream error, services off, no fix) leaves the timer running and *Pause* visible; the only signal is a 4-s snackbar for the error case and nothing for the no-fix case. `LiveTrackingState` has no signal/interruption field | `prov:706-717` (sets `errorMessage` only); `map:360-368` (shows snackbar, clears immediately); `state:10-19` (no GPS-signal field); `track:731-755` (controls keyed on `isTracking`/`isPaused` only). = `F4`/`D-04`/`G-11` | A 30-minute run ends with 0.00 km and full active time; the user was told nothing while it happened | Add a tracking signal to state (`waitingForFix` / `recording` / `noRecentFix` after 30 s without an accepted point / `servicesOff` / `interrupted`); a persistent status line on the card; auto-pause with an `interrupted` boundary when services go off (`Geolocator.getServiceStatusStream()`, per design §7.5) — see §3 states S1–S4 | 4.1.3 status message: status line is `Semantics(liveRegion: true)`; not colour-only | Provider: emit error → `state.signal == interrupted`; fake clock: 30 s without accepted point → `noRecentFix`; services-off event → paused + `interrupted`. Widget: label text present. Device: toggle location off mid-run (§9) |
| **UX-02** | **Critical** | "Approximate" location (Android 12+) is treated as granted; every fix then fails the 50 m ceiling → silent empty workout | `svc:56-62` (`whileInUse`/`always` → granted); `PM.java:54-64` (any of FINE/COARSE granted → `whileInUse`); `gps_point_acceptance_policy.dart:86,140-144`; `manifest:4-5` declares both. = FGS audit §9 row 1 | Same as UX-01 but from the very first second, and it recurs on every workout until the user changes a setting they were never told about | At Start call `Geolocator.getLocationAccuracy()`; on `reduced` **do not start**; show S5 with *Allow precise location* (re-request shows the precise toggle) and *Open app settings* | Blocking card is reachable and labelled; button role | Provider with fake repository returning `reduced` → start refused, `locationServiceStatus` = new `approximateOnly`; widget: card text/actions; device on Android 12+ |
| **UX-03** | **Critical** | Process kill, Task-Manager *Stop*, runtime-permission revocation, reboot, or a screen-off freeze loses the workout; on relaunch the Track screen shows *Ready to Track?* with no acknowledgement. The app never warns that screen-off/background tracking is unsupported | `prov:57-72` (memory only); `main:57-61` (resume → sync only); `track:227-255` (no recovery branch); `manifest` (no FGS). = `D-01`/`D-06`/`F1`/`B-01`; FGS audit §8 "today" column | The worst outcome — a lost multi-hour hike — arrives silently, and the user could not have known to keep the screen on | Interim (before IP-3.1): S12 notice at Start, once per workout, *Keep the screen on — background tracking isn't supported yet*; keep `WakelockPlus`-style screen-on **out** (battery audit `B-12`) — the notice is honesty, not a promise. After IP-3.1/3.3: recovery card per §4 with loss acknowledgement (*Tracking stopped at 14:32 after 42 min; the last 0–5 s may be missing*) | Notice is text, dismissible, announced | Widget: notice shown on first Start of a workout; `integration_test`/ADB harness (IP-3 rollout item 4): kill → relaunch → recovery card |
| **UX-04** | High | Permanently-denied dead end: *Open App Settings* re-runs `checkPermissions()`; `openAppSettings()` is never called anywhere; the description does not name the Settings path | `track:537-546`, `:490-493`; `err:47-48`, `:12-13`; `svc:43-54`; `PM.java:184-187` (`deniedForever` only from a request result, so every tap silently re-requests). = `G-10` | The user follows the button, nothing happens, and there is no other way to recover than guessing | Call `Geolocator.openAppSettings()` (present in 14.0.2, `geolocator.dart:233`) through an injectable launcher seam; copy S7; re-check permission in `didChangeAppLifecycleState(resumed)` so returning from Settings updates the card | Button name matches action (4.1.2) | Widget: fake launcher invoked once; provider: resume re-check updates `hasLocationPermission` |
| **UX-05** | High | Permission is requested with no rationale, first at app open by the map (before any user intent), then again on *Ready to Track?* while the explanatory card is still animating in. Two un-primed denials = permanent on Android 11+ | `map:76-81` → `svc:121-127` → `svc:43-50` (`requestPermission` inside a "check"); `track:85-100` (`checkPermissions()` on tap; card expands concurrently); `_TrackScreenState` never shows text before the OS dialog. = `F10`/`B-08` | The two allowed system prompts are spent without the user ever reading why; then UX-04 | Split `checkPermissions()` into check-only and request; the map centres only if already granted; the first Start shows S6 (*Allow location to record your route*) with *Continue* → OS prompt; on *Only this time* say so (S6 note) | Rationale readable before the OS dialog; focus lands on the rationale | Service/provider: map init never calls request; widget: rationale precedes request; device: deny-twice path ends at S7 not a dead end |
| **UX-06** | High | Stale-granted trap: Start re-checks permission only when the flag is already `false`; when services are off or a one-time grant lapsed, `startTracking()` throws the specific reason, the provider discards it and shows *Failed to start workout. Please try again.* — forever, because the flag stays `true` | `prov:208-228` (`if (!state.hasLocationPermission)`); `prov:283-293` (catch keeps `hasLocationPermission`); `svc:73-78` (throws `Exception(getLocationErrorMessage(...))`) | Every retry says "try again"; the permission card that could fix it never returns until the app is restarted | Always re-check at Start; return a typed start-failure reason (`LocationServiceStatus`) instead of a message-bearing `Exception`; on failure set `hasLocationPermission=false` + status so the card switches to S6/S7/S8 | — | Provider: granted → repository now returns `servicesDisabled` → `startWorkout` → `hasLocationPermission == false`, `locationServiceStatus == servicesDisabled`, message S8 |
| **UX-07** | High | No *saved* acknowledgement on the primary Finish path; the card collapses and the map clears | `track:1132-1157` (saved → ad gate → `_collapseCard()`); only `track:302-307` says *Workout saved.* (retry path) | The user cannot tell whether Finish worked without navigating to Activities; a save-failure and a success look identical for the first second | S10 snackbar with a *View* action, or a 1-line completion summary in the card (*Saved on this device · 5.20 km · 42:10*); never the word "synced" on this screen | Announced (SnackBar is a live region, `snack_bar.dart:830`); action button labelled | Widget with a fake notifier returning `saved` → S10 present with action |
| **UX-08** | High | Discarding a live workout on the logout/exit paths is one tap with no confirmation, unlike the Track-screen discard | `profile:1008-1016` (*Discard & logout* `TextButton`); `main:244-252` (*Discard workout*); vs `track:334-360` (confirmed) | Hours of tracking can be dropped by a mis-tap next to *Stay signed in* | Second dialog S11 that names what is lost (*Discard 42:10 and 5.20 km?*); default focus on *Keep workout* | Destructive action confirmed; not the only emphasised control | Widget: choosing discard requires the second confirmation; no widget test exists today for either dialog |
| **UX-09** | High | Debug `Text`s under the map — hidden visually by the map's opaque default background (`flutter_map` `options.dart:169`, `0xFFE0E0E0`), still in the semantics tree, and visible if the map fails to paint | `track:129-135`; blame `818d571` 2025-10-04 (on `main`). = `F9` (refined: not normally visible, but reachable by TalkBack) | Screen-reader users hear internal session state; anyone sees it on a map failure | Delete the `Column` | Nothing non-UI in the semantics tree | Widget: `find.textContaining('Session State')` findsNothing |
| **UX-10** | Medium | The expanded active view shows *Avg Speed 0.0 km/h* for the whole workout (computed only at Finish), never shows *Paused* or *Est. Calories* live (also set only at Finish), and shows a raw *Points: N* count | `track:877-895`, `:938-952`; `prov:457-475` (avg speed / pausedDuration / calories set in `_stopWorkoutOnce`); `workout_session_entity.dart:54` (default `0.0`) | A false metric on screen; a panel that promises data it never has | Compute average speed live from `totalDistance / activeDuration` (same formula as completion) or hide until Finish; drop *Points* or relabel *GPS points recorded*; show live paused time from the timeline | Values are correct or absent (no misleading text) | Widget: active session with distance/time → no `0.0 km/h`; no `Points:` |
| **UX-11** | Medium | Paused/recording state has no textual label; it is inferred from which control is present, the frozen timer, and a red dashed polyline | `track:683-755` (header shows only the type); `map:197-210` (`statusError` dashed) | Sighted users can miss a pause; screen-reader users get no state at all; colour carries meaning on the map | Status chip on the card (*Recording* / *Paused* / *Waiting for GPS* / *No GPS fix* / *Location off*) as a live region; keep the dash pattern (a non-colour cue) and add it to the map legend | 1.4.1, 4.1.3, 4.1.2 | Widget: `isPaused` → *Paused* text; semantics test finds live-region node |
| **UX-12** | Medium | Every tracking error is a transient 4-s snackbar fired by the **map** widget, which then clears `errorMessage`; the recovery card's `errorMessage` slot is therefore always null in practice and falls back to generic copy | `map:360-368`; `track:282-289`; `prov:639-643`; `card:47-48` | The specific sentence (*Keep this screen open*) is gone in four seconds; the card that persists shows the vague one | Persistent inline status area on the card for interruption/save states; snackbars only for confirmations; the map stops owning error presentation | 4.1.3 — status persists until resolved | Widget: after a failed save the card shows the specific message while pending |
| **UX-13** | Medium | Starting has no dedicated content: the collapsed *Ready to Track?* stays tappable under a floating `CupertinoActivityIndicator`, plus a map *Loading location...* card, plus a green *Starting…* snackbar | `track:72-83`, `:208-217`, `:387-444`; `map:469-492` | Confusing; a second tap re-expands the chooser during start | One starting state on the card (*Starting… waiting for GPS*), controls disabled while `isLoading` | Progress has `semanticsLabel`; card not interactive while starting | Widget: `isLoading` → S0 content, chooser not tappable |
| **UX-14** | Medium | Contrast: coloured SnackBars use Material-2 light-mode default content text (white, `snack_bar.dart:895-904`; no `snackBarTheme` in `theme:272-402`) on `statusSuccess #B1CF5C` ≈ 1.8:1, `statusInfo #73A7E0` ≈ 2.5:1, `statusError #E6624A` ≈ 3.4:1 (computed); connectivity badge 11 px `#E68E4A` on `#F7F7F7` ≈ 2.4:1. Card text passes by computation (white 60–70 % over black ≥ 5:1) but at 10–12 px | `track:72-78`; `map:58-68`, `:545`, `:577`; `colors:44-49`; `connectivity_badge.dart:55-56`, `:86-92` | Start confirmation and every error message are hard to read in light mode | Add `snackBarTheme.contentTextStyle` with a dark colour for light backgrounds, or keep the default dark surface with a leading status icon; raise the badge/labels to ≥ 12 sp with ≥ 4.5:1 | 1.4.3 (4.5:1 normal text) | Widget: `expectLater(tester, meetsGuideline(textContrastGuideline))` in light theme with a snackbar shown |
| **UX-15** | Medium | Tap targets and roles: the expand/collapse `IconButton` is forced to 24×24 (`padding: EdgeInsets.zero, constraints: BoxConstraints()`; M2 default min is 48, `icon_button.dart:782`); the "drag handle" is a 40×4 unlabelled `GestureDetector`; type cards and *Ready to Track?* are `InkWell`s (tap action, no button role, `ink_well.dart:1401-1403`) | `track:699-714`, `:454-467`, `:388-390`, `:622-627` | Hard to hit; TalkBack announces an unnamed clickable element and non-buttons | Default constraints; replace the handle with a labelled *Close* `IconButton` (HugeIcon `strokeRoundedCancel01`) or `Semantics(button:true,label:'Collapse')`; wrap type cards in `Semantics(button: true, label: 'Start running')` | 48 dp target; 4.1.2 name/role | Widget: `meetsGuideline(androidTapTargetGuideline)` and `labeledTapTargetGuideline` on the Track screen |
| **UX-16** | Medium | Screen-reader structure: no `Semantics`/`MergeSemantics`/`liveRegion`/`semanticsLabel` anywhere in `lib/`; metrics read as separate value then label (*1.20 km* … *Distance*); indicators unlabelled; no `sortKey`s so card-vs-map-controls order is left to Flutter's geometric heuristic | grep (0 matches); `track:813-855`, `:958-999`, `:261`, `:215`; `map:481-487` | Slow, ambiguous navigation; status changes never announced | `MergeSemantics` per metric with label *Distance 1.20 kilometres*; `Semantics(liveRegion:true)` on the status chip; `semanticsLabel` on progress; `OrdinalSortKey` so the card precedes the map | 4.1.2, 4.1.3, 1.3.2 | Semantics widget tests (`tester.getSemantics`) per metric and status; `debugDumpSemanticsTree` review on device |
| **UX-17** | Medium | Large text: fixed `childAspectRatio: 1.5` grid cells with vertical content, a `Positioned` card with no scroll, a 32 px timer in an `Expanded` without `maxLines`; text does scale (no `noScaling`), so overflow is the expected failure at 1.5–2.0× | `track:583-611`, `:617-670`, `:138-207`, `:767-776` | Clipped chooser cells, wrapped timer digits, unreachable buttons on small phones (expected, not proven) | Intrinsic-height cells or `Wrap`; card in a `SingleChildScrollView` with a max height; `FittedBox`/`maxLines: 1` for the timer | 1.4.4 (200 %) | Widget at `TextScaler.linear(2.0)` on 360×640: no `RenderFlex` overflow exception; buttons still hit-testable |
| **UX-18** | Medium | Motion: 500 ms scale/opacity on expand, `AnimatedSize` on every timer tick, 800 ms camera flight per accepted point in follow mode — none respect `MediaQuery.disableAnimationsOf(context)` (Android "Remove animations") | `track:40-56`, `:182-184`, `:676-678`; `map:51-54`, `:651-699` | Continuous map motion for a whole workout for users who turned animations off | Zero durations / instant `move()` when disabled | 2.3.3 | Widget with `MediaQueryData(disableAnimations: true)` → no animation ticks |
| **UX-19** | Medium | The map does not follow the user by default (`_isFollowing = false`); after the initial centring the route can leave the viewport until the crosshair is tapped; any pan silently disables follow | `map:44-45`, `:124-126`, `:511-512`, `:411-416` | The most-glanced-at surface during a run stops showing the runner | Follow on while active; crosshair as a toggle with pressed state and label *Following* / *Follow*; a small *Re-centre* affordance when follow drops | Toggle exposes state (4.1.2) | Widget: location update moves the camera when following; pan → toggle off + label change |
| **UX-20** | Medium | Wording that is technical, internal, or wrong: *…enable them in device settings and restart the app* (restart is unnecessary; the app has the system *Turn on* dialog); *Location tracking cleanup was incomplete.*, *Cleanup still pending*, *Retry cleanup*, *completion handling*, *account cleanup*, *explicitly discard*, *local save*, *Check storage*; enum identifiers as UI text (*Starting running workout...*, `RUNNING`) although `getWorkoutTypeName()` exists | `err:6-17`, `:68-79`; `prov:483-486`, `:581`, `:640`, `:794`; `track:74`, `:269-271`, `:305-307`, `:688`; `main:178-215`; `profile:957-990`; `live_map_feed_helper.dart:62-73` | Users cannot tell what happened or what to do; strings are not translation-safe | Adopt §3 strings; one `TrackingStrings` file so a later l10n pass is mechanical | Plain language; localizable | Widget tests assert the exact strings (they already do for the recovery card) |
| **UX-21** | Medium | Recovery icons contradict the state: `cloud_off` for a failed **local** save (reads as network/sync), `location_disabled` for "cleanup pending" | `card:31-35` | Users go looking for Wi-Fi to fix a disk problem | HugeIcons `strokeRoundedDatabase02`/`strokeRoundedAlert02` for save-failed and `strokeRoundedGpsOff01`-class for cleanup, with named aliases in `theme` per convention | Icon meaning matches text; decorative icons excluded from semantics | Widget: icon key per state |
| **UX-22** | Low | Default map centre hard-coded to Delhi when location is unavailable, with no *location unknown* cue | `map:36-37`, `:103-105` | A user elsewhere sees a foreign city with no explanation | World/country zoom, or an overlay *Location not available yet* | — | Widget: null location → overlay text |
| **UX-23** | Low | iOS idioms in an Android-only app: `CupertinoActivityIndicator` (twice), `Icons.arrow_forward_ios` | `track:215`, `:261`, `:435` | Inconsistent with platform; Cupertino spinner has no semantics label | `CircularProgressIndicator(semanticsLabel:)`, HugeIcon chevron | Progress labelled | Widget |
| **UX-24** | Low | Localization readiness: no `flutter_localizations`/ARB, no delegates on `MaterialApp`; km/km/h/min-per-km hard-coded despite an imperial setting (known deferred, STATUS.md); `toStringAsFixed` decimal separator | `pubspec.yaml` deps; `main:148-157`; `state:85-89`, `:110-116` | Not user-visible today (English, metric); blocks any locale later | Centralise strings; format numbers through one helper; do not use `enum.name` for display | — | Golden/widget once l10n lands |
| **UX-25** | Low | Privacy surface: Recents thumbnail shows the live map/route (no `FLAG_SECURE`, no `setRecentsScreenshotEnabled(false)`); design §5.5 proposes `VISIBILITY_PUBLIC` with type/time/distance on the lock screen | `manifest:22-49`; `MainActivity.kt`; design §5.5, §7.8 | Route silhouette in the app switcher; fitness numbers on the lock screen | Acceptable defaults for a journal app (no coordinates ever shown). Options: `setRecentsScreenshotEnabled(false)` (API 33+) hides only the Recents snapshot without blocking user screenshots; a later *Hide workout details on lock screen* preference. **Do not** add `FLAG_SECURE` — it blocks the screenshots users legitimately take of their own workout | — | Device: Recents thumbnail and lock-screen notification review |
| **UX-26** | Low | In both confirmations the destructive action is the only filled (red) button while the safe action is a text button — the visually dominant target is the destructive one | `track:347-358`, `:1098-1107` | Mis-taps favour the irreversible choice | Keep red for destructive; give the safe action equal weight (`OutlinedButton`) and default focus | Both actions labelled and reachable | Widget: focus order |
| **UX-27** | Low | Double-tapping *Grant Permission* while the OS dialog is up throws the plugin's request-in-progress error, which the notifier reports as *Failed to check location permissions.* and mislabels as `permissionDenied`; the button is enabled while `isLoading`. Rare edge: an empty `grantResults` (interrupted dialog) never calls back and `isLoading` never clears | `prov:119-127`; `track:536-547`; `PM.java:148-153` | Spurious error toast; a possible stuck spinner | Disable the button while `isLoading`; treat in-progress as a no-op; keep `locationServiceStatus` unchanged on unknown errors | Disabled state exposed | Provider: repository throws → no status change; widget: button disabled while loading |

---

## 3. Exact user-facing messages for critical states

Rules applied: no coordinates, no fix timestamps, no raw error strings, no "synced" on this screen, and no sentence that claims tracking/saving/continuing unless the code has proven it. Durations and distances are allowed. Where a message depends on IP-3.x, the row says so.

| # | State (trigger) | Where | Title | Body | Primary action | Secondary | Must not say |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S0 | Starting (`isLoading` after a type tap) | Card | *Starting…* | *Waiting for a GPS fix. Time starts when the workout starts; distance starts at your first accurate location.* | — | *Cancel* | "Tracking" until the first accepted point |
| S1 | Recording (≥ 1 accepted point in the last 30 s) | Card status chip | *Recording* | — | Pause · Finish | — | — |
| S2 | No fix yet / no recent fix (0 accepted points, or > 30 s without one, while active) | Card status chip + line | *Waiting for GPS* | *No accurate location for {n} s. Time is still counting; distance isn't. Head for open sky.* | Pause | Finish | "Interrupted" (nothing broke), "tracking continues" |
| S3 | Location services switched off mid-workout (services event / stream error) — after auto-pause lands (IP-3.1/design §7.5); before that, use the interim body | Card status chip + line; later notification | *Paused — location is off* | *Your workout is paused because device location was turned off. Turn it on, then tap Resume.* Interim (today's code, no auto-pause): *Location was lost. Time is still counting; distance isn't. Check that device location is on.* | *Turn on location* (system dialog) → *Resume* | Finish | "Tracking was interrupted" alone; anything implying auto-resume |
| S4 | Provider/stream error while services are on | Card status line | *GPS lost* | *No location updates are arriving. Time is still counting; distance isn't. If this continues, pause and check location settings.* | Pause | Finish | "Please try again" (there is nothing to retry) |
| S5 | Approximate-only grant (Android 12+, `getLocationAccuracy() == reduced`) — **blocks Start** | Card | *Precise location needed* | *RythmRun has approximate location only, which can't record a route. Allow precise location to start.* | *Allow precise location* (re-request) | *Open app settings* | Starting anyway |
| S6 | First request / denied once (rationale before the OS prompt) | Card | *Allow location to record your route* | *RythmRun uses your location only while you're recording a workout, to draw the route and measure distance. Choose "While using the app" and "Precise". If you choose "Only this time", you'll be asked again next workout.* | *Continue* → OS prompt | *Not now* | "Always" (not requested), background claims |
| S7 | Permanently denied | Card | *Location is blocked for RythmRun* | *Android won't ask again. Open Settings → Permissions → Location and choose "Allow only while using the app" with "Use precise location" on.* | *Open app settings* (`openAppSettings()`) | — | "Grant permission" (the button can't) |
| S8 | Location services off at Start | Card | *Turn on device location* | *Location is switched off on this phone. Turn it on to start a workout.* | *Turn on location* (system dialog) | — | "restart the app" |
| S9 | Finish confirmation (in-app) | Dialog | *Finish workout?* | *Your {type} will end and be saved on this device. A finished workout can't be resumed.* If paused: *…The current pause ends now.* | *Finish & save* (destructive style) | *Keep going* | "cannot be undone" as the only explanation |
| S10 | Saved (primary path) | Snackbar with action / card line | — | *Saved on this device · {distance} · {active time}* | *View* (Activities → detail) | — | "Synced", "uploaded", "backed up" |
| S11 | Discard confirmation (any path: Track screen, logout, exit resolution) | Dialog | *Discard this workout?* | *{active time} and {distance} will be deleted from this phone. This can't be undone.* | *Keep workout* (default focus) | *Discard* (destructive) | — |
| S12 | Interim honesty notice at Start (until IP-3.4 device evidence exists) | Card line, once per workout | *Keep the screen on* | *Background tracking isn't supported yet. If the screen turns off or the app is closed, the workout stops and can't be recovered.* | *Got it* | — | Any hedge implying it "may" continue |
| S13 | Save failed | Card (persistent) | *Workout not saved* | *Your finished workout is only in memory. Keep this screen open and tap Retry. If storage is full, free some space first.* | *Retry save* | *Discard workout* (→ S11) | "Check storage" alone; cloud/sync language |
| S14 | GPS shutdown pending after save | Card (persistent) | *Finishing up* | *Your workout is saved. GPS is still switching off; tap Retry if this doesn't clear in a few seconds.* | *Retry* | — | "cleanup" |
| S15 | Recovered after restart — active/paused checkpoint (IP-3.3) | Recovery card | *Workout interrupted* | *Recording stopped at {clock time} after {active time} and {distance}; up to 5 seconds may be missing. Time since then is not counted.* | *Resume* (starts service from the visible screen) | *Finish* · *Discard* (→ S11) | "Resumed automatically"; any coordinates |
| S16 | Recovered — `starting` with no points | Recovery card | *Workout didn't start* | *A workout was starting when the app closed. Nothing was recorded.* | *Start again* | *Discard* | Finish (no data) |
| S17 | Recovered — `finishing` without a completed row | Recovery card | *Workout not saved* | *The app closed while saving {active time} · {distance}.* | *Retry save* | *Discard* (→ S11) | Resume |
| S18 | Notification permission denied (API 33+, IP-3.4) | Card line, once per workout | — | *Notifications are off, so Pause and Finish won't appear in your notification shade. Tracking still continues while the workout runs.* (design §7.7 wording, kept) | *Notification settings* | — | Telling the user to use a control that can't be shown |

---

## 4. Recovery UX decision tree

```text
App launch / activateUserScope(userId)
│
├─ TODAY (d0e5b92): no checkpoint exists → nothing to recover → Track shows "Ready to Track?"
│    Honest minimum until IP-3.1: S12 at Start; nothing else can be claimed.
│
└─ WITH IP-3.1–3.3 (design §7.5, IP-3.3 policy 1–8):
   query checkpoint WHERE user_id = current user only (other users' rows never read)
   │
   ├─ none ──────────────────────────────► normal Track screen
   │
   ├─ validation fails ──────────────────► preserve row; card "Couldn't read the interrupted
   │                                        workout" + stable code; no auto-delete; support path
   │
   ├─ state = starting, 0 points ────────► S16: Start again | Discard   (never Finish)
   │
   ├─ state = finishing
   │    ├─ completed row (user_id, client_sync_id) exists ─► delete only the owned checkpoint,
   │    │                                                     show S10 "Saved on this device"
   │    └─ no completed row ──────────────────────────────► S17: Retry save | Discard (never Resume)
   │
   ├─ state = active ────────────────────► append `interrupted @ last_flushed_at`, set paused
   │                                        (unknown downtime excluded) → S15
   └─ state = paused ────────────────────► pause stays open → S15
        │
        S15 actions (exactly three, current user only):
        ├─ Resume ─┬─ location permission missing/approximate/services off?
        │          │     └─ yes → S6/S5/S8 gate FIRST; Resume stays disabled until granted
        │          └─ ok → start FGS from the visible screen (design §7.7), append `active`,
        │                  first accepted point anchors zero distance; status chip S2 until a fix
        ├─ Finish ─► finalize at last durable boundary → S10 or S13/S17 on failure
        └─ Discard ► S11 confirmation → delete owned checkpoint → "Workout discarded" snackbar
   
   Never: auto-resume location after reboot/login/kill without a user action and a visible
   notification (IP-3.3 policy 6). Never: offer another account's checkpoint (policy 7).
```

Two UX rules that the design's tree does not state explicitly and that this audit adds:

1. **Permission gate before Resume.** After a revocation-kill or a lapsed one-time grant, the recovery card must resolve permission first (S6/S5/S7/S8) and keep *Resume* disabled with a reason, otherwise UX-06 recurs inside recovery.
2. **Acknowledge the loss in numbers, not in apology.** S15 states the last known active time and distance and the bounded loss ("up to 5 seconds"), which is the IP-3 durability objective; it never states where the user was.

---

## 5. Notification labels and Finish confirmation (assessment of the IP-3.4 design; nothing exists in code)

Baseline: design §5.5/§7.4 and FGS-audit §7 already specify channel `workout_tracking`, LOW importance, silent, ongoing, chronometer, actions Pause/Resume then Finish, body tap → Track tab, no coordinates, "Saving workout…" with no actions while finishing, and *optionally* a two-tap Finish "recommended off for the first release".

Recommended labels (all ≤ 20 characters so they fit two actions on every OEM shade):

| State | Title | Text | Actions |
| --- | --- | --- | --- |
| starting | *RythmRun · Running* | *Starting…* | none |
| active, recent fix | *RythmRun · Running* | *Recording · 3.2 km* + chronometer | **Pause** · **Finish** |
| active, no fix > 30 s | *RythmRun · Running* | *Waiting for GPS · 3.2 km* + chronometer | **Pause** · **Finish** |
| paused (user) | *RythmRun · Running* | *Paused · 3.2 km · 23:15* | **Resume** · **Finish** |
| paused (location off) | *RythmRun · Running* | *Paused — location is off · 3.2 km* | **Resume** · **Finish** (Resume opens the app to S3 if services are still off) |
| finish tapped, awaiting confirmation | *Finish workout?* | *3.2 km · 23:15 will be saved on this device* | **Finish** · **Keep going** (auto-reverts to the previous row after 10 s) |
| finishing | *RythmRun · Running* | *Saving…* | none |
| saved | (FGS notification removed) optional non-ongoing, auto-cancelling summary: *Saved on this device · 3.2 km · 23:15* with `setTimeoutAfter(60 s)` | — | none |
| save failed | *Workout not saved yet* | *Open RythmRun to retry* (regular notification, design §7 row `finishing`) | body tap → recovery card |

Assessment and departures from the design:

- **Finish is destructive and must be confirmed in the shade too.** In-app Finish already requires a dialog (`track:1083-1111`); a shade Finish that ends the workout on one tap is *less* protected than the in-app path even though a lock-screen tap is more accident-prone (pocket, swipe). The code has no undo: `stopWorkout` writes the completed row and nulls the timeline (`prov:476-495`), and nothing can reopen a finished workout. Recommendation: **ship the two-tap Finish ON** (design §7.4's optional variant, transient Dart state, no durable write, auto-revert 10 s), not off. Alternative if the maintainer rejects two-tap: make the shade *Finish* action a `PendingIntent.getActivity` that opens the app to S9 (allowed — the trampoline ban covers activities started *after* a broadcast/service, not an action's own activity intent); it costs the one-handed convenience.
- **Label is "Finish" everywhere, never "Stop"/"End".** In-app the Finish control uses the `Icons.stop` glyph (`track:747`); keep the word *Finish* on the glyph in both places so the shade and the screen teach the same vocabulary. Pause/Resume are correct and reversible; no confirmation.
- **Notification tap behaviour.** Body tap → Track tab; if a recovery card is pending, land on it; never choose a workout by ID from the intent (design §7.4). Add: when the tap arrives while S3/S5/S7 applies, land on that card, not on a *Resume* button that cannot work.
- **Honesty in the text.** *Recording* only while points are being accepted; *Waiting for GPS* otherwise (§3 S2). *Tracking · 3.2 km* (design wording) is acceptable but *Recording* is the more precise verb because it is what the checkpoint proves.
- **Saved summary.** The design and FGS audit choose no completion notification to avoid a second notification. From the shade-only user's perspective the FGS notification simply vanishes; a 60-second auto-cancelling summary is the cheapest truthful confirmation and cannot mislead. Maintainer decision.
- **Lock screen.** `VISIBILITY_PUBLIC` is acceptable because the payload is type/time/distance and never location (design §7.8, UX-25); if the app later adds a preference, default it to public.
- **Dismissed notification (Android 13/14 default-dismissible).** Design/FGS audit: continue tracking, re-post on the next transition. From a UX view add one in-app line when the app is next opened: *Your workout is still recording; the notification was dismissed* — otherwise the absence of the notification silently reads as "not tracking".

---

## 6. Accessibility findings in one place

| Area | Today | Requirement | Where the fix lives |
| --- | --- | --- | --- |
| Semantic labels | None in `lib/`; icons unlabelled; `CupertinoActivityIndicator`/`CircularProgressIndicator` without labels (`track:215,261`; `card:63-67`; `map:481-487`) | Every control has a name; decorative icons excluded; progress labelled | UX-15, UX-16, UX-23 |
| Screen-reader order | No `sortKey`; Stack children = debug texts, map (attribution link + 4 buttons), card; order left to geometry (`track:126-221`) | Card (primary controls) before map controls; debug nodes removed | UX-09, UX-16 |
| Status announcements | Only SnackBars are live regions (`snack_bar.dart:830`), 4 s, fired by the map | Persistent status chip as `liveRegion`; pause/GPS/save states announced | UX-01, UX-11, UX-12 |
| Tap targets | Expand toggle 24×24 (`track:712-713`); handle 40×4 (`track:454-467`); others ≥ 48 via M2 `_InputPadding` | ≥ 48×48 dp for every control | UX-15 |
| Large text | Scales (good); fixed grid aspect, non-scrolling card, unbounded timer (`track:583-611,138-207,767-776`) | 200 % without overflow or unreachable buttons | UX-17 |
| Contrast | SnackBars ≈ 1.8–3.4:1 in light mode; badge ≈ 2.4:1; card small text ≥ 5:1 by computation | ≥ 4.5:1 normal text | UX-14 |
| Colour-only meaning | Paused = red dashed line only; state = which button exists (`map:197-210`; `track:734-745`) | Text label + pattern | UX-11 |
| Motion | 500/300/800 ms animations ignore `disableAnimations` (`track:40-56,182,676`; `map:651-699`) | Honour reduce-motion | UX-18 |
| Localization | English literals; enum names as text; hard-coded units (`track:74,688`; `state:85-116`) | Centralised, translation-safe strings | UX-20, UX-24 |
| Roles | `InkWell` cards (tap, no role); IconButtons have tooltips → names (good, `map:442-465`) | Buttons announced as buttons | UX-15 |

---

## 7. Privacy check (item 8)

- **Lock-screen notification:** none today; design payload = type/state/elapsed/distance only — acceptable (UX-25).
- **App switcher:** Recents snapshot shows the live map/route; consider `setRecentsScreenshotEnabled(false)` on API 33+; do not use `FLAG_SECURE` (blocks legitimate user screenshots of their own workout).
- **Screenshots:** unrestricted — correct for a journal.
- **UI detail exposure:** the Track screen shows the route on the map (necessary), *Started HH:MM* local time (`track:933-937`), and a raw *Points* count (UX-10); no coordinates, no fix timestamps. `TrackingPointEntity.toString()` redacts coordinates (`tracking_point_entity.dart:55-58`); no tracking-path `debugPrint`/`log` calls exist (grep). `LiveTrackingState.toString()` prints only flags/distance/status (`state:147-150`).
- **Error text:** the messages proposed in §3 carry durations/distances only; the service's `Exception('Failed to start location tracking: $e')` (`svc:94`) embeds a raw plugin error but is caught and replaced before display (`prov:283-293`) — keep it that way when adopting typed reasons (UX-06).

---

## 8. Honest state vocabulary (item 9)

| Claim | May be shown when | Evidence today | Today's gap |
| --- | --- | --- | --- |
| **Recording** | ≥ 1 accepted point in the last 30 s and `isTracking` | not shown | State implied by the *Pause* button even with zero points (UX-01) |
| **Waiting for GPS** | active, no accepted point yet / none in 30 s | not shown | (UX-01/02) |
| **Paused** (user) | `WorkoutStatus.paused` | *Resume* button only | No label (UX-11) |
| **Paused — location is off** | services event / stream error after auto-pause | not implemented | Only a vanishing snackbar (UX-01, `G-11`) |
| **Interrupted** | recovery only: checkpoint `active` with the process gone (IP-3.3) | none | No recovery (UX-03) |
| **Saving…** | `_isFinishingWorkout` | *Finishing workout…* | wording (UX-20) |
| **Saved on this device** | `LiveWorkoutFinalizationStatus.saved` | retry path only | primary path silent (UX-07) |
| **Not saved yet** | `savePending` (in memory) | *Workout not saved* card | wording/icon (UX-13/21) — never say "queued" |
| **Synced** | never on the Track screen (sync status is IP-4.1; no per-workout indicator exists in the history list either) | — | Do not introduce it here |

---

## 9. Test requirements

**Widget (`flutter test`, no device)** — none exist for `TrackScreen`, `LiveMapFeed`, or the logout/exit dialogs today (`test/` grep):

1. Track screen states: idle, starting (`isLoading`), permission (`permissionDenied`, `permissionDeniedForever`, `servicesDisabled`, new `approximateOnly`), active with/without a recent fix, paused, finishing, save-pending, cleanup-pending, saved — each asserting the §3 strings and the presence/absence of the status chip.
2. Debug text absent (UX-09). Finish and discard confirmations render the S9/S11 copy; discard from the profile/exit dialogs requires the S11 confirmation (UX-08).
3. `expectLater(tester, meetsGuideline(androidTapTargetGuideline | labeledTapTargetGuideline | textContrastGuideline))` in light and dark themes with a snackbar visible (UX-14/15).
4. `TextScaler.linear(2.0)` at 360×640: `tester.takeException()` is null; *Finish* and *Pause* still hit-testable (UX-17).
5. `MediaQueryData(disableAnimations: true)`: expanding the card and a follow-mode location update settle without pumping animation frames (UX-18).
6. Semantics: `tester.getSemantics(find.byKey('metric-distance'))` has a merged label; the status chip node has `isLiveRegion`; the settings launcher seam is invoked once for `permissionDeniedForever` (UX-04/16).

**Provider (`LiveTrackingNotifier`, fake repository/clock, existing harness in `live_tracking_provider_test.dart`)**:

7. Stream error → `signal == interrupted`, `isTracking` unchanged, no false `Pause` semantics until auto-pause exists; services-off event → paused + `interrupted` boundary (UX-01).
8. `checkPermissions` result `reduced` → Start refused with `approximateOnly` (UX-02).
9. Granted flag stale, repository now `servicesDisabled` → Start sets `hasLocationPermission=false` and the specific status (UX-06).
10. Fake clock: 30 s without an accepted point → `noRecentFix`; next accepted point → `recording` (UX-01).
11. Repository throws request-in-progress → state unchanged, no snackbar (UX-27).

**Accessibility review (device, once per release)** — TalkBack linear swipe through the Track screen (order, names, live status), Switch Access reach for Pause/Finish, font size 200 % + display size largest, "Remove animations" on, light and dark, `adb shell dumpsys accessibility`/`debugDumpSemanticsTree()` capture for the evidence log (no coordinates in the dump — the map markers must not carry them).

**Physical device (append to MC-1.5 / IP-3.4 matrix; emulator-only is insufficient)** — on ≥ 1 Android 12+ and ≥ 1 Android 14+ device: (a) deny → deny → confirm S7 opens Settings and returning updates the card; (b) *Approximate* → confirm Start is blocked with S5 and *Allow precise location* re-prompts; (c) *Only this time* → background the app for the platform grace period → confirm the next Start re-prompts and no false *Recording* state was shown; (d) turn location services off at minute 5 of a run → confirm S3 within 5 s, active time stops accruing after auto-pause lands, resume requires the *Turn on* dialog; (e) indoors start → S2 visible, timer counting, distance 0.00, no *Recording* claim; (f) Finish → S10 with *View* opening the saved workout; (g) inject a save failure → S13 persists across a tab switch and back; (h) **today**: screen off 5 min → document that time accrues and distance does not, that S12 warned, and that no *Recording* claim was made — this run produces the evidence that "background tracking is not supported" is stated truthfully, not that it works; (i) after IP-3.4 only: the shade two-tap Finish, auto-revert, and the saved summary; lock-screen content review; Recents thumbnail review.

---

## 10. Staged implementation plan (no code written here)

Every stage is behind widget/provider tests, touches no schema, and rolls back by revert. Stages 0–2 do not depend on IP-3.1 and can land first; each is one PR.

| Stage | Depends on | Scope | Findings closed | Tests (from §9) | Rollback trigger |
| --- | --- | --- | --- | --- | --- |
| **0 — Truth and dead-ends** (≈ 1 day) | nothing | Delete debug texts; `openAppSettings()` via an injectable launcher; always re-check permission at Start with a typed reason; disable *Grant Permission* while loading; S10 saved acknowledgement; S11 confirmation on the logout/exit discard paths; recovery-card icons + named aliases (HugeIcons); wording pass to §3 strings in one `TrackingStrings` file; `snackBarTheme` contrast; expand toggle default constraints; drag handle → labelled *Close* | UX-04, 06, 07, 08, 09, 14, 15 (part), 20, 21, 23, 27 | 1, 2, 3, 6, 9, 11 | Any existing provider test regresses → revert; nothing durable changes |
| **1 — Signal state and permission journey** (≈ 2–3 days) | Stage 0 | `signal` field in `LiveTrackingState`; status chip (live region) with S0–S4; interim S3 body until auto-pause; approximate-only check at Start (S5); rationale-before-request (S6) and no request at app open (map centres only if already granted); S12 interim honesty notice at Start; follow-by-default toggle with state; live avg speed or hide; drop *Points* | UX-01 (UI half), 02, 03 (interim), 05, 10, 11, 12, 13, 19 | 1, 7, 8, 10; device (a)–(e), (h) | Regression in MC-1.5 or `flutter test` → revert; the notice/S-strings can be reverted independently |
| **2 — Accessibility layer** (≈ 2 days) | Stage 1 | `MergeSemantics` per metric; `semanticsLabel` on progress; `OrdinalSortKey` card-before-map; large-text layout (`Wrap`/scrollable card/`FittedBox`); honour `disableAnimations`; type cards as buttons; connectivity-badge size/contrast; Delhi default → overlay | UX-15 (rest), 16, 17, 18, 22 | 3, 4, 5, 6; accessibility review | Visual regression only → revert per widget |
| **3 — Auto-pause and recovery UX** | IP-3.1 engine (`getServiceStatusStream` auto-pause per design §7.5) and IP-3.3 | S3 real auto-pause; recovery card per §4 (S15–S17) with the permission gate before Resume; loss acknowledgement in numbers; remove S12 only when device evidence for IP-3.4 exists | UX-01 (engine half), UX-03 | IP-3 failure-injection + `integration_test` kill/relaunch | Design §10 rollback: service stops, checkpoints preserved |
| **4 — Notification controls** | IP-3.4 | Labels per §5; two-tap Finish ON with auto-revert; S18 notification-permission copy; saved summary (maintainer decision); lock-screen visibility decision; `setRecentsScreenshotEnabled(false)` decision (UX-25) | UX-25; item 5 of the brief | Physical-device matrix (i); T-11 dismissed-notification behaviour from the FGS audit | Design §10 |

Conventions to respect while doing it (from CLAUDE.md): convert Material icons to HugeIcons only in widgets being edited and add named aliases in `theme`; use `spacing*`/`iconSize*` constants and `textTheme` styles instead of the raw sizes now in `track` (`fontSize: 10/11/12/14/22/32`, icon `14/16/18/20/28/56`); keep the settings launcher and any new side effect injectable so widget tests can observe it; keep the recovery card's `ValueKey`s used by the existing tests.

---

## Appendix A — What was checked and found acceptable (do not "fix")

- Pause/resume/finish arithmetic and the paused zero-distance bridge (IP-1.2 tests, `live_tracking_provider_test.dart:42-180`).
- Duplicate Start/Finish serialization, save-failure retention, discard requiring explicit confirmation on the Track screen (`prov:155-168`, `:391-403`, `:556-565`; `track:334-360`).
- Confirmation before Finish exists in-app; the destructive button is styled as destructive.
- SnackBars are announced to screen readers (`snack_bar.dart:830`); map control buttons carry tooltips that become names (`map:442-465`); bottom navigation items are labelled (`home_screen.dart:117-120`).
- `IndexedStack` excludes hidden tabs from semantics, so no cross-tab leakage (`home_screen.dart:107`).
- No coordinates, timestamps, or route payloads on any tracking log path; `TrackingPointEntity.toString()` redacts.
- The recovery card never offers *Discard* for the cleanup-only state (`card:75-85`, tested).

## Appendix B — Explicitly not verified here

- No `flutter test`, `flutter analyze`, build, emulator, or device run. Overflow at 200 % text, TalkBack traversal order, and the empty-`grantResults` hang are *expected from the code* and marked as such.
- Contrast ratios are computed (WCAG relative-luminance formula on the hex values and Flutter M2 defaults), not measured on hardware; OEM display tuning can shift them.
- Android one-time-permission expiry timing and its process-termination behaviour are taken from the FGS audit §9 / platform documentation, not observed.
- The IP-3.4 notification recommendations describe a design that has no code; nothing in this document claims background tracking, notification actions, or recovery work today.
