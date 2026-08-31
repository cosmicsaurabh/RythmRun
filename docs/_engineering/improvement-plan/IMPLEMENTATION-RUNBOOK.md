---
published: false
---

# Reliability implementation runbook

This is the execution order for the workout, Android background-tracking, map,
route-quality, accessibility, and sync findings reviewed in August 2026. It does
not replace the improvement-program contracts:

- [README.md](./README.md) owns program rules, decisions, dependencies, and the
  definition of done.
- [STATUS.md](./STATUS.md) owns the live phase summary.
- [ACTION-REQUIRED.md](./ACTION-REQUIRED.md) is the only register for device,
  hosted, provider, production, and maintainer-only checks.
- The IP phase files own durable requirements, rollout rules, and evidence.

Point-in-time audits are active discovery inputs, not parallel authorities. They
stay in the repository and are linked from this runbook while their mapped work
is pending. If this runbook and a phase file disagree, the phase file wins. If
documentation and code disagree, code is the current behavior and the
discrepancy must be recorded before implementation continues.

Nothing in this runbook changes the standing release fact: **IP-0 remains the P0
operational blocker.** Repository work cannot complete any manual check.

## Checkpoint lifecycle

Each row advances through exactly these states:

`Pending` → `In progress` → `Implemented` → `Documentation reconciled` →
`Staged for review` → `Committed`

Only one checkpoint is staged at a time. The maintainer reviews and commits it;
the next checkpoint does not start while the prior staged checkpoint remains
unreviewed. A checkpoint is not `Implemented` until its scoped verification has
passed. `Staged for review` is repository state, not deployment, device,
staging, or release verification. A pre-existing commit is recorded, not
rewritten, even when its message or process did not follow this lifecycle.

## Start or resume a checkpoint

Every future agent uses this sequence before editing:

1. Read the handoff at the top of [STATUS.md](./STATUS.md).
2. Read this runbook's workstream row and ordered active step.
3. Read the mapped rows in [AUDIT-REGISTER.md](./AUDIT-REGISTER.md).
4. Run `git status --short --branch`, inspect both `git diff` and
   `git diff --cached`, and compare the branch/HEAD with the handoff. Git is the
   authority when the snapshot is stale.
5. Inspect the active checkpoint: read its owning phase, linked source reports,
   the decision table in [README.md](./README.md), applicable maintainer gates in
   [ACTION-REQUIRED.md](./ACTION-REQUIRED.md), and any existing staged/unstaged
   implementation. If a complete checkpoint is already staged, verify and
   report it; do not mix the next checkpoint into the index.
6. Continue only the defined checkpoint. Run focused then applicable full gates,
   reconcile maintained docs, stage only when STATUS or the maintainer directs
   it, and inspect the exact staged diff. Never commit or push unless the
   maintainer asks.

When pausing, STATUS must name the branch, base/HEAD, staged and unstaged files,
verification already run, blockers/nonclaims, and the single next action. Phase
evidence owns durable results; git history owns old implementation detail.

## Repository snapshot

Snapshot taken 2026-08-22 after reading the improvement program, staged audits,
relevant Flutter/backend code, Android configuration, tests, and branch graph;
updated 2026-08-31 for the W1 commit and W2 repository correction.

- Working branch: `workout-reliability`, created from `origin/main` at
  `792bd52` (PR #190). The tree at the former local `auth-impr` HEAD `d0e5b92`
  was identical to that remote-main tree, so the staged index carried across
  without rebasing or conflict.
- Local `main` is stale at `48c8ae0`; do not base work on it until it is
  fast-forwarded safely.
- `origin/auth-impr` points at `eb358ed`, the source commit for the eight original
  audit/design reports and duplicate STATUS entries. Step 1 restores the reports
  verbatim but does not cherry-pick the duplicate status history.
- The public remote refs were refreshed before the branch was created.
- The prior agent committed Step 1 locally as `6c75fb2` with subject
  `i dont know`; it is included in `origin/workout-reliability` and its history
  must not be amended without explicit maintainer approval. No application gates
  were run for that documentation-only commit.
- The W0 follow-up was committed locally as `53cb751` with subject
  `docs(plan): reconcile reliability handoff and audit map`.
  W1 was then committed as `1315378` with subject
  `fix(storage): retain owner workouts across session exit`; HEAD and
  `origin/workout-reliability` point to that commit. W2 remains unstaged.

Verified current behavior that controls the order:

- Normal logout, account switch, and forced authentication loss retain every
  owner workout and queued delete. The workout repository history contract now
  takes the explicit owner ID. Teardown awaits that owner's restore-flag reset
  and provider invalidation before credential cleanup completes; the persistence
  service verifies write success and readback, and a failed reset retains the
  recoverable scope. A pending forced-loss marker reruns owner teardown after
  restart before credentials are removed. Provider state and SQLite queries
  remain user-scoped, admitted work drains before a new account activates, and
  A's retained rows remain inaccessible to B.
- The owner-scoped local purge primitive remains intact and covered for a future
  explicit account-deletion path. There is no wired in-app deletion flow, so W1
  does not claim account-deletion E2E behavior.
- Completed-workout save is local-first and transactional. Push is idempotent by
  `(userId, clientSyncId)`, and remote workout deletion already has a durable
  owner-scoped queue.
- Restore remains a one-shot insert-only bootstrap behind a boolean flag. It has
  no cursor, revision, tombstones, ongoing pull, or image restore. W2 isolates
  restore read/download/completion-write failure so an owner-valid pass still
  pushes queued workout/delete/image work; the read-only GET uses idempotent
  authenticated replay. Full sync flights and workout passes coalesce one
  bounded follow-up, typed transport failure stops remaining queue work, and
  owner/gate checks reject stale completion.
- Connectivity now uses platform interface state without the recurring public
  DNS socket/timer. It replays current state safely, treats recovery to `slow`
  or `connected` as one trigger, and defers resume sync while a workout is
  active or paused. Interface availability does not prove internet reachability;
  real request outcomes remain authoritative.
- One production GPS stream feeds the notifier. Older claims that the map owns a
  second GPS subscription are stale. Active workout state is still memory-only,
  the first SQLite write is at Finish, pause leaves high-accuracy GPS running,
  and no app-owned Android foreground service exists.
- Android declares target/compile SDK 36 and the bumped Gradle/AGP/Kotlin
  versions, but clean debug/release proof and physical-device behavior have not
  been recorded. A referenced `proguard-rules.pro` is absent.
- Tile availability is independent of recording and durable save. Map/provider
  lifetime, error reporting, privacy-safe logging, and long-session rebuild
  costs remain open. Provider policy must be rechecked from current official
  sources when that checkpoint starts.
- The proposed GPS noise/elevation constants come from static/synthetic review,
  not device calibration. Zero altitude is not proof that altitude was absent.
  No threshold or journal-mode recommendation is accepted without measurement.

## Workstream status

| ID | Workstream | State | Owning contract | Review note |
| --- | --- | --- | --- | --- |
| W0 | Program control and audit consolidation | **Committed** as `53cb751` on `origin/workout-reliability` | README, STATUS, runbook, audit register | Documentation-only; no application gate claimed |
| W1 | Retained owner data at session exit | **Committed** as `1315378` on `origin/workout-reliability` | D-004, IP-2.7, IP-1.3 | Repository gates passed; external/ACTION evidence remains open |
| W2 | Schema-free sync safety | **Documentation reconciled; unstaged** | IP-2.7, IP-4 | Runtime, tests, full Flutter gates, and owning docs are ready for maintainer review; no throwaway pull protocol added |
| W3 | Tracking truth, permission, accessibility, and resource fixes | Pending | IP-1, IP-3.3/3.5, IP-5.6 | Behavior changes split into focused commits |
| W4 | GPS/route-quality measurement and policy version | Pending | IP-1.2, IP-3.1 | Measurement-gated; do not guess thresholds |
| W5 | Durable workout schema, engine, finalization, and recovery | Pending | IP-3.1–3.3 | Blocked from rollout by IP-2.7 storage decision |
| W6 | Android foreground execution and notification controls | Pending | IP-3.4 | Physical-device evidence required |
| W7 | Long-session and map performance/reliability | Pending | IP-3.5, IP-5.6 | Preserve full-fidelity stored route |
| W8 | Versioned sync, restore, and cleanup | Pending | IP-4.1–4.6 | Additive backend rollout; old app remains supported |
| W9 | Release and operational evidence | Pending | IP-0, IP-5, ACTION-REQUIRED | Repository cannot mark manual checks verified |

## Dependency-aware implementation sequence

### Step 1 — Consolidate control documents

**Implementation.** Create this runbook; correct STATUS/IP-2/IP-3/IP-4 where
the staged audits conflict with code or existing decisions; remove duplicate
audit-only delivery rows from STATUS; retain all eight original reports and link
them to their implementation steps and retirement gates.

**Why now and dependencies.** The audits prescribe competing foreground-service,
wake-lock, SQLite-version, route-anchor, and logout behaviors. Implementation
cannot start from multiple contradictory plans. This step depends only on the
repository inspection and changes no runtime behavior.

**Input disposition.** The live reports and their step mapping are recorded in
[AUDIT-REGISTER.md](./AUDIT-REGISTER.md). Canonical requirements remain in IP-1
through IP-5; the reports retain detailed evidence, alternatives, test ideas,
and unresolved findings until implementation proves their outcome.

**Outcome and git.** The prior agent created `workout-reliability` from
`origin/main@792bd52` and committed the eight source reports, this runbook, and
canonical-plan corrections as local commit `6c75fb2`. It ran documentation
checks only. The current documentation-only follow-up adds the missing complete
audit register, live handoff, resume rules, and verified-current documentation
corrections without rewriting that commit. The follow-up was committed locally
as `53cb751`; no runtime or test file belonged to W0.

### Step 2 — Preserve all completed owner data across session exit

**Implementation.** Make provider invalidation awaitable through the teardown
contract. Remove the ordinary-session call to `clearLocalWorkouts`; retain all
synced, unsynced, blocked, delete-pending, point, status, and image rows. Continue
draining admitted work and invalidating every user-scoped provider before another
account activates. Await the per-user restore-flag reset until IP-4 replaces it
with a cursor. Keep the owner-scoped local purge primitive intact and reserve it
for a future explicit account-deletion path.

**Why now and dependencies.** Before W1, this was the repository's highest code
risk because teardown violated a binding product decision and could erase the
durable state that IP-3 recovery and IP-4 sync must preserve. It depends on Step
1, not on network availability; logout must never require a successful sync.

**Tests.** Cover voluntary logout, forced loss, and A→B→A with synced and
unsynced workouts, queued deletes, children, and images; prove B cannot access A;
prove A later pushes/deletes exactly once; prove finish-and-exit yields one row;
prove teardown awaits invalidation/reset; preserve coverage of the owner-scoped
local purge primitive. Account-deletion integration and E2E remain open.

**Outcome, evidence, and git.** W1 removes the normal-session workout purge,
makes user-state invalidation awaitable, awaits the old user's restore-flag
reset through an explicit-owner repository contract, retains owner rows across
A→B→A, and leaves the owner-scoped local purge primitive intact. Failed reset
persistence blocks cleanup and retains provider access for recovery; a pending
forced-loss restart reruns owner teardown before credential removal. The
real-SQLite gate retains synced, unsynced, blocked, and delete-pending A rows with
their point/status/image children and delete queue, performs no remote I/O during
exit or B's session, then creates and deletes the correct remote IDs exactly once
after A returns. A live finish-and-exit gate creates exactly one durable workout
row. One focused command across seven suites passed 79 tests, including five
local database ownership/purge cases and the real-SQLite gate tests. Locked
restore passed; all 366 Flutter tests passed; analysis reported nine existing
infos and no warnings or errors; formatting changed none of the 13 Dart files;
root `git diff --check` passed. W1 changes an internal Flutter repository API,
but there is no backend or server HTTP API, schema, migration, exit-time sync, or
account-deletion E2E change. At this checkpoint a failed
`history_restored=true` completion write could still abort a sync pass before
push while work remained queued; Step 3 owns that later correction. W1 was
committed as `1315378` with subject
`fix(storage): retain owner workouts across session exit` and pushed to
`origin/workout-reliability`.

### Step 3 — Isolate restore failure from push and make sync passes complete

**Implementation.** Keep a failed bootstrap visible/retryable without preventing
local workout/delete/image push in the same pass; opt the read-only restore GET
into the existing safe post-refresh replay contract; coalesce a sync request that
arrives during an active pass into one bounded follow-up pass; stop quickly on
transport failure; make reconnect/resume triggers deterministic. Remove or gate
the process-wide ten-second public-DNS probe and rely on platform state plus real
request outcomes.

**Why now and dependencies.** These are schema-free loss/availability fixes and
test seams needed before IP-3 creates more durable work. W1 must be accepted and
committed, and the maintainer must explicitly authorize W2, before this step
starts. This step must not add an interim timestamp pull, partial sync enum, or
route thinning that IP-4 would replace.

**Tests.** Restore failure still runs push; failed push remains queued; a request
during a pass schedules exactly one rerun; slow reconnect is observed; account
switch rejects stale completion; no recurring DNS socket is created.

**Documentation and git.** Reconcile IP-4’s current-state note, STATUS, and this
row. Same branch, one staged Flutter checkpoint. Proposed commit:
`fix(sync): preserve push progress when restore is unavailable`.

**Outcome, evidence, and git.** W2 isolates restore read, download, and
completion-flag failures from queued push while preserving owner/gate checks;
the read-only restore GET opts into existing idempotent authenticated replay.
The coordinator serializes the whole restore/workout/image flight into the
active pass plus at most one same-owner follow-up, and the workout repository
does the same for direct pass requests. Typed `NetworkException` stops the
remaining create/delete/image loop only after retryable queue state is
preserved; classified HTTP failures retain their existing behavior.
Connectivity now uses platform interface events with immediate race-safe replay
and monitoring-generation rejection, with no recurring timer or public-DNS
socket. `disconnected` recovery to either `slow` or `connected` requests one
sync, and lifecycle resume defers while an active or paused workout exists.

One focused command across seven suites passed 79 tests. Locked restore passed;
all 384 Flutter tests passed; analysis reported the same nine existing infos and
no warnings or errors; changed-file formatting and root `git diff --check`
passed. The counted analyzer comparison correctly rejected local Dart 3.12.2
against its CI-only Dart 3.12.1 stamp. W2 changes no backend/server HTTP API,
schema, or migration. It does not add cursor/revision/tombstone pull, remote
image restore, restore item isolation/projections, a rendered failed state or
manual retry, the full sync enum/backoff model, or device/staging/production
evidence. The runtime, tests, and owning documents are reconciled but unstaged;
there is no W2 commit.

### Step 4 — Correct backend sync-boundary defects without changing contracts

**Implementation.** Make list ordering deterministic; await signed image URL
generation before constructing responses; replace activity message-string 404
mapping with the existing typed error; add restore/list/delete integration
coverage and fix any verified fidelity/race defects without changing v1 response
shapes.

**Why now and dependencies.** These are small current-contract correctness fixes,
not the IP-4 redesign. They can follow the client regression net. Because merging
backend code deploys immediately, every change must remain compatible with the
released app.

**Tests.** Add native-ESM focused service/HTTP tests, then run all backend gates.

**Documentation and git.** Update the owning backend docs only if behavior or
rollout facts change, plus STATUS/runbook evidence. Keep the checkpoint on the
current branch; do not combine it with a migration. Proposed commit:
`fix(sync): make activity reads deterministic and typed`.

### Step 5 — Fix schema-free tracking truth and UI dead ends

**Implementation.** Introduce explicit permission/service/fix/stream states;
make the settings action open the correct settings surface; avoid an eager map
permission/fix request; remove committed debug text; acknowledge durable save;
add truthful recovery/discard copy and focused semantics, tap-target, contrast,
large-text, and reduced-motion coverage. Fix the map animation-listener and tile
provider/client lifetime before any follow-by-default change. Do not create a
large one-use strings abstraction.

**Why now and dependencies.** These defects misstate current recording status or
waste resources but do not require the checkpoint schema. They provide the state
vocabulary W5/W6 will consume. Stopping GPS on pause waits for the durable engine
because today’s synchronous pause/resume path has transition races.

**Tests.** Permission denial/denied-forever/stale grant/no fix/stream failure,
settings launch, save acknowledgement, discard confirmation, semantics and large
text, map init without location prompt, listener/provider disposal.

**Documentation and git.** Update IP-3.3/3.5, IP-5.6 only for verified map facts,
STATUS, and this row. Same branch; split into two staged commits if tracking-state
and map-lifetime diffs cease to be one reviewable unit. Proposed first commit:
`fix(tracking): report permission and recording state truthfully`.

### Step 6 — Measure and version route-quality policy

**Implementation.** Add deterministic fake-GPS/replay fixtures and an explicit
sampling/field-availability contract. Use MC-1.5 device runs to measure stationary
jitter, warm-up, accuracy, speed, altitude availability, and elevation noise.
Choose whether v1 remains or an IP-1 follow-up policy is warranted. Persist a
policy version and any contribution/anchor decision needed for deterministic
replay; never treat `altitude == 0.0` as missing without a real availability seam.

**Why now and dependencies.** The audits identify plausible quality risks but do
not establish production thresholds. The policy/schema contract must be decided
before IP-3 makes checkpoint aggregates durable. This step may remain pending on
manual evidence while unrelated Step 5 work proceeds.

**Tests.** Stationary, sparse, warm-up, gap, pause/resume, elevation, impossible
speed, missing-field, and replay-equivalence fixtures. Device results remain in a
privacy-safe external evidence location referenced by ACTION-REQUIRED.

**Documentation and git.** Reopen IP-1 only if evidence changes the shipped
policy; otherwise record that v1 remains. Coordinate the next SQLite version in
IP-3—no independent “v7” migration. Proposed commit after evidence:
`test(tracking): define replayable GPS quality policy`.

### Step 7 — Add the IP-3 durable schema and DAO

**Implementation.** After the IP-2.7 at-rest design gate, add one coordinated
SQLite migration for the active checkpoint, ordered accepted points/transitions,
stable completed point/event sequences, and policy version. Enforce one active
checkpoint per user, foreign keys, ownership, and migration invariants. Keep
`recoverable` derived from an orphan checkpoint, not stored as a second truth.

**Why now and dependencies.** Step 2 protects durable rows; Step 6 fixes the
replay/schema contract; IP-2.7 determines the protected storage topology. This is
the foundation for all later engine, FGS, and IP-4 work.

**Tests.** Every supported-version migration, duplicate/corrupt rows, crash at
migration boundaries, owner isolation, sequence uniqueness, FK checks, and
rollback preservation.

**Documentation and git.** Update IP-3.1, local DB version docs/tests, STATUS,
ACTION only for new manual migration evidence, and this row. Same branch, one
schema/DAO-only checkpoint. Proposed commit:
`feat(tracking): add owner-scoped active workout checkpoints`.

### Step 8 — Move tracking into one durable engine

**Implementation.** Extract one single-flight engine that commits Start before
GPS, persists transitions immediately, writes accepted points within the proven
loss objective, owns the timer/timeline/anchors, stops GPS during a durable Pause,
and resumes from a zero-distance anchor. UI observes lightweight snapshots and
does not reimplement arithmetic.

**Why now and dependencies.** The DAO and policy contract must exist first.
Stopping GPS on pause is safe only after transitions and resume failure are
durable and testable.

**Tests.** Failure injection at each transition/write, pause/resume races,
permission loss, stream failure auto-pause, fake-clock timing, bounded crash loss,
and unchanged IP-1 metrics.

**Documentation and git.** Update IP-3.1 evidence, STATUS, and this row. Same
branch, one engine checkpoint. Proposed commit:
`feat(tracking): persist active workout transitions and points`.

### Step 9 — Make finalization exact-once and recovery user-visible

**Implementation.** Atomically transform one checkpoint into one completed local
workout; make retry idempotent; preserve the checkpoint on failure. On startup,
offer Resume/Finish/Discard only for the current owner; exclude unknown downtime
from active duration; integrate D-011 logout and the ad gate without showing an
ad for pending/failed/headless completion.

**Why now and dependencies.** It requires the engine and retained-session model.
Foreground execution must not launch until process-death recovery is already
safe.

**Tests.** Kill/fail before and after each finalization boundary, starting and
finishing recovery states, A/B isolation, no duplicate completion, no silent
discard, and no ad on non-durable outcomes.

**Documentation and git.** Update IP-3.2/3.3, STATUS, ACTION for later device
recovery proof, and this row. Same branch, one staged checkpoint. Proposed commit:
`feat(tracking): finalize and recover workouts exactly once`.

### Step 10 — Implement Android foreground execution

**Implementation.** Use the approved app-owned minimal `location` foreground
service with one cached Flutter engine and one Dart workout engine. Declare only
required permissions/service type; start from user Start/Resume; use privacy-safe
notification state and idempotent actions; handle engine/activity/service races,
configuration changes, notification denial/dismissal, service loss, swipe-away,
and Task Manager Stop truthfully. Do not request background location or hold a
continuous wake lock by default. Require two-step Finish unless the maintainer
records a different product decision.

**Why now and dependencies.** Clean Android build proof, the durable engine,
exact-once finalize, and recovery must precede this service. Screen-off heartbeat
claims must be based on committed points/transitions and device evidence, not a
Dart timer assumed to wake a sleeping CPU.

**Tests/evidence.** Native channel/service tests, clean debug and ads-disabled
release builds, merged release-manifest inspection, then stock/Samsung/older-API
device runs under lock, battery saver, notification denial/dismissal, offline,
process death, and a multi-hour session. Manual results stay in ACTION-REQUIRED
and cannot be marked verified from the repository.

**Documentation and git.** Update IP-3.4, Android configuration, ACTION with
MC-3 rows when the testable behavior exists, STATUS, and this row. Same branch,
one staged checkpoint; no iOS scope. Proposed commit:
`feat(android): keep durable workouts active under screen off`.

### Step 11 — Bound long-session and map work

**Implementation.** Replace full-list state copies/resegmentation with lightweight
snapshots and an incremental/bounded display polyline while retaining every
accepted stored point. Gate clocks/offstage map work by lifecycle, reuse/dispose
map resources, move heavy image processing off the UI isolate, and add explicit
tile configuration, stable app identification, privacy-safe failure categories,
route-only degradation, and retry. Do not add offline bulk tile download.

**Why now and dependencies.** Performance work should measure the durable engine
that will ship. Do not increase sampling density until IP-4 removes the current
single-body/point ceiling.

**Tests/evidence.** Synthetic multi-hour memory/frame/DB measurements, provider
outage vs offline UI, no tile URL/route leakage, resource disposal, device battery
measurement, and current official provider-policy review.

**Documentation and git.** Update IP-3.5, IP-5.6, ACTION for release/device
checks, STATUS, and this row. Same branch, one or two focused staged checkpoints.
Proposed first commit: `perf(tracking): bound active route rendering work`.

### Step 12 — Add explicit local sync state once

**Implementation.** Implement the complete IP-4.1 enum, leases, retry metadata,
backoff, stale-attempt recovery, user-visible status, manual retry, and triggers.
Migrate every legacy boolean/remote-ID/delete-queue combination exactly as the
phase specifies. Do not land the audit’s temporary partial UI.

**Why now and dependencies.** Stable point/event identity comes from IP-3. The
schema must represent the final v2 lifecycle, not a disposable intermediate.

**Tests.** All legacy combinations, stale callbacks, account switch, ambiguous
acknowledgement, retry classification, and deterministic schedule.

**Documentation and git.** Update IP-4.1, STATUS, and this row. After the Flutter
reliability checkpoints land, decide whether the backend/mobile compatibility
series needs a fresh `sync-v2` branch from then-current `main`; do not create it
early. Proposed commit:
`feat(sync): persist explicit activity sync state`.

### Step 13 — Add bounded v2 upload compatibly

**Implementation.** Add additive backend draft/batch/revision/tombstone schema,
capability negotiation, canonical digest fixtures, and initiate/batch/status/
finalize endpoints. Retain bounded v1 and `(userId, clientSyncId)` semantics;
make v1 tombstone-aware. Mobile persists protocol/progress per attempt.

**Why now and dependencies.** IP-4.1 state and IP-3 sequence identity are
required. Backend deploys on merge before mobile reaches users, so server-first
additive rollout is mandatory.

**Tests/evidence.** Dropped responses, duplicate/reordered batches, missing
ranges, digest mismatch, token refresh, process death, tombstone collision, v1
compatibility, and maximum supported route.

**Documentation and git.** Use `sync-v2`; one schema/API checkpoint followed by
one mobile-enable checkpoint if needed. Record deploy order and rollback in
backend/IP-4 docs. Proposed first commit:
`feat(sync): add resumable versioned activity upload`.

### Step 14 — Add projections, indexes, cursor pull, and image restore

**Implementation.** Separate summaries/details/point pages; add measured indexes;
implement revision-bound cursor pull and explicit tombstones; transact per-user
cursor/application; preserve never-synced collisions; restore remote-only image
metadata and verified on-demand files.

**Why now and dependencies.** The v2 identity/revision contract must be live
before pull/merge. Do not infer deletion from absence or auto-delete an unproven
local collision.

**Tests/evidence.** Bounded list bytes/query count, paged reconstruction, fresh
device/two-device restore, replay before cursor commit, tombstone anti-resurrection,
A/B isolation, signed URL expiry, and representative query plans.

**Documentation and git.** Continue `sync-v2` with reviewable API/index and
mobile-restore checkpoints. Update IP-4.3–4.5, ACTION, STATUS, and this row.
Proposed first commit: `feat(sync): add cursor-based owner restore`.

### Step 15 — Make external and local file deletion durable

**Implementation.** Generalize the existing cleanup outbox with atomic jobs,
leases, bounded retry/dead-letter state, prefix validation, multi-replica safety,
and DB-first deletion. Add the owner-scoped mobile file-cleanup outbox and remove
the in-process timer only after the worker owns/drains the backlog.

**Why now and dependencies.** It depends on the final activity/image/tombstone
model. Deletion must be idempotent across worker/process death and must never use
S3 success as the database transaction prerequisite.

**Tests/evidence.** Transaction rollback, storage failure, worker death after
delete, lease contention/reclaim, invalid prefix, mobile cascade/process death,
and replica deployment checks.

**Documentation and git.** Continue `sync-v2`; update IP-4.6, backend deployment
runbook, ACTION, STATUS, and this row. Proposed commit:
`feat(storage): make activity cleanup durable and leased`.

### Step 16 — Reconcile release evidence and close only proven gates

**Implementation.** Run the full repository, hosted, staging, two-device,
Android/OEM, long-route, performance, privacy, provider, Play Console, rollback,
and production checks owned by IP-0/IP-5/ACTION. Recheck public legal wording as
verified facts for maintainer review; do not edit legal text autonomously.

**Why now and dependencies.** Release claims follow implementation. IP-0
operational containment and every applicable manual check remain hard gates.

**Documentation and git.** After each implementation checkpoint is committed,
use a separate documentation checkpoint to disposition the affected findings.
Retire a report only when every finding is implemented, explicitly deferred, or
superseded with linked evidence and no unique test/rollback/manual guidance would
be lost. Extract the lasting product behavior into maintained tracking and sync
architecture documents, shrink delivered phase instructions to durable
architecture/rollback/evidence, remove this temporary runbook only when no active
step depends on it, and keep STATUS/ACTION exact.

## Decision and evidence gates

| Needed before | Decision/evidence | Recommended default |
| --- | --- | --- |
| Step 6 behavior change | MC-1.5 device calibration and replay equivalence | Keep policy v1 until evidence justifies a versioned change |
| Step 7 rollout | IP-2.7 threat model, encrypted-store/library/performance/backup/key-loss approval | Per-user protected store/key; never delete plaintext source until verified migration succeeds |
| Step 10 implementation | Android runtime architecture | App-owned minimal location FGS, one cached engine, no background-location permission, no boot auto-start, no continuous wake lock |
| Step 10 notification UX | Finish confirmation and notification dismissal semantics | Two-step Finish; in-app controls remain authoritative; non-sensitive state only |
| Step 11 map release | Provider, app identification, cache retention, degraded-mode UX, current policy check | Configurable provider, stable app UA/contact, bounded standard cache, route-only fallback, no bulk download |
| Step 13+ rollout | Mobile compatibility window and v1 removal condition | Additive server-first v2; keep v1 until supported-client evidence allows removal |
| Step 14 conflict handling | Remote tombstone vs local collision | Auto-delete only proven previously-synced identity; quarantine never-synced collision |

Thresholds, wake locks, SQLite journal mode, tile cache size/TTL, sampling density,
and exact route-quality constants are measurement decisions, not defaults copied
from an audit.

## Audit register and retirement gates

[AUDIT-REGISTER.md](./AUDIT-REGISTER.md) inventories the phase plans, all eight
August reports, the original-audit provenance, maintained architecture, deferred
integration plans, finding-to-checkpoint map, and retirement gates. It is the
only audit register; do not recreate old parallel trackers.

The intended maintained documents after implementation are:

- `docs/_engineering/tracking/tracking-runtime.md` — how recording, checkpoints,
  recovery, foreground execution, signal truth, map degradation, and battery
  behavior work in the shipped app, including what changed from the old runtime;
- `docs/_engineering/sync/sync-architecture.md` — the local-first sync state
  machine, push/pull, identity, tombstone/conflict, image restore, retry, cleanup,
  and backward-compatibility contracts.

Create those from implemented, tested behavior—not from proposals alone.

## Per-checkpoint verification and handoff

For every code checkpoint:

1. Run focused tests first, then the full applicable gates from README/AGENTS.
2. Format only changed files and run `git diff --check`.
3. Reconcile the owning phase, STATUS, ACTION (manual rows only), and this row.
4. Stage only the complete checkpoint. Do not commit or push.
5. Report changed files, branch, exact staged state, tests/gates run, remaining
   manual evidence, the next step, and a proposed commit message.
6. After the maintainer commits an implementation checkpoint, make the next
   documentation checkpoint update the affected audit dispositions. Deletion is
   allowed only when that report's retirement gate above is satisfied.

Backend gates are required whenever backend code/config/schema changes. Flutter
gates are required whenever Flutter/Dart/Android code/config changes. A local
green run never verifies hosted PostgreSQL, production topology, Play Console,
physical-device behavior, provider policy, or any ACTION-REQUIRED row.
