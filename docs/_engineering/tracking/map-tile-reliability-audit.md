---
published: false
---

# Map rendering and tile-provider reliability audit

| Field | Value |
| --- | --- |
| Date | 2026-08-18 |
| Scope | Map rendering and tile-provider reliability only: `LiveMapFeed`, `WorkoutHistoryMapViewer`, `OpenStreetMapAttribution`, the `FlutterMap`/`TileLayer` configuration, map helpers/segment builder, `pubspec.yaml`, and the pinned `flutter_map` / `http` package sources that decide the real network contract |
| Method | Static read of the working tree at `d0e5b92` (branch `auth-impr`) plus the pinned package sources in the pub cache (`flutter_map 8.3.1`, `http 1.6.0`, Flutter `3.44.1`). The OSMF Tile Usage Policy, Attribution Guidelines and the flutter_map documentation were fetched on 2026-08-18 and are quoted below |
| Not done | No build, no `flutter test`, no device or emulator run, no network capture, **no request was sent to `tile.openstreetmap.org`**. No code was changed |
| Verdict | **Amber.** Tracking and saving never depend on tiles; the map degrades passively (blank tiles, no indicator, no retry, tile URLs logged in release) and grows heavier through a follow-mode workout. Usable for personal testing now; not release-grade until the Stage B/C fixes below land. None of them needs a paid provider or a new dependency |

Evidence classes used throughout:

- **[R]** — verified repository or pinned-package fact, with `file:line`.
- **[P]** — requirement quoted from the official OSMF Tile Usage Policy
  (<https://operations.osmfoundation.org/policies/tiles/>, fetched 2026-08-18)
  or the OSMF Attribution Guidelines
  (<https://osmfoundation.org/wiki/Licence/Attribution_Guidelines>).
- **[A]** — assumption or estimate that was not verified in this audit.

Line references into `flutter_map` and `http` are into the pub-cache copies
`~/.pub-cache/hosted/pub.dev/flutter_map-8.3.1/lib/...` and
`~/.pub-cache/hosted/pub.dev/http-1.6.0/lib/...` (the versions locked in
`rythmrun_frontend_flutter/pubspec.lock`).

## 1. Executive verdict

**Reliability.** The map is decorative for the product's core promise. GPS
acceptance, metrics, and the SQLite save run entirely through
`LiveTrackingService` → `LiveTrackingNotifier` → `WorkoutRepository`; the map
only *reads* provider state and every tile failure is swallowed inside
`flutter_map`'s `TileImage` (§6). A workout is never lost because tiles fail.
What is missing is everything around that: a failed tile is a blank grey square
with no message, nothing retries when the network returns, and there is no
route-only mode on the live map even though the history viewer already has one
(§5). Two defects make a long follow-mode workout progressively heavier —
`_animatedMove` leaks two animation status listeners per call and replays every
past destination on each completion (M-05), and every per-second rebuild
constructs a fresh `NetworkTileProvider`, i.e. a fresh `HttpClient` with no
connection reuse (M-16). Neither is a crash; both are wasted CPU, battery and
network that IP-3.5 will otherwise inherit.

**Compliance.** The URL, HTTPS, absence of `{s}` subdomains, attribution, HTTP
caching, conditional requests, and the absence of any prefetch/offline feature
all satisfy the current OSMF policy as it reads today (§3). Two gaps: the
`User-Agent` is the library-formatted `flutter_map (com.github.cosmicsaurabh.rythmrun)`
— distinct and stable, which flutter_map's documentation treats as sufficient,
but not the OSMF-recommended "app name + contact" form (M-02); and the tile URL
is hard-coded in two files, so a block or URL change cannot be absorbed without
a store release, which the policy explicitly recommends against (M-01). The
policy also warns that "capacity is limited", that "access may be blocked
without prior notice", and that "commercial services, or those that seek
donations, should be especially aware that access may be withdrawn at any
point" — relevant because IP-5.5 plans ads.

**Privacy.** Any online raster map discloses the device IP, the app identity,
and the coarse map area (a z16 tile is roughly 400–600 m across in mid
latitudes, a z19 tile 50–75 m) with timing to the tile operator; that is
inherent and must be disclosed (STATUS.md already lists the missing
privacy-policy sentence under IP-5.6). App-side, three avoidable leaks exist:
tile URLs are printed to logcat in **release** builds on every failed tile
(M-03); the map acquires a GPS fix and triggers the OS permission prompt at app
launch, before any workout intent (M-07); and the tile disk cache is
device-wide, not user-scoped and not cleared on logout (M-08). No analytics or
third-party SDK sits in the map path, and no exact coordinate leaves the device
through the map.

**Highest-value fixes** (all Flutter-only, all backward compatible, no backend
change, no new dependency): one shared tile configuration with an explicit UA
and `--dart-define` endpoint (M-01/M-02), `silenceExceptions: true` on the tile
provider (M-03), a connectivity-driven "Map unavailable — recording continues"
chip plus route-only toggle and reload-on-reconnect (M-04), and the two lifetime
fixes in `LiveMapFeed` (M-05, M-16).

## 2. Current implementation facts

### 2.1 Tile source, identification, caching

| # | Fact | Evidence |
| --- | --- | --- |
| F-01 | Both map screens use `flutter_map` `TileLayer` with `urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'`, `userAgentPackageName: 'com.github.cosmicsaurabh.rythmrun'`, `maxZoom: 19`; no `tileProvider`, `errorTileCallback`, `errorImage`, `fallbackUrl`, `reset`, `tileBounds`, `retinaMode`, or `tileBuilder` is passed | [R] `lib/presentation/features/Map/screens/live_map_feed.dart:423-428`; `lib/presentation/features/tracking_history/screens/workout_history_map_viewer.dart:390-396` |
| F-02 | The URL is HTTPS, has no `{s}` placeholder (so the default `subdomains: ['a','b','c']` is unused), and is a string literal in two files — no constant, no `--dart-define`, no config class | [R] same lines; `lib/core/config/` contains no map/tile setting |
| F-03 | Pinned versions: `flutter_map ^8.2.2` → **8.3.1**, `latlong2` 0.9.1, `http` 1.6.0, `connectivity_plus` 6.1.5, `url_launcher` 6.3.2 | [R] `pubspec.yaml:67-68`; `pubspec.lock` (`flutter_map` `version: "8.3.1"`, `http` `version: "1.6.0"`) |
| F-04 | The `User-Agent` actually sent is `flutter_map (com.github.cosmicsaurabh.rythmrun)`: `TileLayer` calls `tileProvider.headers.putIfAbsent('User-Agent', () => 'flutter_map ($userAgentPackageName)')` on non-web platforms, so an explicit header on a `NetworkTileProvider` would win | [R] `flutter_map/src/layer/tile_layer/tile_layer.dart:279-285` |
| F-05 | Default provider is `NetworkTileProvider()` → `RetryClient(Client())`; defaults `silenceExceptions: false`, `attemptDecodeOfHttpErrorResponses: true`, `abortObsoleteRequests: true`, `cachingProvider: null` (→ built-in cache) | [R] `tile_layer.dart:276`; `tile_provider/network/tile_provider.dart:34-42` |
| F-06 | `Client()` on Android is `IOClient()` → a new `dart:io` `HttpClient` (HTTP/1.1, no per-request timeout, no `maxConnectionsPerHost` bound); `RetryClient` defaults: 3 retries **only on HTTP 503**, never on thrown errors, delays 500 ms × 1.5ⁿ | [R] `http/src/client.dart:42`, `http/src/io_client.dart:14-20,101`; `http/retry.dart:62-72,182-187` |
| F-07 | Built-in disk cache is on by default: files under `getApplicationCacheDirectory()/fm_cache` (Android app cache dir), keyed by UUIDv5 of the URL, default `maxCacheSize` 1 GB, freshness from `Cache-Control: max-age`/`Expires` (age-adjusted), **fallback 7 days** when headers are insufficient, `ETag`/`Last-Modified` stored and replayed as `If-None-Match`/`If-Modified-Since`; a background isolate writes files and trims size | [R] `tile_provider/network/caching/built_in/built_in_caching_provider.dart` (factory params); `.../impl/native/native.dart` (`fm_cache`, isolate); `.../caching/tile_metadata.dart:34-92`; `.../image_provider/image_provider.dart:164-259` |
| F-08 | A fresh cached tile is served without a request; a stale cached tile triggers a conditional GET; if that request throws (offline) the tile **errors** — the stale bytes on disk are *not* used as a fallback | [R] `image_provider.dart:213-234, 300-331` |
| F-09 | On error the provider evicts the image and rethrows unless `silenceExceptions` is true, in which case a transparent tile is returned and no error is reported | [R] `image_provider.dart:300-331` |
| F-10 | `_TileLayerState._onTileLoadError` calls `debugPrint(error.toString())` **unconditionally**, then the (unset) `errorTileCallback`. `ClientException.toString()` is `'ClientException: $message, uri=$uri'`; `NetworkImageLoadException` renders `'HTTP request failed, statusCode: $statusCode, $uri'`. Flutter's `debugPrint` "logs to console even in release mode" | [R] `tile_layer.dart:724-727`; `http/src/exception.dart` (`toString`); Flutter `packages/flutter/lib/src/painting/image_provider.dart:1880-1884`; Flutter `packages/flutter/lib/src/foundation/print.dart:34-50` |
| F-11 | An errored tile with no `errorImage` renders `RawImage(image: null)`, i.e. the map `backgroundColor` shows through; the live map uses flutter_map's default `Color(0xFFE0E0E0)`, the history viewer `Colors.transparent` (tiles on) or `Colors.grey` (tiles off) | [R] `tile.dart:82-94`; `map/options/options.dart:169`; `live_map_feed.dart:402-421` (no `backgroundColor`); `workout_history_map_viewer.dart:385-386` |
| F-12 | Errored tiles are never re-requested: `createMissingTiles` only starts loads for tiles whose `loadStarted == null`; recovery requires the tile to be pruned and recreated (pan/zoom), a `TileLayer` reset stream (unused), or the `TileLayer` widget being removed and re-added | [R] `tile_image_manager.dart:88-109`; `tile_layer.dart:685-717, 767-770` |
| F-13 | Obsolete in-flight requests are aborted (`abortObsoleteRequests: true`) when a tile is pruned; `IOClient` opens the request before registering the abort, so cancellation is applied before the body is sent in the common path | [R] `tile_provider.dart:39,122`; `image_provider.dart:144, 295-299`; `http/src/io_client.dart:105-146`. Whether an aborted request ever reaches the socket is timing-dependent [A] |
| F-14 | flutter_map prints a **debug-mode-only** OSM policy reminder when the URL contains `tile.openstreetmap.org`, with extra warnings for a missing UA or `{s}`; nothing is printed in profile/release | [R] `tile_layer.dart:322-362, 392` |
| F-15 | The app defines no `HttpOverrides`, zone `Client`, tile cache configuration, or map config; nothing in `lib/` references `flutter_map` outside the three map files and the attribution widget | [R] `grep` over `lib/` (only `Map/screens/*`, `tracking_history/screens/workout_history_map_viewer.dart`, `common/widgets/open_street_map_attribution.dart`) |

### 2.2 Attribution

| # | Fact | Evidence |
| --- | --- | --- |
| F-16 | `OpenStreetMapAttribution` wraps flutter_map's `SimpleAttributionWidget` with source text `'OpenStreetMap contributors'`, bottom-left, 88 % surface background; tap launches `https://www.openstreetmap.org/copyright` externally through an injectable `urlLauncher` seam | [R] `lib/presentation/common/widgets/open_street_map_attribution.dart:9-39` |
| F-17 | `SimpleAttributionWidget` renders `'flutter_map \| © '` + source inside a `SafeArea`, so the visible text is **"flutter_map \| © OpenStreetMap contributors"** | [R] `flutter_map/src/layer/attribution_layer/simple.dart:41-73` |
| F-18 | The live map always includes the attribution; the history viewer includes it only while tiles are shown and removes it together with the `TileLayer` when the user taps "Hide map" | [R] `live_map_feed.dart:432`; `workout_history_map_viewer.dart:390-396, 405, 416-420` |
| F-19 | One widget test proves the attribution text, key, and copyright link for the widget in isolation; no test mounts either map screen | [R] `test/presentation/common/widgets/open_street_map_attribution_test.dart:6-35`; `grep` over `test/` finds no other `flutter_map`/`LiveMapFeed`/`WorkoutHistoryMapViewer` reference |
| F-20 | Attribution shipped in the 1.2.0+21 release fix on 2026-07-28 (`028d469`, "show clickable OpenStreetMap attribution on both map screens") | [R] `git log -- lib/presentation/common/widgets/open_street_map_attribution.dart` |

### 2.3 Where the maps live and how they are driven

| # | Fact | Evidence |
| --- | --- | --- |
| F-21 | `HomeScreen` builds all four tabs into an `IndexedStack`; `TrackScreen` is index 0 and the default tab, so `LiveMapFeed` (and its `TileLayer`) is created at home entry and stays alive while other tabs are shown | [R] `lib/presentation/features/home/screens/home_screen.dart:15, 97-107`; `lib/presentation/features/live_tracking/screens/track_screen.dart:136` |
| F-22 | `LiveMapFeed.initState` creates a `MapController`, then `_initializeMap()` creates a **second** `MapController` and immediately calls `liveTrackingRepository.getCurrentLocation()`; neither controller is disposed | [R] `live_map_feed.dart:47-56, 70-77, 76-106` |
| F-23 | `LiveTrackingService.getCurrentLocation()` first runs `checkPermissions()`, which calls `Geolocator.requestPermission()` when the permission is `denied`, then `Geolocator.getCurrentPosition(accuracy: high, timeLimit: 10 s)` — a one-shot fix independent of the tracking stream | [R] `lib/core/services/live_tracking_service.dart:35-63, 121-144` |
| F-24 | The map centre defaults to New Delhi (28.6139, 77.2090) at zoom 16 in both screens; when the fix fails the live map stays on Delhi and loads Delhi tiles | [R] `live_map_feed.dart:37-38, 103-105`; `workout_history_map_viewer.dart:42-43` |
| F-25 | The live map watches the **whole** `liveTrackingProvider` state in its `Consumer`, plus two `select` listeners (`errorMessage` → snackbar; `currentLocation` → marker/follow) | [R] `live_map_feed.dart:355-378` |
| F-26 | The provider emits a new state every second during an active session (`elapsedTime` tick) and a new `WorkoutSessionEntity` per accepted point, copying the full point list each time | [R] `lib/presentation/features/live_tracking/providers/live_tracking_provider.dart:688-702, 720-740` |
| F-27 | During an active session the map holds **no** second GPS subscription; it consumes `state.currentLocation` (the IP-3 audit bullet about a second map subscription is stale, as the GPS audit already noted). The only independent fixes are the init fix (F-22) and the "Center on current location" button, which calls `checkPermissions()` + `getCurrentLocation()` again even mid-workout | [R] `live_map_feed.dart:369-378, 503-591` |
| F-28 | Route rebuild: on every session object change, `_updateTrackingPath` rebuilds all segments through `LiveMapSegmentBuilder.buildSegments` → `WorkoutRouteSegmenter.buildSegments`, maps every point to `LatLng`, clears and recreates every `Polyline`, and calls `setState` per polyline | [R] `live_map_feed.dart:129-181, 183-210, 325-351`; `lib/presentation/features/Map/screens/live_map_segment_builder.dart:6-8`; `lib/core/tracking/workout_route_segmenter.dart:10-62` |
| F-29 | Segment rules: version-2 (accepted-only) routes are all-`active`; a segment breaks at a pause/resume boundary or at a gap `> 30 s` (`activeAnchorResetGap`), so pauses and GPS dropouts appear as **gaps**, never as bridging lines. The red dashed "paused" polyline is reachable only for legacy (v1) routes that stored points during pause; the history viewer keeps a join-all-points fallback for legacy routes only | [R] `workout_route_segmenter.dart:15-40`; `lib/core/tracking/gps_point_acceptance_policy.dart:87`; `live_map_feed.dart:170-174`; `workout_history_map_viewer.dart:116-136`; `lib/domain/entities/workout_session_entity.dart:9-10,47` |
| F-30 | Polyline styling: live solid width 6 / history width 4, round caps and joins; dashed pattern `[10, 5]` red. `PolylineLayer` defaults apply: `simplificationTolerance` 0.3 px with Douglas–Peucker, `cullingMargin` 10 — rendering-only, persisted route untouched | [R] `live_map_feed.dart:183-210`; `workout_history_map_viewer.dart:145-166`; `flutter_map/src/layer/shared/layer_projection_simplification/widget.dart:26`; `polyline_layer/polyline_layer.dart:66,102` |
| F-31 | `PolylineLayer`'s projection and simplification caches are dropped **unconditionally in `didUpdateWidget`**, i.e. on every rebuild of the parent, and rebuilt in the next `build` by re-projecting every point | [R] `layer_projection_simplification/state.dart:54-58, 64-95` |
| F-32 | Markers: a current-location marker (colour by workout type, or by speed when idle) is shown only when there is no active session with points — it is deliberately hidden during tracking; a green start marker is re-added on each path update; history adds green start and red end markers | [R] `live_map_feed.dart:212-266, 288-319`; `workout_history_map_viewer.dart:168-222` |
| F-33 | Camera follow is **off by default** (`_isFollowing = false`); it is enabled only by the "Center on current location" button and disabled by any map event whose source is not the controller (drag, pinch, tap, size change) and by fit/zoom buttons; when on, each accepted point triggers an 800 ms animated pan | [R] `live_map_feed.dart:43-45, 108-127, 407-417, 503-512, 593-647` |
| F-34 | `_animatedMove` creates a new `CurvedAnimation` per call, adds a status listener that is never removed, calls `_animationController.reset()` inside that listener, and finishes with `_mapController!.move(destLocation, destZoom)`. `CurvedAnimation`'s constructor also registers its own status listener on the parent controller and the object is never disposed | [R] `live_map_feed.dart:651-699` (history variant `workout_history_map_viewer.dart:285-324` lacks the final move); Flutter `animation/animations.dart:381-385`; `animation/animation_controller.dart:372-377, 393-395, 410-422` |
| F-35 | The history viewer fits the route with a post-frame callback plus a hard-coded 100 ms delay ("Critical: Add a small delay to ensure map has finished rendering") instead of `MapOptions.onMapReady`; loading and empty states use `Colors.red` containers | [R] `workout_history_map_viewer.dart:75-94, 329-363` |
| F-36 | Both files carry the comment "Always use online flow - TileLayer will handle offline gracefully"; nothing in either file consults `ConnectivityService`/`isOfflineModeProvider`; the Track app bar shows the generic `ConnectivityBadge` | [R] `live_map_feed.dart:383`; `workout_history_map_viewer.dart:365`; `track_screen.dart:123`; `lib/core/services/connectivity_service.dart` |
| F-37 | `offline_map_widget.dart` is a fully commented-out `OfflineMapWidget` (grid background, no `TileLayer`, `print` of workout ids); STATUS.md records "Offline map implementation commented out — Deferred", README defers "Offline map tile caching", IP-3 lists "Full offline map tiles" as a non-goal | [R] `lib/presentation/features/Map/widgets/offline_map_widget.dart:1-193`; `STATUS.md:248`; `improvement-plan/README.md:234`; `IP-3-workout-durability.md:46` |
| F-38 | Manifest declares `INTERNET`, `allowBackup="false"`; no cleartext or network-security config is involved (tiles are HTTPS) | [R] `android/app/src/main/AndroidManifest.xml:6, 23` |
| F-39 | The public privacy policy names "Infrastructure and email providers" as recipients and states "We only collect location data when you actively start a workout"; it does not mention OpenStreetMap or map tiles. STATUS.md already lists this under IP-5.6 | [R] `docs/privacy-policy.md:78-79, 107`; `STATUS.md:242` |
| F-40 | IP-4.2 already plans `GET /api/capabilities`, a versioned non-sensitive document cached per API base URL — a natural home for a runtime tile-endpoint switch | [R] `IP-4-sync-data-restore.md:229` |

## 3. Policy compliance findings

Requirements are quoted from the OSMF Tile Usage Policy as fetched on
2026-08-18. The page states it "may change at any time"; the older clauses this
audit expected ("distributing an app … requires permission", "2 download
threads", "250 tiles at z17+") are **not** in the current text.

| Requirement [P] | Current state [R] | Risk | Smallest fix |
| --- | --- | --- | --- |
| "Use the correct URL: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`"; "Other subdomains or hostnames may be slower or withdrawn without notice" (§1) | Exact match, HTTPS, no `{s}` (F-01, F-02) | None | — |
| "Provide visible licence attribution … Typically: © OpenStreetMap contributors"; "Do not hide attribution beneath UI, behind toggles, or off-screen" (§2); Attribution Guidelines: link to `openstreetmap.org/copyright`, "should not require individuals to interact with the map … to see the attribution" | "flutter_map \| © OpenStreetMap contributors", bottom-left, always on while tiles are shown, tap opens the copyright page (F-16–F-18) | None. The `flutter_map \|` prefix is the library's default framing, not a policy issue | Optional: `RichAttributionWidget` for cleaner text; add the recommended "Report a map issue" link (`https://www.openstreetmap.org/fixthemap`) — a "should", not a "must" |
| "Send a valid HTTP User-Agent that clearly identifies your application"; "Apps must configure a distinct, stable User-Agent naming your app and optionally a contact URL or email"; "Do not use a library default User-Agent"; example `MyTownMaps/1.4 (+https://example.org; contact: maps@example.org)` (§3.1, §3.4) | `flutter_map (com.github.cosmicsaurabh.rythmrun)` — distinct, stable, identifies the app by package id in the library's format, no app name, no contact (F-04). flutter_map's docs treat this value as the compliance step and say only "unspecified or generic" values are blocked | Low–medium: it is not the recommended form and offers OSMF no contact channel; a future tightening on the `flutter_map (…)` prefix would block the app until a store release [A] | Pass `NetworkTileProvider(headers: {'User-Agent': 'RythmRun/1.2 (Android; +https://cosmicsaurabh.github.io/RythmRun/; contact: <support email>)'})` from one shared config; keep it stable across releases (M-02) |
| "Cache tiles locally according to HTTP caching headers (or at least 7 days)"; "Never send `Cache-Control: no-cache`…"; "Use Conditional Requests" (§3.2) | Built-in cache honours `max-age`/`Expires`, falls back to 7 days, sends `If-None-Match`/`If-Modified-Since`, no `no-cache` header (F-05, F-07). What OSM actually returns in `Cache-Control` was not captured [A] | Low. Side effects: 1 GB default cap; device-wide cache not cleared on logout (M-08); stale tiles not served offline (M-09) | Configure `BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: …)` once at startup; optional `overrideFreshAge`; decide on logout clearing |
| "Bulk downloading … or offer prefetch features" prohibited; "Offline use is not permitted on `tile.openstreetmap.org`" (§4) | No prefetch, no offline download, offline widget commented out (F-37); only viewport (+1 pan buffer, +2 keep buffer) tiles are requested | None today | Keep it so; any future offline feature must use another provider (§10) |
| "Avoid hard-coding the tile URL; allow switching without needing a software update" (recommended, Quick summary) | Hard-coded twice (F-02); Play releases "take time and users may not install" (CLAUDE.md) | Medium operational: a block, URL change, or provider switch strands installed builds | Stage B: one config with `--dart-define` default (per-build switch); Stage E: `mapTiles` block in the planned `GET /api/capabilities` with compiled fallback (runtime switch) (M-01) |
| "Publish a contact email on your website or app store listing" (recommended) | Privacy policy publishes a support email; Play listing not checked [A] | Low | Maintainer confirms the listing |
| "Support HTTP/2 or HTTP/3" (recommended, §3.3) | `dart:io` `HttpClient` is HTTP/1.1; connections per host unbounded (F-06) | Low | Optional `IOClient(HttpClient()..maxConnectionsPerHost = 4)`; do **not** add `cronet_http` for this (dependency surface) (M-14) |
| "Use of OSMF services is subject to the OSMF Privacy Policy" (§6) | The app's privacy policy does not name OSMF/OpenStreetMap as a recipient of IP address + approximate viewed area (F-39) | Medium: policy accuracy; Play Data-safety classification is the maintainer's call [A] | IP-5.6 wording (maintainer-owned; suggested sentence in §14) (M-10) |
| "Traffic using generic defaults, referer-stripping, or spoofed identities may be blocked without notice"; "Access may be blocked without prior notice"; "Commercial services, or those that seek donations, should be especially aware that access may be withdrawn at any point" (§3.4, §7) | Ads are planned (IP-5.5) but off; no fallback endpoint; no user-visible degraded state | Medium at release scale | Configurable endpoint + degraded UX (M-01, M-04); provider switch trigger in §13 |

## 4. Findings

Severity: **P1** breaks or misleads a core promise; **P2** real reliability,
privacy or resource defect worth a focused PR; **P3** hygiene/UX. No P0 and no
P1 in the map layer — nothing here loses a workout.

| ID | Sev | Finding | Evidence | Smallest fix | Test |
| --- | --- | --- | --- | --- | --- |
| M-01 | P2 | Tile URL, UA source and max zoom are duplicated string literals in two widgets; no way to switch endpoint per build or at runtime | F-01, F-02 | One `MapTileConfig` (URL from `String.fromEnvironment('MAP_TILE_URL', defaultValue: OSM)`, attribution text, UA, `maxNativeZoom`) and one place that builds the `TileLayer` for both screens; later a `mapTiles` block in `GET /api/capabilities` (F-40) validated as `https` + host allowlist, compiled default kept | T-2 |
| M-02 | P2 | UA is the library-formatted identifier, no app name/contact | F-04 | Explicit stable UA header on `NetworkTileProvider` (value in M-02 fix column of §3) | T-2 |
| M-03 | P2 (privacy) | Every failed tile prints `…uri=https://tile.openstreetmap.org/z/x/y.png` (or `HTTP request failed, statusCode: …, <uri>`) via `debugPrint`, which is **not** stripped in release; an offline workout with follow-mode logs a coarse route trace to logcat | F-10 | `NetworkTileProvider(silenceExceptions: true)` — one argument; the app uses no per-tile error signal today, so nothing is lost. Consider an upstream flutter_map issue (release `debugPrint` of tile URLs) | T-3 (assert captured `debugPrint` contains no host/`/z/x/` string) |
| M-04 | P2 | Passive degradation: blank tiles, no message, no retry on reconnect, no live route-only mode; the "graceful" comment is aspirational | F-11, F-12, F-36 | Chip driven by `currentConnectivityStatusProvider` ("Map unavailable — recording continues"); "Route only" toggle on the live map mirroring history's "Hide map"; on transition disconnected→connected bump the `TileLayer` key (or use `reset`) so errored tiles reload | T-3, T-4, T-9 |
| M-05 | P2 | `_animatedMove` leaks two status listeners per call for the widget's lifetime; on every completion all accumulated app callbacks fire, each `reset()`-ing the controller and calling `move()` for its stale destination (~2N synchronous moves, N = calls so far, then a `TileUpdateEvent` per move → tile create/prune/abort churn); with follow-mode on, N grows by one per accepted point; the widget lives for the app session (F-21). Also: second `MapController()` orphaned; controllers never disposed | F-22, F-33, F-34 | Keep one `CurvedAnimation` field created in `initState` and disposed in `dispose`; remove the status listener in its own callback (or use `_animationController.forward().whenComplete`); drop the duplicate `MapController()`; call `_mapController.dispose()` | T-5b |
| M-06 | P2 (owned by IP-3.5) | Whole-state watch rebuilds `FlutterMap` and all layers every second during a session; `PolylineLayer` then re-projects and re-simplifies every point (F-31); every accepted point additionally rebuilds all segments/polylines (F-28) on top of the provider's own O(n) list copy (F-26). Cost grows linearly with route length; happens even while the Track tab is offstage (F-21) | F-25, F-26, F-28, F-31 | Interim: `ref.watch(liveTrackingProvider.select((s) => s.currentSession))` for the map subtree, `select` for `isLoading`; full fix is IP-3.5 items 1–5 (incremental polylines, selectors) | T-5a |
| M-07 | P2 (privacy/UX; IP-3.5 item 6) | Map init acquires a high-accuracy fix and can pop the OS permission prompt at home entry, before any workout intent; contradicts the policy sentence "We only collect location data when you actively start a workout" (wording is maintainer-owned); Delhi tiles are fetched when the fix fails; "Center" mid-workout requests another fix instead of using `state.currentLocation` | F-22–F-24, F-27, F-39 | Do not call `checkPermissions()`/`getCurrentLocation()` from `initState`; centre on `state.currentLocation` when a session is active; request the one-shot fix only from the button and only if permission is already granted (permission flow stays in Track) | T-8 |
| M-08 | P3 (privacy) | Disk tile cache (`cache/fm_cache`, ≤1 GB) is device-wide, UUID-keyed, not user-scoped, not touched by `invalidateUserState`; it retains an approximate "areas viewed" footprint across logout/account switch | F-07 | Decide: call `BuiltInMapCachingProvider.getOrCreateInstance().destroy(deleteCache: true)` in session teardown (re-download cost, OSM load) **or** accept and record; either way set a smaller `maxCacheSize` (e.g. 200 MB [A]) | T-7 |
| M-09 | P3 | Stale-but-present cached tiles are not shown offline (conditional GET fails → blank), so a familiar route area goes blank once its `max-age` passes | F-08 | `overrideFreshAge` (e.g. 30 days [A]) on the built-in provider — still ≥ 7 days; a stale-on-error provider is more code and should wait for demand | T-4 |
| M-10 | P3 (docs) | Privacy policy silent on OSMF as a data recipient and on the launch-time fix | F-39 | Maintainer wording under IP-5.6 (§14) | — |
| M-11 | P3 (UX) | Follow-mode off by default and silently disabled by any gesture or size change; no current-position marker during tracking, so after a pan the runner's position is off-screen until "Center"; the button then shows up to three snackbars and re-requests GPS | F-32, F-33 | Enable follow on workout start; keep a small "you are here" head marker during tracking; drop the success snackbar | T-5b |
| M-12 | P3 (UX/robustness) | 100 ms delayed fit instead of `onMapReady`; `Colors.red` loading/empty containers; "Hide/Show map" is the only (undocumented) tile-retry affordance | F-35 | Use `MapOptions.onMapReady`; theme colours; label the toggle "Route only" | T-1 |
| M-13 | P3 (hygiene) | Dead commented-out `OfflineMapWidget` with `print`s; `LiveMapSegmentBuilder` is a pass-through with two unused helpers | F-37, F-28 | Delete when a map PR touches these files (no unrelated diffs) | — |
| M-14 | P3 (network) | HTTP/1.1, unbounded parallel connections; policy merely recommends HTTP/2/3 | F-06 | Optional `maxConnectionsPerHost` on an injected `IOClient`; no new dependency | T-4 |
| M-15 | P3 | Retina mode is disabled (correct choice: emulated retina multiplies tile requests); recorded so nobody "fixes" blurry labels by enabling it against the public server | F-01 | None — keep disabled while on OSM | — |
| M-16 | P2 | A new `NetworkTileProvider` → `RetryClient(Client())` → new `HttpClient` is constructed on **every** `LiveMapFeed` rebuild (each second during a session); subsequent tiles use the newest client, so keep-alive connections are not reused and earlier clients are abandoned unclosed until their idle timeout | F-05, F-06, F-25, F-26; `tile_layer.dart:446-509` (no provider comparison in `didUpdateWidget`), `:512-519` (only the last provider is disposed) | Hold one `NetworkTileProvider` (or the built `TileLayer`) in State, created in `initState`; the `_TileLayerState` disposes it | T-4 (assert one client instance) |

### 4.1 Why M-05 is worth a paragraph

`CurvedAnimation.addStatusListener` forwards to the parent controller
(`AnimationWithParentMixin`), and `CurvedAnimation`'s constructor registers a
second listener of its own. `LiveMapFeed._animatedMove` never removes either
and never disposes the curve, so after N calls the controller carries 2N
listeners. When animation N completes, Flutter notifies every registered
listener with `completed`; the app's callback from call 1 runs first, calls
`_animationController.reset()` — which sets the value to 0, notifies value
listeners (the still-registered listener from call N moves the camera back to
its *start*), flips the status to `dismissed` and re-notifies all listeners —
then calls `move(dest_1)`. Callbacks 2…N repeat this with their own stale
destinations; the last one wins, so nothing visibly jumps in the painted frame,
but `MapController.move` runs ~2N times and each emits a `MapEvent` that the
`TileLayer` turns into a range calculation plus tile create/prune (with abort)
for each stale camera. With follow-mode on, N is the number of accepted points
in the current app session — the work per completion grows linearly and the
total quadratically. It is invisible in a 20-minute test and real in a
three-hour hike.

## 5. Network-failure and degraded-mode UX flow

### 5.1 Today

| Trigger | What the user sees | What the app does | How it recovers |
| --- | --- | --- | --- |
| Cold start, online | Map jumps from Delhi to the user's position after a fix (≤10 s); tiles fade in | Permission prompt if `denied`; one-shot high-accuracy fix; ~24 tiles for viewport + pan buffer at z16 [A: viewport size]; tiles written to disk cache | n/a |
| Cold start, offline | Fresh cached tiles appear; everything else is flat grey (`0xFFE0E0E0`); no message; app-bar `ConnectivityBadge` may show offline | Conditional GET for stale tiles fails → error → `debugPrint` of the tile URL per tile | Only by panning/zooming after reconnect |
| Network drops mid-workout | New tiles stop appearing; route line and start marker keep drawing over grey; metrics keep counting | In-flight requests throw `ClientException`; each errored tile logs its URL; follow-mode keeps requesting tiles that fail | Recording is unaffected; tiles that scroll out of the keep buffer are recreated on reconnect; visible errored tiles stay blank |
| Network returns | Nothing changes until the camera moves | No retry; errored `TileImage`s keep `loadStarted != null` (F-12) | Live: newly needed tiles load; History: zoom/pan or "Hide map"→"Show map" (rebuilds the `TileLayer`) |
| Slow or stalled network | Grey areas linger; no spinner | No per-request timeout; `RetryClient` retries only 503 (≤3, ≈2.4 s total); a stalled request is aborted only when its tile is pruned | Time or camera movement |
| Server 4xx (blocked UA, 429, 403) | Either the provider's error image (if the body decodes as an image [A]) or grey | `attemptDecodeOfHttpErrorResponses` tries the body; else `NetworkImageLoadException` → log | None automatic |
| Finish while offline | "Workout saved" flow as usual | SQLite save; sync queued (IP-4) | n/a — tiles are irrelevant |

### 5.2 Proposed (Stage C)

| Trigger | What the user sees | What the app does |
| --- | --- | --- |
| Offline or tile server unreachable | Small chip over the map: **"Map unavailable — your route is still being recorded"**; route drawn on a neutral background; optional **"Route only"** toggle (same control as history's Hide map) | Chip bound to `currentConnectivityStatusProvider == disconnected` (no dependency on tile errors, so `silenceExceptions: true` costs nothing); no URL logging |
| Reconnect | Grey squares fill in within a second or two | Key-bump/`reset` on the `TileLayer` when connectivity flips to connected; errored tiles reload |
| Provider blocks or is withdrawn | Same chip (tiles fail while connectivity is fine → after Stage E the capability document can point to another endpoint without a release) | Endpoint from `MapTileConfig`; attribution text follows the endpoint |
| Any of the above | Nothing else changes: Start/Pause/Resume/Finish, metrics, and the save path are untouched | — |

## 6. Do GPS tracking and saving continue when tiles are unavailable?

Yes, by construction; unproven by test.

- Location: `Geolocator.getPositionStream` → `LiveTrackingService._onLocationUpdate` → broadcast stream → `LiveTrackingNotifier._onLocationUpdate` (acceptance policy, metrics, state) — no import of `flutter_map`, no network [R] `live_tracking_service.dart:80-96, 107-113`; `live_tracking_provider.dart:648-703`.
- Save: `TrackScreen._finishWorkout` → `notifier.stopWorkout()` → `_persistCompletedWorkout` → `WorkoutRepository.saveWorkout` (SQLite) [R] `track_screen.dart:1113-1186`; `live_tracking_provider.dart:614-645`. Cloud sync is a later, queued concern (IP-4).
- Isolation: tile failures are caught in `TileImage.load`/`_onImageLoadError` and never leave `flutter_map` [R] `tile_image.dart:135-177`; the map's snackbars come from provider `errorMessage`, not from tiles [R] `live_map_feed.dart:360-368`. If `LiveMapFeed.build` itself threw, Flutter would replace only that subtree with the error widget; the notifier and the Track card are separate widgets.
- Gap: no widget test mounts either map with a failing tile provider (F-19). T-3/T-6 close it.

## 7. Rendering memory and CPU during a long workout

Verified structure [R], magnitudes estimated [A]; nothing was measured.

- Per second (elapsed tick): rebuild of `FlutterMap` and every layer; `PolylineLayer` re-projects all n points and re-simplifies at the current zoom (F-31); a new `NetworkTileProvider`/`HttpClient` (M-16). Estimate for n ≈ 6,500 (3 h at ~0.6 accepted pts/s): low single-digit ms per tick on a mid-range phone [A] — not a jank source alone, but continuous and offstage too.
- Per accepted point: provider list copy O(n) (F-26); segmenter O(n) + `LatLng` mapping O(n) + polyline recreation + several `setState`s (F-28); with follow-mode, an 800 ms pan (≈48 `move()`s at 60 fps, each a `MapEvent` and a `TileLayer` range calc) plus the M-05 replay of all past destinations.
- Memory: bounded on the map side — `TileImageManager` keeps viewport + `keepBuffer` 2 rows/columns; Flutter's `ImageCache` limits decoded tiles; disk cache ≤1 GB (F-07). Unbounded growth comes only from the leaked listeners/closures (M-05, ~two objects per point) and from short-lived garbage (new `List<LatLng>` per point, new `HttpClient` per second).
- Ownership: IP-3.5 (incremental polylines, selectors, one subscription) already owns the structural fix; M-05 and M-16 are separate, small, and should not wait for it.

## 8. Does the live map request location independently of the tracking service?

Twice, both one-shot and both through the same `LiveTrackingService`
singleton (so no second *stream*):

1. At map construction (`_initializeMap` → `getCurrentLocation()`), which also
   runs `checkPermissions()` and can show the OS permission dialog before the
   user has expressed any intent to track (F-22, F-23). Because `TrackScreen`
   is the default tab, this happens at every home entry.
2. On every "Center on current location" tap, even while a session is active
   and `state.currentLocation` already holds the last accepted point (F-27).

Recommendation: no location or permission call from the map's `initState`;
centre from provider state during a session; one-shot fix only from the button
and only when permission is already granted. IP-3.5 item 6 already names the
tab-laziness half of this.

## 9. Privacy risks from map requests and map UI

| Risk | Class | Detail | Mitigation |
| --- | --- | --- | --- |
| Tile operator learns IP + coarse area + time | Inherent to online raster maps | Each request carries the device IP, the UA (app identity), and z/x/y (≈ 400–600 m cell at z16, 50–75 m at z19 [A: mid-latitude figures]); a follow-mode workout emits a coarse trace with timing; opening a history detail discloses that workout's area again | Disclose in the privacy policy (M-10); minimise requests (cache, no offstage/stale-camera loads — M-05/M-06); no analytics in the path (F-15) |
| Tile URLs in device logs (release) | App-side, avoidable | F-10; visible via `adb logcat` on a debug-connected device; contradicts the spirit of IP-1.2's "no exact coordinates in release logging" (these are coarse, not exact) | `silenceExceptions: true` (M-03) |
| Launch-time GPS fix and permission prompt | App-side, avoidable | F-22/F-23 vs privacy-policy line 107 (F-39) | M-07 |
| Unscoped disk cache | App-side, low | F-07; app-private storage, `allowBackup=false` (F-38); reveals viewed areas to anyone with the app's private files, and survives account switch | M-08 |
| Attribution tap | None | Opens `openstreetmap.org/copyright` externally with no query data (F-16) | — |
| Ads slot next to the map | Out of scope | Ads are fail-closed (IP-1.7); no ad code in the map path | — |

## 10. Suitability and provider strategy (items 8–10)

### 10.1 Is `tile.openstreetmap.org` suitable?

- **Personal testing — yes.** Interactive viewing with a valid UA, caching and
  attribution is exactly the permitted pattern [P §4 "Permitted usage"].
- **Small public release — acceptable as a starting point, not a dependency to
  build on.** The current policy no longer forbids distributed apps outright,
  but it says capacity is limited, access may be blocked without notice, and
  commercial/donation-seeking services "should be especially aware that access
  may be withdrawn at any point" [P §7]. RythmRun plans ads (IP-5.5). The
  responsible posture is: comply fully now (M-01–M-04), keep the endpoint
  switchable, and define the trigger for moving off (§13).
- **Offline maps — no.** "Offline use is not permitted on
  `tile.openstreetmap.org`"; any download-for-offline or save-area feature
  "rely[s] on prefetch/bulk downloading" and "will be blocked without notice"
  [P §4]. Reusing the naturally populated cache for a revisit is permitted;
  filling it deliberately is not.

### 10.2 Low-cost provider strategy

| Phase | Provider | Fit with terms | Cost | Change in the app |
| --- | --- | --- | --- | --- |
| Personal / testing (now) | `tile.openstreetmap.org` | Permitted interactive use; needs proper UA, caching, attribution, no prefetch | $0 | Stage B fixes (UA, config seam, silence log, cache size) |
| Small public release, ads off | `tile.openstreetmap.org` behind `MapTileConfig`, with the switch already wired; **or** a free-tier hosted OSM-based provider from the OSMF-linked list (switch2osm names Stadia Maps, MapTiler, Thunderforest, Geoapify, Jawg, Tracestrack, … under "Allows free usage") | Free tiers exist; exact quotas, key handling, hobby/non-commercial clauses and required attribution strings **must be verified before use** [A] | $0 within free tiers | URL template + attribution text + (for keyed providers) `--dart-define=MAP_TILE_KEY` — never committed; keys embedded in an APK are extractable, providers rate-limit per key/package [A] |
| Ads on, or growth beyond a free tier, or an OSMF block/notice | Free tier → cheapest paid tier of the same provider; **or** self-hosted static tiles (e.g. a Protomaps/PMTiles regional extract on the existing Cloudflare R2 with a small serving worker) [A: current terms and tooling not verified] | Own infra means own terms | Small monthly $ only when triggered | Config only (Stage E makes it release-free) |
| Future offline requirement | Not OSM. Either (a) the zero-cost honest answer already half-built — a route-only mode that draws the recorded polyline without tiles, which satisfies "a workout survives poor connectivity"; or (b) a provider whose terms **explicitly** permit offline packaging (self-hosted vector/PMTiles extracts, or a commercial SDK with an offline licence). Vector tiles "where the provider terms permit can be packaged for offline use" [P §8] | Must be explicit in the provider's terms | New dependency + design; stays in the deferred backlog until users ask | Provider + renderer change; not a config flip |

## 11. Recommendations

**Attribution** — keep `OpenStreetMapAttribution` always-on while OSM tiles are
shown (already true). Make the text follow `MapTileConfig.attribution` so a
provider switch cannot leave a wrong credit; add the "Report a map issue" link
only if it fits the small overlay. Never gate it behind the controls overlay.

**Cache behaviour** — keep flutter_map's built-in cache (it is what makes the
app policy-compliant); configure it once at startup with a smaller
`maxCacheSize`; decide `overrideFreshAge` (M-09) and logout clearing (M-08) as
maintainer decisions; never add prefetch against OSM.

**Configurable tile endpoint** — one `MapTileConfig` (URL template, attribution,
UA, `maxNativeZoom`, optional key) read from `--dart-define` with the OSM
default, consumed by one `TileLayer` builder used by both screens (two call
sites, one network boundary — the abstraction earns its place). Then a
`mapTiles` block in the IP-4.2 capability document for a release-free switch,
validated client-side (`https` only, host allowlist compiled in, fall back to
the compiled default on any validation or network error — same no-silent-
downgrade rule IP-4.2 already states for protocol selection).

**User-Agent / contact** — explicit, stable header
`RythmRun/<major.minor> (Android; +https://cosmicsaurabh.github.io/RythmRun/; contact: <support email>)`
via `NetworkTileProvider(headers: …)`; publish the same contact on the store
listing. Do not include the build number (identification should be stable
across releases [P §3.4]).

**Graceful map failure** — `silenceExceptions: true`; connectivity-driven chip;
route-only toggle on the live map; reload errored tiles on reconnect; neutral
`backgroundColor` in both screens; `onMapReady` instead of the 100 ms delay;
theme colours for loading/empty states.

**Lifetime hygiene** — one `NetworkTileProvider` per map State (M-16); one
`CurvedAnimation` and no leaked status listeners (M-05); one `MapController`,
disposed (F-22).

**Do not** — enable retina mode against OSM (M-15); add `cronet_http` for
HTTP/2 (M-14); add a tile-download feature of any kind on OSM (§10.1).

## 12. Tests

All are `flutter test` unless marked device/manual. Two seams are needed and
are consistent with the repository's "injectable seams over hard-wired globals"
rule: an optional `TileProvider` (or the whole `TileLayer` builder) injected
into `LiveMapFeed`/`WorkoutHistoryMapViewer`, and `MapTileConfig` as a plain
value object. In widget tests always pass
`cachingProvider: const DisabledMapCachingProvider()` (or a temp
`cacheDirectory`) — the default built-in cache calls `path_provider`, which has
no implementation under `flutter test` and would fail asynchronously.
`package:http/testing.dart`'s `MockClient` (already in the dependency tree)
covers HTTP simulation without a new package; flutter_map's own tests use a
`TileProvider` returning a `MemoryImage` white tile — copy that pattern.

| ID | Test | Asserts |
| --- | --- | --- |
| T-1 Attribution visibility | Pump `WorkoutHistoryMapViewer` (2-point fixture, tiles on) and `LiveMapFeed` (ProviderScope overrides + fake tile provider) | `Key('openStreetMapAttribution')` present, text contains "OpenStreetMap"; toggling Hide/Show map removes and restores it; tap opens the copyright URL through the seam |
| T-2 Tile config | Unit test on `MapTileConfig` | HTTPS, exact OSM template, no `{s}`, UA equals the constant and contains the site URL, `maxNativeZoom` 19; a CI run with `--dart-define=MAP_TILE_URL=https://example.test/{z}/{x}/{y}.png` proves the override reaches the `TileLayer` |
| T-3 Offline simulation | `NetworkTileProvider(httpClient: MockClient((r) async => throw ClientException('Failed host lookup', r.url)), cachingProvider: DisabledMapCachingProvider())`; capture `debugPrint`; drive 20 accepted points through the existing fake location stream harness | 20 points in state, polylines present, `tester.takeException()` null, captured log contains no `tile.openstreetmap.org` and no `/16/` (after M-03), chip visible when the connectivity override says disconnected |
| T-4 HTTP errors and timeouts | `MockClient` returning 503 (count attempts ≤ 4 per tile), 403/429 with empty body, and a `Completer` that never completes | No exception, controls still tappable, only one `NetworkTileProvider` instance is created across 30 fake seconds of ticks (M-16), pruning after a zoom aborts the pending request |
| T-5a Long route | Pure Dart benchmark: 12,000-point synthetic route (IP-4 upload cap) → `WorkoutRouteSegmenter.buildSegments` + `LatLng` mapping | Completes under a recorded budget [A]; widget pump of `WorkoutHistoryMapViewer` with the fixture builds one frame without timeout |
| T-5b Follow-mode growth | Enable follow, feed 500 accepted points, observe `MapController.mapEventStream` (controller injected or exposed for test) | After M-05: exactly one `move` per completion; status-listener count constant (or `debugPrint` of leaked-listener assertion in debug builds) |
| T-6 Tracking without map | `LiveMapFeed` mounted with the failing provider from T-3, then `stopWorkout()` with a fake `WorkoutRepository` | `saveWorkout` called once with all points; result `saved`; no map-originated exception |
| T-7 Cache configuration | Startup wiring calls `BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: …)` before the first tile; if logout clearing is adopted, `invalidateUserState` deletes `fm_cache` (use `cacheDirectory: tempDir`) | Instance parameters; directory absent after teardown |
| T-8 No location before intent | Pump `HomeScreen` with a fake `LiveTrackingRepository` | `checkPermissions`/`getCurrentLocation` not called until a Track interaction (after M-07) |
| T-9 Device/manual (new MC item) | Airplane mode during a workout on a physical device: record 10 min → Finish → reconnect; `adb logcat` scan on a **release** build | Recording and save unaffected; chip shown; tiles reload after reconnect without user action; no `tile.openstreetmap.org` in logcat |

## 13. Staged plan (no paid infrastructure unless growth proves it)

| Stage | Content | Gate / trigger | Rollback |
| --- | --- | --- | --- |
| A — record (this audit) | Facts into IP-5.6 (privacy sentence, launch-time fix), IP-3.5 (M-05/M-06/M-16 pointers), decisions §14; offline tiles stay deferred | None | — |
| B — one Flutter PR: compliance and hygiene | `MapTileConfig` + shared `TileLayer` builder + `--dart-define` default (M-01), explicit UA (M-02), `silenceExceptions: true` (M-03), cache size (M-08 size only), single provider per State (M-16), animation/controller lifetime (M-05, F-22); tests T-1, T-2, T-3, T-4, T-5b, T-6, T-7 | Standard Flutter gates; no backend, no schema, backward compatible with the released app | Revert restores identical network behaviour; no data |
| C — one Flutter PR: degraded-mode UX | Chip, route-only toggle, reload on reconnect, neutral backgrounds, `onMapReady`, no init fix/prompt (M-04, M-07, M-11, M-12); T-8, manual T-9 | After B | UI-only |
| D — with IP-3.5 | Selectors and incremental polylines (M-06); T-5a | IP-3.5 schedule | IP-3.5 rules |
| E — with IP-4.2 | `mapTiles` block in `GET /api/capabilities` (optional field, backward compatible); client validation + compiled fallback | IP-4.2 delivery | Client ignores the block |
| F — provider switch | Flip `MapTileConfig` (or capabilities) to a free-tier provider or self-hosted tiles; attribution follows | Any of: OSMF contact or block; ads enabled for real users; sustained MAU above the free-tier comfort line the maintainer sets [A]; error-rate chip firing while online | Flip back |
| G — offline maps | Only with a provider whose terms permit offline packaging; separate design | Demonstrated user need; stays deferred (README) | n/a |

## 14. Decisions and facts for the maintainer

- **UA string and contact.** Confirm the support address to embed and publish
  on the store listing (M-02).
- **Cache lifetime and scope.** `overrideFreshAge` value or none (M-09); clear
  `fm_cache` on logout/account switch, or accept and record (M-08); `maxCacheSize`.
- **Privacy policy (IP-5.6, wording is yours; engineering supplies the fact).**
  Facts to reflect: map images are fetched from OpenStreetMap's public tile
  servers operated by the OpenStreetMap Foundation; each request discloses the
  device's IP address, the app's identity, and the approximate map area being
  viewed; tiles are cached on the device; the app currently requests a location
  fix when the Track screen is first shown, not only when a workout starts
  (until M-07 lands). Whether Play's Data-safety form treats this as "sharing"
  is your call [A].
- **Provider-switch trigger** (§13 F) and whether an ads-enabled release may
  stay on OSM at all.
- **Offline maps** remain deferred (README backlog); confirm.
- **New manual check** T-9 belongs in `ACTION-REQUIRED.md` when Stage C lands.

## Appendix — pinned-package behaviours relied on above

| Behaviour | Where |
| --- | --- |
| UA header composed with `putIfAbsent`; default `'unknown'` | `flutter_map/src/layer/tile_layer/tile_layer.dart:264, 279-285` |
| Debug-only OSM warning | `tile_layer.dart:322-362` |
| `debugPrint(error.toString())` on tile error | `tile_layer.dart:724-727` |
| Errored tiles not reloaded | `tile_image_manager.dart:88-109` |
| Errored tile paints `RawImage(null)` | `tile.dart:82-94` |
| Default map background `0xFFE0E0E0` | `map/options/options.dart:169` |
| `NetworkTileProvider` defaults and `RetryClient(Client())` | `tile_provider/network/tile_provider.dart:34-42` |
| Cache read/conditional GET/no stale-on-error; error → transparent only if silenced | `tile_provider/network/image_provider/image_provider.dart:164-331` |
| Built-in cache location, key, 1 GB cap, isolate writer | `tile_provider/network/caching/built_in/built_in_caching_provider.dart`, `impl/native/native.dart` |
| Freshness from headers, 7-day fallback | `tile_provider/network/caching/tile_metadata.dart:34-92` |
| Projection/simplification cache dropped on any `didUpdateWidget` | `layer/shared/layer_projection_simplification/state.dart:54-95` |
| `simplificationTolerance` 0.3, Douglas–Peucker | `layer/shared/layer_projection_simplification/widget.dart:26`; `layer/polyline_layer/polyline_layer.dart:102` |
| `SimpleAttributionWidget` text `'flutter_map \| © '` | `layer/attribution_layer/simple.dart:41-73` |
| `MapController.dispose` closes the event stream | `map/controller/map_controller_impl.dart:761-766` |
| `RetryClient` defaults (503 only, no error retry) | `http/retry.dart:62-72, 182-187` |
| `Client()` → new `IOClient()` → new `HttpClient()` | `http/src/client.dart:42`; `http/src/io_client.dart:14-20, 101` |
| `ClientException.toString()` includes `uri` | `http/src/exception.dart` |
| `debugPrint` not stripped in release | Flutter `foundation/print.dart:34-50` |
| `CurvedAnimation` registers a parent status listener; `reset()` re-notifies | Flutter `animation/animations.dart:381-385`; `animation/animation_controller.dart:372-377, 393-395, 410-422` |
