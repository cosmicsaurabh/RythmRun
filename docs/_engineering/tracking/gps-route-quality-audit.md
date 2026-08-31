---
published: false
---

# GPS Route-Quality and Metric-Correctness Audit

| Field | Value |
| --- | --- |
| Audited | 2026-08-17, branch `auth-impr` at `d0e5b92` (working tree also carries the uncommitted sync/tracking audit docs, read but untouched) |
| Scope | **Route quality and metric correctness only**: acceptance policy, distance, pace, speed, elevation, gaps, pause/resume anchoring, map/store/sync consistency, long routes. Durability, screen-off, process death, and sync reliability are covered by the [GPS tracking audit](./gps-tracking-audit.md) (`F1`…`F14`) and the [sync audit](../sync/sync-reliability-audit.md) (`SYNC-xx`) and are cited, not re-derived. |
| Method | Static read of the Flutter tracking path and its tests; static read of the pinned plugin sources in the local pub cache (`geolocator_android-5.0.3`, `geolocator_platform_interface-4.2.8`); backend DTO/Prisma read for payload bounds. **One synthetic simulation was run** (Python, in the session scratchpad, no dependencies) that replays the app's exact acceptance/haversine/elevation arithmetic against synthetic Gaussian noise on an abstract path — it produced the numbers quoted below and nothing else. **Not run:** `flutter test`, `flutter analyze`, any build, any emulator, any device, CI, staging, production. No coordinates, routes, or acquisition timestamps appear in this document; every synthetic figure is metres/seconds only. |
| Verdict | **Units, pause/resume, finish-while-paused, and "one accepted sequence feeds everything" are correct and hold in code.** What is *not* yet handled is GPS *noise*: stationary drift and warm-up fixes count as distance, single-interval implied speed makes max speed a noise statistic, the elevation algorithm both over-counts flat noise and under-counts gentle climbs, and the plugin's "field not available → 0.0" contract silently defeats the accuracy and altitude checks. All fixes are cheap, offline, and versionable; the thresholds need one round of real-device measurement that nothing in the repository can substitute for. |

Documents read in full: `AGENTS.md`, `improvement-plan/README.md`, `STATUS.md`,
`IP-1-tracking-correctness.md`, `IP-3-workout-durability.md`, and the existing
`gps-tracking-audit.md`. Source read in full: the policy, timeline, segmenter, service,
provider, state model, entities, `calculation_helper.dart`, `activity_sync_model.dart`,
`live_map_feed.dart`, `live_map_segment_builder.dart`, `live_map_feed_helper.dart`,
`workout_history_map_viewer.dart`, the point/metric parts of `local_db_service.dart`, and
every test named in Appendix A.

Path shorthand (all under `rythmrun_frontend_flutter/` unless noted): `policy` =
`lib/core/tracking/gps_point_acceptance_policy.dart`; `provider` =
`lib/presentation/features/live_tracking/providers/live_tracking_provider.dart`; `service` =
`lib/core/services/live_tracking_service.dart`; `helper` = `lib/core/utils/calculation_helper.dart`;
`segmenter` = `lib/core/tracking/workout_route_segmenter.dart`; `timeline` =
`lib/core/tracking/workout_timeline.dart`; `sync` = `lib/data/models/activity_sync_model.dart`;
`db` = `lib/core/services/local_db_service.dart`; `entity` =
`lib/domain/entities/workout_session_entity.dart`; `map` =
`lib/presentation/features/Map/screens/live_map_feed.dart`; `history-map` =
`lib/presentation/features/tracking_history/screens/workout_history_map_viewer.dart`;
`plugin-position` = `~/.pub-cache/hosted/pub.dev/geolocator_platform_interface-4.2.8/lib/src/models/position.dart`;
`plugin-mapper` = `~/.pub-cache/hosted/pub.dev/geolocator_android-5.0.3/android/src/main/java/com/baseflow/geolocator/location/LocationMapper.java`;
`plugin-options` = `…/geolocator_android-5.0.3/android/src/main/java/com/baseflow/geolocator/location/LocationOptions.java`;
`plugin-fused` = `…/geolocator_android-5.0.3/android/src/main/java/com/baseflow/geolocator/location/FusedLocationClient.java`;
`dto` = `RythmRun_backend_nodejs/src/models/dto/activity.dto.ts`.

---

## 1. The current acceptance and distance policy, in plain English

**What the phone hands the app.** Tracking asks Android for its best fused location with a
5 m minimum displacement and no explicit interval (`service` :81-84). The plugin fills the
missing interval with **5000 ms** and passes both to FusedLocation as interval, minimum
interval, and minimum update distance (`plugin-options` :58-59; `plugin-fused` :105-108). So
in practice the app sees at most one fix every 5 s, and only when the platform's own estimate
has moved ≥ 5 m — a device-side filter that is *not* written down anywhere in the app's
versioned policy. Each fix carries latitude, longitude, the fix time (UTC), and — **only if
the platform says it has them** — altitude, horizontal accuracy, speed, and heading
(`plugin-mapper` `toHashMap`, one `if (location.hasX())` per field). On the Dart side any
missing field becomes **`0.0`, not null** (`plugin-position` :171-178, :200-206). `mapPosition`
copies the values through unchanged (`service` :147-157).

**What the app keeps.** Every fix goes through one pure, versioned decision function
(`policy` :100-246, `policyVersion = 1`). In order, a fix is thrown away if:

1. any number is NaN/∞ (:108-113), or the coordinates are out of range (:114-121), or exactly
   (0, 0) (:123-127);
2. accuracy is missing, negative, or **worse than 50 m** (:129-144);
3. its time is not strictly after the last accepted fix (:146-157) — this drops duplicates
   and out-of-order deliveries;
4. the workout is active and the fix time is before the current active segment started —
   i.e. a stale fix delivered after Start or after Resume (:159-166);
5. the platform's own reported speed is negative or above the sport cap: **walk/hike 5 m/s
   (18 km/h), run 10 m/s (36 km/h), cycle 30 m/s (108 km/h)** (:168-176, :248-259).

If the workout is **paused**, a surviving fix is accepted only as a "where am I" marker: it
moves the dot on the map but is not stored in the route and adds nothing (:178-186;
`provider` :671-675).

If the workout is **active**, the fix is compared against the **distance anchor** — the last
stored active point:

- no anchor yet (first point after Start or after Resume) → stored, **0 m added**, starts a
  new drawn segment (:188-196);
- anchor older than **30 s** → stored, **0 m added**, starts a new drawn segment
  (:208-216) — the app deliberately does not bridge a gap;
- otherwise the straight-line (haversine, sphere radius 6371 km, :271-295) distance from the
  anchor is computed; if that distance divided by the elapsed time exceeds the sport cap the
  fix is rejected and **the anchor stays where it was** (:218-235); else the fix is stored,
  the distance is added, and it becomes the new anchor (:237-245; `provider` :687-696).

**What the metrics are.**

- **Distance** = sum of accepted anchor-to-point straight lines (`provider` :690).
- **Live pace** = the last accepted interval only, distance ÷ whole seconds (`provider`
  :677-685; `helper` :5-16).
- **Max speed** = the largest single accepted interval's implied speed, m/s (`provider`
  :687-693). The platform's Doppler speed is stored but never used for metrics.
- **Average speed / pace / calories** are computed once at Finish from total distance and
  the timeline's active duration (`provider` :441-447; `helper` :107-135). Calories use a
  fixed 70 kg and a speed-only MET table (`provider` :441-442; `helper` :61-92).
- **Elevation gain/loss** are computed once at Finish over the stored active points, per
  drawn segment: a 3-point moving average of altitude, then every consecutive step whose
  magnitude exceeds 2 m is added to gain or loss (`provider` :463-475; `helper` :137-218).
- **Time**: elapsed/active/paused come from a wall-clock timeline that clamps backwards
  jumps (`timeline`); the fix timestamps are used only for the acceptance arithmetic.

**Where the numbers go.** The same stored point list plus the status-change list drives the
live map, the history map (`LiveMapSegmentBuilder` → `WorkoutRouteSegmenter`, `map` :151,
`history-map` :104), the SQLite save (`db` :279-294), the sync payload (`sync` :30-52), and
the Finish-time elevation (`provider` :463-467). Rejected fixes are not kept anywhere.

---

## 2. Findings, severity-ranked

Severity is judged by how far a *typical* recorded metric can drift from the truth for an
ordinary user, not by code risk. "Sim" figures come from the synthetic replay described in
§0 and are **upper-bound illustrations** (independent Gaussian noise; real fused output is
Kalman-filtered and correlated, so real drift is smaller — by how much is a device
measurement, §4).

| ID | Sev | Scenario | Current behaviour | Evidence | Under/over risk | Recommended low-cost fix | Test required |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RQ-1 | **High** | Stationary without pausing (traffic light, water stop, phone-in-hand chat) | Every jitter fix that survives the platform 5 m filter, has accuracy ≤ 50 m, and implies ≤ the sport cap is **counted as distance and can set max speed**. There is no displacement-vs-accuracy gate and no speed floor. | `policy` :140-144, :218-245; `provider` :687-693; platform 5 m filter `plugin-fused` :108 | **Overcount.** Sim, 5 s cadence after the 5 m filter: 60 s stopped ≈ 30 m (σ 3 m) to 170–340 m (σ 8–15 m); 15 min ≈ 0.8 km (good sky) to 2.5–4.9 km (poor). Max speed 6–52 km/h while standing still. | Add a *distance-contribution gate* (point still stored/drawn, but adds 0 m and holds the anchor): skip when Doppler speed is available (> 0) and below a sport floor, else require Δ ≥ k·max(acc_anchor, acc_point), k≈1.5. Measure the gap from the last *accepted* point, not the held anchor (see RQ-6 interaction). `policyVersion 2`. | Notifier fixture: 5 min synthetic jitter (σ 3/8/15 m) → distance < 5 % of v1, maxSpeed unchanged from before the stop; moving fixtures (walk 1.4, run 3, cycle 8 m/s) stay within ±3 % of v1. |
| RQ-2 | **High** | Elevation on any workout | 3-point moving average, then **per-step |Δ| > 2 m** accumulates. Vertical GPS noise (σ typically 5–15 m raw) turns a flat route into hundreds of metres of gain *and* loss; a steady gentle climb whose per-sample step is < 2 m is counted as **zero**; every segment's first/last sample is unsmoothed. | `helper` :137-174, :192-218 (threshold :163); `provider` :463-475 | **Both.** Sim, 10 km flat, 1200 pts: σ_v 4 m → ≈ 490 m gain / 510 m loss; σ_v 6 m → ≈ 1.1 km each. Steady 1 % over 10 km (true +100 m) → **0 m**; 3 % over 5 km (true +150 m) → 0 m. | Replace with a wider centred window (≈ 7 samples or 30 s) plus a **hysteresis accumulator** (commit only when altitude has moved ≥ T from the last committed altitude, T ≈ 5–8 m; measure). Keep per-active-segment evaluation. Sim of that: flat σ 4 → 0/0, σ 6 → 113/113; 1 %/3 %/8 % climbs → 96/144/151 m of 100/150/160. Version the change (see §6). | Pure-function fixtures: flat-noise (gain < 5 % of v1), steady-grade (within 5 % of true), step plateau, single spike; existing 20 m boundary test kept for v1 behaviour. |
| RQ-3 | **High** | Any fix where the platform lacks a field (network/Wi-Fi fixes, some devices, mock providers) | Plugin delivers **0.0** for missing accuracy/altitude/speed/heading. Result: (a) a fix with *no* accuracy is treated as **perfectly accurate** and passes the 50 m gate — the `rejectedMissingAccuracy` branch is unreachable on Android; (b) a missing altitude is stored as **0.0** and, because the `altitude != null` filter never triggers, poisons elevation; (c) missing speed passes as "0 m/s". Restore also coalesces server nulls to 0.0. | `plugin-position` :171-178, :200-206; `plugin-mapper` `toHashMap`; `policy` :129-144; `helper` :146-149; `sync` :64-68 | **Overcount** (elevation) and unfiltered garbage fixes. Sim: one 0.0 altitude sample inside a 300 m plateau → **+100 m gain and +100 m loss** under v1 (43/43 even under the proposed smoothing unless dropped). | In `mapPosition` map exact `0.0` → `null` for **accuracy and altitude** with a comment citing the plugin contract (a real fix never has accuracy exactly 0.0; ellipsoidal altitude exactly 0.0 is a measure-zero event). Keep speed/heading as-is (0.0 is a legal value) but treat `speed == 0` as "unknown" for any Doppler-based rule. Elevation then skips null altitudes as already coded. `ActivitySyncModel.fromJson` should stop coalescing null → 0.0. Cheapest fix in this audit. | Service test building a `Position` from a map without `accuracy`/`altitude` keys → entity nulls; policy test `accuracy: 0.0` → `rejectedMissingAccuracy`; elevation test with an interior null; sync round-trip test preserving null. |
| RQ-4 | Medium | Urban-canyon / multipath spike (a fix jumps 40–60 m sideways for one or two samples, then returns) | First spike sample is rejected (implied speed > cap) and the anchor is kept — good. But the anchor's Δt keeps growing, so the **second** spike sample passes the same cap (same displacement, double the time) and is counted; the return leg is counted again. Walking/hiking's 5 m/s cap catches it; running (10) and cycling (30) do not. | `policy` :198-235 (Δt measured from a stationary anchor) | **Overcount** + max-speed spike. Sim, running 3 m/s, 60 m spike for 2 samples: +67 m on 900 m and max speed 22.8 km/h; 40 m spike: +48 m, 29.3 km/h. Walking: fully rejected. | *Provisional jump*: when a point is rejected for implied speed, remember it; accept the next point only if it is consistent with the anchor **or** confirms the provisional point (then treat the move as real). ~30 lines, pure, testable. Alternatively cap the single-step displacement at k·max(acc, 10 m) for run/cycle. | Policy sequence fixtures: spike-and-return (rejected wholesale), persistent shift (accepted once), per sport. |
| RQ-5 | Medium | First fix after Start / after Resume (warm-up, cached fix) | The first fix within 50 m accuracy becomes the zero-distance anchor even if it is 40 m off; the next good fix then adds a phantom 30–50 m and a max-speed spike. Stale cached fixes are correctly rejected by the active-boundary check. | `policy` :86, :159-166, :188-196 | **Overcount** at every start/resume. Sim: first fix 40 m off at 45 m accuracy → +14 to +26 m on a 90 m walk, max speed 9.5–23 km/h. | Covered by the RQ-1 gate (Δ ≥ k·max(acc)); optionally require the *first* anchor of a segment to have accuracy ≤ 20–25 m or be superseded by a better fix arriving within 10 s. | Notifier fixture: poor first fix then good fixes → distance within 10 % of the good-fix path; maxSpeed ≤ true × 1.2. |
| RQ-6 | Medium (decision) | Gaps > 30 s: stops without pausing, tunnels/underpasses, tree cover, temporary signal loss, and (until IP-3.4) every screen-off period | New anchor, **0 m**, drawn break. A 45 s stop loses ≈ the platform's 5 m displacement plus noise and leaves a visible break; a 2 min tunnel loses the whole stretch. Also, with the RQ-1 gate a *held* anchor would age past 30 s and reset while walking slowly — the gap must be measured from the last accepted point. | `policy` :87, :208-216; `segmenter` :35-39; existing audit F5 | **Undercount.** Sim: hiker stops 45 s → −5 m and a break; sim with a naive gate + old gap rule: slow hiking (0.6 m/s) counted 194 m of 360 m. | Keep "no bridge" as the safe default for now but (a) measure the gap from the last accepted fix; (b) make the reset sport-aware (walk/hike/run 30 s, cycle 60 s — measure); (c) later add a **bounded straight-line bridge** (gap ≤ 5 min run/walk, ≤ 10 min hike/cycle; both endpoints acc ≤ 20 m; implied speed ≤ cap and ≤ 1.5× rolling average) drawn dashed as "estimated" and counted, with a per-workout `bridgedMeters` counter. Straight line ≤ true path, so a bridge can only under-count. | Policy/segmenter fixtures for stop-and-go, tunnel (bridged vs not), gate-held-anchor slow walk (no reset); map fixture that a bridged segment renders dashed. |
| RQ-7 | Medium | Max speed | Single 5 s interval implied speed; noise-dominated (see RQ-1/4/5 numbers). Doppler speed is available on most GPS fixes and unused. | `provider` :687-693 | **Overcount.** A jogger routinely gets 20–30 km/h max speed. | Max over a ≥ 20 s (or ≥ 3-interval) window of *counted* points; or use reported Doppler speed when > 0 (RQ-3 semantics) bounded by the sport cap. Both cheap. | Fixture: jitter and spike fixtures assert maxSpeed ≤ true × 1.2; steady 3 m/s fixture asserts ≈ 3 m/s. |
| RQ-8 | Medium | Sport caps as the only jitter filter | For running/cycling the implied-speed cap admits 45–150 m single-sample jumps; walking/hiking's 5 m/s cap is doing double duty as a jitter filter, which is why walking looks cleaner than running. Reported-speed rejection drops a positionally-fine point on a Doppler glitch (harmless, anchor kept). | `policy` :88-91, :168-176, :226-235 | Overcount for run/cycle | Keep the caps (they are physically reasonable) but stop relying on them for noise: RQ-1 gate + RQ-4 provisional jump. Evaluate reported speed only when > 0. | Same fixtures run per sport with the same assertions. |
| RQ-9 | Medium | Long routes: 10,000+ points and any future interval tightening | Backend caps 12,000 locations per activity; a `400` is classified permanent, so an over-cap workout is **permanently unsyncable** with no local warning. At 5 s cadence that is ≈ 16 h moving; at 1–2 s (an IP-3.4 temptation) it is 3–6 h — a normal hike or ride. | `dto` :42, :196-199; sync audit `SYNC-05`; existing audit F14 | Silent sync loss | Keep ≈ 5 s cadence for the metric path; if IP-3.4 wants denser sampling for the *display*, thin at acceptance time (versioned) rather than sending more points; add a client-side pre-sync check that surfaces "route too long to sync" instead of a permanent silent failure; chunked upload is IP-4.2. | Payload fixture at 12,000 and 12,001; notifier test that a synthetic 12,001-point route yields a visible sync-blocked state. |
| RQ-10 | Medium | Long routes: 1,000 / 5,000 / 10,000 points in the live UI | Per accepted point: full list copy (O(n)), full re-segmentation and every polyline rebuilt with several `setState`s (O(n)); the Track screen watches the whole state. Total work is O(n²): ~1k points fine, ~5k noticeable, ~10k jank on mid-range devices (estimate, unmeasured). Persistence (one batch in one transaction) and indexed reads are fine at 10k. | `provider` :689; `map` :151-181, :192-210; `db` :279-294, :1161-1171; existing audit F7 / IP-3.5 | Not a metric error | Append to the last polyline when only the active segment grew; use the existing `select` providers; display-only simplification for the live polyline (persisted fidelity untouched). | Replay benchmark through the fake repository at 1k/5k/10k asserting bounded per-point cost. |
| RQ-11 | Low | Live pace | One interval, `duration.inSeconds` truncation (a 5.9 s interval is treated as 5 s → up to 20 % error), flickers between fixes. | `provider` :677-685; `helper` :5-16 | Display noise | Rolling 30–60 s window over counted points; use microseconds. Display-only, no version. | Unit test on a synthetic steady-pace fixture. |
| RQ-12 | Low | The platform's 5 m / 5 s filter is undocumented policy | Accepted sequences depend on `distanceFilter: 5` and the plugin's implicit 5000 ms interval, neither of which is named in `GpsPointAcceptancePolicy` or pinned by a test. Changing either silently changes every downstream metric. | `service` :66-84; `plugin-options` :58-59 | Reproducibility | Document both as part of the policy-v1 contract (a comment plus constants) and pin them with a test on the settings passed to the plugin (needs a small injectable seam). | Service test asserting `distanceFilter` and an explicit `timeInterval`/`AndroidSettings.intervalDuration`. |
| RQ-13 | Low | Timestamps: fix time vs wall clock | Fix times are the provider's `getTime()`; the active-boundary check compares them with `DateTime.now()`. With FusedLocation both are the system clock; on a device without Play Services the GPS provider's time can differ from a skewed system clock, rejecting the first *skew* seconds after each Start/Resume as "before boundary". Backward clock jumps freeze acceptance until GPS time catches up (existing audit F8). | `policy` :159-166; `lib/data/repositories/live_tracking_repository_impl.dart` :15 | Undercount, device-dependent | Measure on a non-Play-Services device before doing anything; a small tolerance (≤ 2 s) is the only cheap mitigation. | Device matrix item; notifier clock-jump tests. |
| RQ-14 | Low | Restored workouts and DST | Points and status rows for *restored* workouts are written as offset-less local ISO strings; `ORDER BY tp.timestamp` is a string sort, so a workout crossing a DST fall-back could be re-ordered on read (map zig-zag; metrics unaffected because they are stored, not recomputed). Device-recorded points are written with `Z` and are safe. | `sync` :65; `db` :290, :1161-1171; existing audit F13 | Rare | Write UTC for new rows. | FFI fixture spanning a synthetic DST fall-back. |
| RQ-15 | Low | Haversine on a 6371 km sphere | ≤ ~0.5 % systematic error vs the WGS-84 geodesic depending on latitude/direction (≈ 50 m on 10 km). Three distance implementations exist; only the policy's is on the metric path (`service` `calculateDistance` via Geolocator and `live_map_feed_helper.calculateDistance` are unused there). | `policy` :271-295; `service` :164-175; `live_map_feed_helper.dart` :10-24 | Negligible | Leave as is; delete the two unused helpers when touching those files (simplification, not a fix). | — |
| RQ-16 | Info | Calories | Speed-only MET table (cycling at 25 km/h is scored as "fast running" 14.5 MET; walking 5 km/h as 6.0), fixed 70 kg. Correctly labelled an estimate (IP-1 non-goal). | `helper` :61-92; `provider` :441-442 | Estimate only | Type-aware MET table when profile weight exists; not a route-quality item. | Unit table test. |
| RQ-17 | Info | `useMSLAltitude` off | Altitude is ellipsoidal, not mean-sea-level; a constant local offset that does not affect gain/loss. Only matters if absolute elevation is ever displayed. | `geolocator_android-5.0.3/lib/src/types/android_settings.dart` :19 | None for gain/loss | Nothing now. | — |

### 2.1 Things checked that are correct (do not "fix")

- **Units** are m / s / m/s in domain, storage, and API; km/h ×3.6 exactly once at
  presentation (`entity` :26-31; `helper` :44-59; `live_tracking_state.dart` :110-116;
  `sync` :16-19). D-003 holds.
- **Pause/resume**: paused fixes are markers only; the first resumed fix is a zero-distance
  anchor; late paused fixes after the resume boundary are rejected; movement during a pause
  never bridges (`provider` :300-388, :671-675; `policy` :159-196; tests
  `live_tracking_provider_test.dart` "paused movement and the first resumed point add no
  distance"). Residual cost: the first ≈ 5 m after every resume (the platform's displacement
  filter) is lost — accepted trade-off, quantify on device.
- **Finish while paused** closes the open pause exactly once (`timeline` :91-114).
- **Delayed / out-of-order / duplicate fixes**: strictly-increasing fix time is enforced
  against the last accepted point (including paused markers) (`policy` :146-157); batched
  late deliveries after a doze wake are handled correctly *because fix time, not arrival
  time, drives the arithmetic* — keep that.
- **One accepted sequence** feeds map, storage, distance, max speed, elevation, and sync —
  see §3.

---

## 3. Do map, stored points, distance, pace, max speed, and sync all derive from the same accepted sequence?

**Yes, for `metricsVersion 2` rows**, and the derivation is deterministic enough to be
replayed:

| Consumer | Input | Evidence |
| --- | --- | --- |
| Live map polylines | `session.trackingPoints` + `statusChanges` through `WorkoutRouteSegmenter` (segments break on status transitions and on > 30 s between consecutive stored points) | `map` :151-181 → `LiveMapSegmentBuilder.buildSegments` → `segmenter` :10-62 |
| History map | the same rows read back, same segmenter | `history-map` :104; `db` :1161-1171 |
| Distance | Σ haversine(anchor, point) where the anchor is always the previous stored point in the same segment (every accepted active point advances the anchor; rejected points do not) | `provider` :687-696; `policy` :188-245 |
| Max speed | max over the same consecutive pairs (d/Δt) | `provider` :687-693 |
| Elevation | the same stored points through `buildActivePointSegments` at Finish | `provider` :463-467; `segmenter` :64-73 |
| Average speed / pace / calories | total distance and the timeline's active duration | `provider` :441-475 |
| SQLite | the same points, status changes, and the incremental totals (not recomputed) | `db` :253-311 |
| Sync payload | the same entity fields, points, and status changes; UTC | `sync` :9-54 |

Because the anchor is always the previous stored point within a segment, and segments are
defined by stored status changes and stored timestamps, **v2 distance, max speed, and
elevation can be re-derived exactly from (points, statusChanges, startTime, endTime,
pausedDuration)** — the only inputs a replay lacks are the rejected fixes, which by
construction never influenced the totals. This is the property that makes a versioned,
non-destructive metric evolution (§6) possible; do not break it (e.g. by counting distance
from a point that is not stored, or by storing a point that was not the anchor's successor).

Two deliberate deviations, both fine: `LiveTrackingState.currentLocation` includes paused
markers that are not in the route (`provider` :673); and restored (`fromJson`) points
coalesce null optionals to 0.0 (`sync` :64-68 — RQ-3 asks to stop that).

Rows with `metricsVersion 1` (pre-IP-1) contain raw points including paused movement and
are drawn with dashed paused segments; their stored totals must not be recomputed under any
new rule (§6).

---

## 4. Recommendations, and which thresholds need a real device

Every value below is a **starting point for measurement**, not a verified constant. The
policy is `const` today; the recommended way to tune without guessing is a debug-only
"calibration capture" (§4.7) plus MC-1.5.

### 4.1 Accuracy thresholds

- Keep **50 m** as the ceiling for *accepting a fix at all* (route/marker); it rejects
  garbage without starving urban users.
- Add a separate, tighter bound for *contributing distance*: **≤ 25 m** walk/hike/run,
  **≤ 35 m** cycle (larger per-sample displacement makes noise matter less). A fix between the
  two bounds is stored and drawn but adds 0 m and holds the anchor.
- Treat accuracy **exactly 0.0 as missing → reject** (RQ-3).
- First anchor of a segment: prefer accuracy **≤ 20–25 m**, or let a better fix arriving
  within 10 s replace it (RQ-5).
- **Device measurement required:** the accuracy distribution (p50/p90) under open sky, tree
  cover, and urban canyon on the target device class, and what fraction of fixes each bound
  would drop. Without it, 25 m could either be too loose (no benefit) or too tight (a
  walking-in-the-city route with no distance).

### 4.2 Speed limits

- Keep the caps: walk/hike **5**, run **10**, cycle **30 m/s**. They are physically sane
  and cheap. Only evaluate reported speed when it is **> 0** (0.0 = unknown on this plugin).
- Add sport *floors* for counting distance (stationary detection): walk **0.3**, hike
  **0.2**, run **0.5**, cycle **0.8 m/s** — from Doppler speed when available, else from
  implied speed over ≥ 10 s.
- **Device measurement required:** how often `hasSpeed()` is true on fused fixes (Doppler
  availability), and the stationary Doppler-speed distribution (is it reliably < 0.3 m/s?).
  If Doppler is unavailable or noisy on common devices, the floor must fall back to the
  displacement gate alone and be looser.

### 4.3 Stationary-jitter handling

- Distance-contribution gate: count Δ only if Δ ≥ **k · max(acc_anchor, acc_point)** with
  k ≈ **1.5** (range 1.0–2.0), *and* not below the speed floor. Keep the point (route
  continuity), hold the anchor. Do not add an auto-pause state machine — the gate gives the
  same benefit with no UI state.
- Sim of exactly this gate: stationary 15 min → **0 m** at all three noise levels (v1: 0.8–4.2
  km); running/cycling within +1–3 % of v1; walking +9 %, slow hiking +12 % (v1: +41 % / +157
  % under the same synthetic noise) — the residual is the unavoidable "summed noise" of
  straight-line integration and would need position smoothing to remove; not worth it now.
- **Device measurement required:** k. Fused output while stationary is filtered and
  correlated, so real jitter is smaller than the sim's — measure 5-minute stationary captures
  in the three environments and pick the smallest k that yields < 20 m per 5 min.

### 4.4 Gap policy (connect, break, or ignore)

- **Break** the drawn route and reset the anchor only when **no fix has been accepted** for
  > 30 s (walk/hike/run) / > 60 s (cycle). Never measure the gap from a held anchor.
- **Connect (bridge)** later, bounded: gap ≤ 5 min (run/walk) / 10 min (hike/cycle), both
  endpoints acc ≤ 20 m, implied speed ≤ cap and ≤ 1.5× rolling average → count the straight
  line, draw dashed, expose `bridgedMeters`. Straight-line is a lower bound of the true path,
  so bridging can only under-count relative to reality while removing the current
  whole-stretch loss.
- **Ignore** (0 m, break) beyond those bounds, exactly as today.
- **Device measurement required:** whether FusedLocation with min-update-distance = 5 m
  withholds fixes entirely while stationary (this decides how often the 30 s reset fires at
  ordinary stops), and typical outage lengths in the maintainer's real terrain. Until IP-3.4
  lands, every screen-off period is also a gap; the bridge bounds should be chosen with that
  in mind, or bridging should wait for IP-3.4.

### 4.5 Elevation smoothing

- Drop altitude **exactly 0.0** as missing (RQ-3); once vertical accuracy is captured (§6
  stage 3), also drop fixes with vertical accuracy > 15–20 m.
- Centred moving average over **~7 samples or ~30 s**; then a **hysteresis accumulator**
  with threshold **T ≈ 5–8 m**: commit gain/loss only when the smoothed altitude has moved
  ≥ T from the last committed altitude, then move the reference. Per active segment; segment
  ends unsmoothed is acceptable with hysteresis.
- Sim: flat σ_v 4 m → 0/0 (v1 490/510); σ_v 6 m → 113/113 (v1 1104/1083); steady 1 %/3 %/8 %
  climbs recovered to 96 %/96 %/94 % of true (v1: 0 %).
- **Device measurement required:** σ_v of fused altitude on the target device (sets T; 5 m
  under-filters a σ_v 8 device, 8 m under-counts real rolling terrain on a σ_v 3 device) and
  the rate of missing altitude (network fixes) in the city.

### 4.6 Sport-specific settings (proposed table)

| Setting | Walking | Hiking | Running | Cycling | Needs device data? |
| --- | --- | --- | --- | --- | --- |
| Speed cap (keep) | 5 m/s | 5 m/s | 10 m/s | 30 m/s | No (physical) |
| Speed floor for counting | 0.3 | 0.2 | 0.5 | 0.8 m/s | **Yes** (Doppler behaviour) |
| Accept accuracy ≤ (keep) | 50 | 50 | 50 | 50 m | No |
| Count distance if accuracy ≤ | 25 | 25 | 25 | 35 m | **Yes** |
| Displacement gate k | 1.5 | 1.5 | 1.5 | 1.5 | **Yes** |
| Gap reset (no accepted fix for) | 30 s | 30 s | 30 s | 60 s | **Yes** |
| Bridge if gap ≤ | 5 min | 10 min | 5 min | 10 min | **Yes** (terrain) |
| Elevation hysteresis T | 6 m | 6 m | 6 m | 8 m | **Yes** (σ_v) |
| Max-speed window | 20 s | 20 s | 20 s | 20 s | No |
| Live-pace window | 30 s | 60 s | 30 s | 30 s | No |

### 4.7 The measurement tool (so thresholds are not guessed)

A debug-only, on-device "calibration capture": while a workout runs, keep the *raw*
pre-policy samples in memory as **displacements from the first fix in metres** (never
absolute coordinates), with accuracy, speed, altitude, and Δt; on Finish, offer an export of
aggregate statistics (accuracy percentiles, stationary drift per 5 min, `hasSpeed`/altitude
availability rates, σ_v). This satisfies the no-coordinate rule, costs a few hundred lines
behind a `--dart-define`, and is what MC-1.5 needs to produce a dated evidence row.

---

## 5. Fake-GPS / device test matrix (synthetic routes only)

**Rules.** All routes are generated (square, circle, out-and-back, zig-zag) around an
arbitrary synthetic origin — the unit tests' fixed fixture origin is fine — with injected
defects. No real route is ever recorded into the repository, a fixture, or a log. Real-device
calibration runs keep only the aggregate numbers from §4.7. Fake-GPS apps and the emulator
set `isMocked`; recording that flag on the point (optional, one boolean) makes test workouts
distinguishable but is not required.

**Sources.** (S1) the existing `_FakeLiveTrackingRepository` in
`test/presentation/features/live_tracking/providers/live_tracking_provider_test.dart` for
deterministic notifier-level replay; (S2) Android emulator route playback (Extended Controls
→ Location → import a *generated* GPX/KML, or `adb emu geo fix`); (S3) a mock-location app on
a physical device with a generated route; (S4) a physical device outdoors for the §4
measurements only.

| # | Scenario | Synthetic input | Injected defect | Assertion | Source |
| --- | --- | --- | --- | --- | --- |
| T1 | Stationary drift | 5 min at one point, 5 s cadence | Gaussian σ 3 / 8 / 15 m, acc 8 / 20 / 40 m, Doppler speed ~0 | v2 distance < 20 m; maxSpeed unchanged; v1 documented value recorded for comparison | S1, S3 |
| T2 | Warm-up | first fix 40 m off at acc 45, then acc 6 fixes on a 90 m walk | poor first fix | distance within 10 % of 90 m; maxSpeed ≤ 1.2× walking speed | S1 |
| T3 | Multipath spike | 3 m/s straight, 60 m lateral for 2 samples | spike + return | ≤ +5 m over baseline; maxSpeed ≤ 1.2× 3 m/s; per sport | S1 |
| T4 | Persistent shift | 3 m/s straight, permanent 60 m lateral shift | real jump | counted once (≈ +60 m), no reset, no break | S1 |
| T5 | Stop-and-go | 60 s move, 45 s stop with no fixes, 60 s move | gap > 30 s | v1: 2 segments, −5 m; v2 (gap from last accepted): same, then with bridge: 1 dashed bridge ≤ 5 m | S1 |
| T6 | Tunnel | 2 min without fixes at 8 m/s cycling | long gap | no bridge (bounds) → break; with bounds relaxed in test → straight-line ≤ true, dashed | S1 |
| T7 | Slow hiking with held anchor | 0.6 m/s, acc 12, σ 4, 10 min | gate holds anchor > 30 s | **no** reset while fixes keep arriving; distance within 15 % of 360 m | S1 |
| T8 | Missing fields | fixes with `accuracy` / `altitude` / `speed` keys absent (0.0 from plugin) | plugin contract | accuracy 0.0 rejected; altitude 0.0 skipped in elevation; speed 0.0 not used as Doppler | service + policy + helper unit tests |
| T9 | Elevation noise | flat 10 km, σ_v 2 / 4 / 6 / 10 | vertical noise | gain and loss each < 5 % of v1; < 120 m at σ_v 6 | helper unit |
| T10 | Elevation climb | 1 % / 3 % / 8 % steady grades, no noise; then with σ_v 4 | none / noise | within 5 % of true (clean); within 15 % (noisy) | helper unit |
| T11 | Elevation dropout | 300 m plateau with one 0.0 sample | missing altitude | 0 gain / 0 loss | helper unit |
| T12 | Pause / resume anchoring | move, pause, walk 200 m during pause, resume, move | paused movement + late paused fix after resume | paused Δ = 0; first resumed = 0; late fix rejected; map break at resume | S1 (exists partially — extend) |
| T13 | Out-of-order / duplicate delivery | fixes delivered with one older timestamp and one duplicate | ordering | both rejected; no anchor change | S1 (policy test exists; add notifier level) |
| T14 | Delayed batch after doze | 30 s of fixes delivered at once with correct 5 s spacing | delivery delay | first fix after the gap resets, the rest count normally (fix time drives arithmetic) | S1 |
| T15 | Long route | 1,000 / 5,000 / 10,000 / 12,001 points generated | volume | per-point processing cost bounded (benchmark); save/read round-trip; sync payload at 12,000 accepted, 12,001 surfaces a visible blocked state | S1 + FFI DB + payload fixture |
| T16 | Clock jump | +5 min / −5 min wall-clock jump mid-workout | clock | elapsed clamps as documented; distance continues after the GPS time passes the last accepted | S1 (notifier-level, missing today) |
| T17 | Emulator playback | generated square/out-and-back GPX at 1.4 / 3 / 8 m/s | none | distance within 3 % of the generated length; elevation ≈ generated profile | S2 |
| T18 | Mock-location app | same generated route on a physical device | provider without accuracy (some apps) | T8 behaviour observed end-to-end; `isMocked` visible if recorded | S3 |
| T19 | Real-device calibration (§4.7) | none — real walking/running/cycling by the maintainer | environment | only aggregates retained: accuracy percentiles, drift/5 min, `hasSpeed` rate, σ_v; feeds k, T, floors, bounds | S4 (MC-1.5) |
| T20 | Non-Play-Services device (if available) | T2 + T12 | GPS-provider clock skew | first-fix-after-resume not rejected for > 2 s | S4 |

T1–T16 are pure or fake-repository tests and run in `flutter test`; T17–T20 are manual and
produce dated evidence rows, never a "verified" claim inside the repository.

---

## 6. Staged implementation plan (historical versions preserved, no rewrites)

**Invariants for every stage:** old rows are never recomputed or rewritten; every stored
metric remains interpretable by its version marker; the accepted sequence stays replayable
(§3); the backend accepts a new marker *before* any app that emits it can reach users
(backend deploys on merge, the app via Play Store — the asymmetry helps here); each stage
appends an IP-1 evidence row and adds tests in the same change; rollback is a constants
revert or a flag, never a data change.

**Versioning choice.** `metricsVersion` (1 = legacy raw route, 2 = accepted-only route with
30 s gap segments) describes how stored *values* are interpreted; the SQLite `CHECK
(metrics_version IN (1, 2))` (`db` :148-149) and the backend `SUPPORTED_METRICS_VERSIONS`
(`dto` :23-25) both hard-code that set. Relaxing the SQLite CHECK means rebuilding the
`workouts` table under `PRAGMA foreign_keys=OFF` (children cascade otherwise) — doable but
the riskiest migration in this plan. The policy changes below do **not** change how stored
values are interpreted (still metres, still accepted-only, still segment-on-gap), only which
fixes are accepted and how gain is derived. Recommended: **add a nullable
`gps_policy_version` column** (`ALTER TABLE … ADD COLUMN`, cheap, no rebuild; existing v2
rows backfilled to 1, v1 rows left NULL), mirror it as an optional `gpsPolicyVersion` on the
backend, and bump it (2, 3, …) per policy change. Bridged gaps (stage 4) are the one feature
that changes rendering; gate the dashed "estimated" segment on `gpsPolicyVersion ≥ 3` (or a
per-segment marker). Reserve `metricsVersion 3` for a future change to value semantics. If the
maintainer prefers a single marker, do the CHECK relaxation once as `metrics_version >= 1`
in the same v7 migration.

| Stage | What | Behaviour change for new workouts | Old workouts | Tests | Rollback |
| --- | --- | --- | --- | --- | --- |
| **0** — evidence and pins | Add T1–T16 as fixtures against the *current* behaviour (they document v1's numbers); pin `distanceFilter`/interval (RQ-12); add the debug calibration capture (§4.7); add privacy-safe per-workout counters (rejected-by-reason, held-anchor count) kept in memory and shown on a debug screen only. Delete the two unused distance helpers if touched (RQ-15). | None | None | The fixtures themselves | Revert |
| **1** — plugin contract fix | `mapPosition` maps exact 0.0 → null for accuracy and altitude; `fromJson` stops coalescing null → 0.0; policy already rejects null accuracy; elevation already skips null altitude. **Backend first:** nothing needed (nulls already allowed, `dto` :72-84). | Fixes with no accuracy are rejected instead of accepted as perfect; missing altitudes no longer poison elevation. `gps_policy_version` column added (SQLite v7, ALTER only) and written as **2**; backend optional field deployed before the app. | Untouched (NULL / 1) | T8, T11, sync round-trip, migration v6→v7 fixture via `LocalDbTestHarness` | Revert the mapping; rows already written with version 2 stay correct (they are a subset of what v1 would have accepted) |
| **2** — noise-aware acceptance | RQ-1 gate (Doppler floor + k·accuracy), gap measured from last accepted (RQ-6a), provisional jump (RQ-4), windowed max speed (RQ-7), first-anchor accuracy preference (RQ-5); rolling live pace (RQ-11, display only). Constants from stage-0/T19 measurement, otherwise the §4.6 starting values. Written as `gps_policy_version 3`. | Less phantom distance, sane max speed | Untouched | T1–T5, T7, T12–T14, T16; per-sport parametrised | Constants back to v1 values keeps the architecture (IP-1 rollback rule); rows tagged 3 remain interpretable |
| **3** — elevation | RQ-2 smoothing + hysteresis, per active segment; optional new nullable columns `altitude_accuracy`, `speed_accuracy` (SQLite ALTER, backend optional fields, **backend first**) so vertical/speed accuracy can gate; written as `gps_policy_version 4` if columns land, else folded into stage 2's version. | Gain/loss no longer noise-dominated; gentle climbs counted | Untouched — old `elevation_gain` values stay as recorded and labelled by version | T9–T11; migration fixture | Revert function; old rows unaffected |
| **4** — gap bridge (decision) | RQ-6c bounded straight-line bridge, dashed rendering, `bridgedMeters` counter; only after IP-3.4 (so gaps mean signal loss, not screen-off) and after T19 terrain data. Segmenter learns the dashed "estimated" segment for `gps_policy_version ≥` this stage. | Tunnels/underpasses no longer lose the whole stretch | Untouched | T5, T6, map widget test for dashed rendering | Bounds to zero disables bridging; rows keep their counter |
| **5** — display and volume | RQ-10 append-only polyline, `select` providers, display-only simplification; RQ-9 pre-sync length check with a visible blocked state; density decisions in IP-3.4 made with the 12,000 cap in view. | UI only | Untouched | T15 benchmark; payload fixtures | Revert |

Optional later (not planned here): a read-only "recomputed under policy N" view for old
rows via §3 replay — never a rewrite.

---

## 7. Top five route-quality improvements by value ÷ effort

1. **Treat the plugin's 0.0 as missing for accuracy and altitude (RQ-3).** ~10 lines plus
   tests. Removes a whole class of silent garbage-fix acceptance and the ±100 m elevation
   spikes from network fixes. No threshold to measure.
2. **Elevation hysteresis + wider window (RQ-2).** One pure function, versioned. Today's
   gain/loss are noise on flat routes and zero on gentle climbs; the sim shows the proposed
   algorithm within ~5 % of truth on clean climbs and ~0 on flat noise at σ_v 4 m. Only T
   needs a device number.
3. **Distance-contribution gate with the gap measured from the last accepted fix (RQ-1,
   RQ-5, RQ-6a).** ~40 lines in the policy, all fixtures pure. Removes stationary drift and
   warm-up phantoms; the sim shows 0 m for 15 min stopped versus 0.8–4 km today. Needs k and
   the Doppler floor measured.
4. **Windowed max speed and rolling live pace (RQ-7, RQ-11).** ~20 lines each. Max speed
   stops being "the biggest jitter"; live pace stops flickering. No device data needed.
5. **Provisional-jump confirmation for running/cycling (RQ-4).** ~30 lines. Closes the
   "second-try acceptance" hole that lets a there-and-back multipath spike count twice for
   the two sports whose caps are too high to catch it. Threshold benefits from urban
   measurement but has a safe default (k·max(acc, 10 m)).

Bridging gaps (RQ-6c) is deliberately not in the top five: its value is real but it depends
on IP-3.4 and terrain measurement, and done early it would bridge screen-off holes.

---

## Appendix A — tests read and where the gaps are

- `test/core/tracking/gps_point_acceptance_policy_test.dart` (12): thresholds pinned,
  finiteness, ranges, accuracy bounds (including `accuracy: 50` accepted, `50.0001`
  rejected; **`0.0` never tested**), monotonic timestamps, resume boundary, reported/implied
  speed caps per sport, 30 s boundary, anchor kept after a rejected jump, paused marker,
  haversine spot value. Every distance is stubbed; **no sequence fixture** (jitter, spike,
  warm-up, stop-and-go).
- `test/core/tracking/workout_route_segmenter_test.dart` (4): pause/resume split, > 30 s
  split, legacy behaviours, one exact-20 m segmented elevation.
- `test/core/tracking/workout_timeline_test.dart` (4): finish-while-paused, open pause,
  repeated pauses, backward clamp.
- `test/core/utils/calculation_helper_test.dart` (8): m/s, pace, formatting, completion
  summary. **No elevation-noise fixture; no steady-grade fixture; no missing-altitude
  fixture.**
- `test/presentation/features/live_tracking/providers/live_tracking_provider_test.dart`
  (18): pause/resume distance, finish-while-paused, elapsed timer, rejected samples
  (jump/accuracy/non-monotonic/NaN), start/reset/dispose/account-exit serialisation, cleanup
  and save failure paths. **No jitter, spike, warm-up, gap, clock-jump, or long-route
  fixture at notifier level.**
- `test/core/services/live_tracking_service_test.dart` (1): field pass-through with all
  fields present. **No absent-key case.**
- `test/presentation/features/live_tracking/models/live_tracking_state_test.dart` (4) and
  `test/core/services/local_db_service_metrics_test.dart` (4): units and version handling.
- **Absent:** any `LiveMapFeed`/`WorkoutHistoryMapViewer` test, any elevation
  round-trip through the segmenter with noise, any 1k/5k/10k route test, any payload-cap
  fixture on the client.

## Appendix B — explicitly not verified

- Nothing was run except the synthetic Python replay; the Flutter and backend suites,
  analyzer, builds, emulator, devices, CI, staging, and production were not touched.
- All Android runtime statements (5000 ms default interval, min-update-distance semantics,
  `has*()`-gated fields, `_toDouble(null) → 0.0`, FusedLocation vs LocationManager time
  base) are read from the pinned plugin sources and Android documentation, not observed on a
  device.
- The synthetic magnitudes assume independent Gaussian noise; real fused output is filtered
  and correlated, so real drift is smaller. The *direction* and *mechanism* of every finding
  is established from the code; the *size* is what §4 asks the device to measure.
- Existing-audit items cited (`F5`, `F7`, `F8`, `F12`, `F13`, `F14`, `SYNC-05`) were not
  re-audited.
