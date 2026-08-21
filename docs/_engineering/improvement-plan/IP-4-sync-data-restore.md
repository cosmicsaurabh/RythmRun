---
published: false
---

# IP-4: Sync, API/data contracts, and cloud restore

| Field | Value |
| --- | --- |
| Status | Planned |
| Priority | P1/P2 |
| Target | 2–4 weeks with compatibility and load evidence |
| Owner | Unassigned |
| Last updated | 2026-07-17 |
| Depends on | IP-2 refresh/privacy; IP-3 durable local workout identity and finalization |
| Exit condition | Resumable long-workout sync, visible states, query/index, restore, tombstone, and durable-cleanup gates pass |

## Outcome

After this phase, a completed workout syncs through bounded, resumable, idempotent requests; list APIs do not return full routes; local UI shows queued/retrying/failed/synced state; a fresh device restores the user's history without duplicates; deletes do not resurrect; and external object cleanup survives process restarts and multiple replicas.

## Audit evidence

The 2026-08-17 [Push/Pull Sync Reliability Audit](../sync/sync-reliability-audit.md)
re-traced push, pull, and multi-device behaviour against the current code
(`d0e5b92`). It carries the gap list `SYNC-01`…`SYNC-18` and the deferred-decision
log `D-01`…`D-14`; the items below are the original 2026-07-10 findings. Two
corrections since then: a bootstrap-only pull now exists (`IP-2.7`, one-shot per
login, no cursor, no tombstones), and session teardown deletes unsynced local rows
(`SYNC-01`, P0). The audit does not change this phase's target design; `SYNC-02`
is a minimal delta pull that IP-4.5 later completes.

- Flutter sends all locations/status changes in one JSON body.
- Express previously used its default 100 KB body limit; IP-1 provides only a bounded interim increase.
- Backend activity list and detail share `activityInclude`, eagerly loading all route points.
- Major PostgreSQL foreign-key/query indexes are absent.
- Flutter `ActivityRemoteDataSource` implemented create/delete only; no pull/merge path existed. IP-2.7 later added `fetchActivities` and a one-shot bootstrap (see the audit note above); there is still no delta pull, cursor, or tombstone.
- Local sync is a `synced` boolean with little actionable user feedback.
- Activity PATCH can destroy child history unless presence-aware behavior from IP-1 is retained.
- Backend activity deletion calls S3 before deleting the database row, so failures can leave cross-system inconsistency.
- Image cleanup is an in-process timer handling 25 rows per web process and is not safely coordinated across replicas.
- At audit time several backend modules created their own Prisma clients. IP-1.6 now centralizes repository ownership on one adapter-backed client/pool; real deployed replica/pool behavior remains unverified under MC-1.12/MC-1.13.
- Connectivity state may not emit an initial connected value and uses a repeated TCP probe to a public DNS address.

## Scope

- Explicit local/remote activity sync state and retry metadata.
- A versioned, bounded, resumable route upload protocol.
- Lightweight activity summaries and paged detail/route reads.
- Server revisions, tombstones, cursor-based pull, and deterministic conflict policy.
- Remote image metadata restore and on-demand local caching rules.
- PostgreSQL indexes and measured query plans.
- Preserve the IP-1.6 shared Prisma lifetime and prove deployed pool/replica behavior; do not reintroduce per-module clients.
- Durable, leased object-deletion/outbox worker.
- Initial connectivity emission and sync triggering without public-DNS polling.
- Contract, migration, failure, and representative load tests.

## Non-goals

- Microservices, Kafka, Redis, Kubernetes, or generic event streaming.
- Public social route feeds.
- Server-side route simplification for public sharing.
- Caching before query/payload measurements prove a need.
- Database partitioning or 64-bit location-ID migration unless measured row growth now justifies it; record the projection for a later migration.

## Sync invariants

1. `(userId, clientSyncId)` remains the workout idempotency identity.
2. Every point has a stable sequence within a workout.
3. Replaying the same request is safe; reusing an identity with different data is a conflict, not silent overwrite.
4. A workout becomes visible as complete only after finalization validates its declared contents.
5. Absence from a paginated response never means deletion. Only an explicit tombstone deletes.
6. A remote tombstone prevents an old offline client from recreating a deleted workout under the same `clientSyncId`.
7. Exact route data remains owner-only under IP-2 privacy rules.
8. Local queued work is never discarded merely because a pull occurred.

## Local sync state model

Replace the workout `synced` boolean with an enum/state value and metadata:

- `queued`: durable local completion has not fully uploaded;
- `syncing`: a worker owns the current attempt;
- `retrying`: retryable failure with `nextRetryAt`;
- `failed`: permanent/action-required failure with a safe error code;
- `synced`: server ID/version and completed finalization are recorded;
- `deletePending`: local delete is hidden and waiting for remote tombstone;
- `deleted`: terminal local cleanup/tombstone acknowledgement where a row is retained for queue bookkeeping.

Store retry count, last attempt, next retry, last safe error code, remote activity ID, remote revision, last synced time, protocol version, and a lease/attempt token as needed. Never persist raw response bodies, tokens, signed URLs beyond their required cache metadata, or sensitive server stack errors.

## Target upload protocol

Implement `/api/v2/activities` while retaining IP-1's bounded v1 endpoint only for a defined supported-client window.

Use separate draft tables; do not make required `Activity` completion fields nullable:

- `ActivityUploadSession`: session ID, user ID, `clientSyncId`, protocol version, validated metadata/digest, expected counts, route digest, state, expiry, finalized activity ID, and timestamps;
- `ActivityUploadPoint`: session ID, stable sequence, validated point fields, and uniqueness on `(sessionId, sequence)`;
- `ActivityUploadStatusEvent`: session ID, stable sequence, validated event fields, and uniqueness on `(sessionId, sequence)`;
- optional accepted batch receipts keyed by `(sessionId, batchIndex)` with byte digest/range/count.

Finalization validates the draft and atomically creates the required `Activity`, `Location`, and `StatusChange` rows, then marks the upload session finalized. Normal activity queries never include draft tables.

### 1. Initiate

`POST /api/v2/activities/sync-sessions`

- Input: `clientSyncId`, metric/schema version, metadata, expected point/status counts, and optional whole-route digest.
- Server: enforce owner/tombstone/private defaults, create or return the idempotent draft, and issue a sync-session/activity ID plus next expected range.
- A repeated identical initiate returns current progress. Different metadata for a finalized identity returns conflict.

### 2. Upload point batches

`PUT /api/v2/activities/{id}/point-batches/{batchIndex}`

- Initial contract: at most 500 points and 256 KiB encoded body per batch; changing either is a versioned capability value backed by load/fixture evidence.
- Each point carries an integer sequence and validated domain fields.
- Request includes first/last sequence, count, protocol version, and batch digest.
- Unique `(activityId, sequence)` and/or `(activityId, batchIndex)` makes exact replay safe.
- If an existing sequence/batch has a different digest, return conflict and do not partially overwrite.

Status events are small but still bounded. Upload them through an idempotent batch or include them in finalization with sequences and a digest.

Digest contract: SHA-256 of the exact canonical UTF-8 JSON bytes. The v2 schema fixes object field order, uses no insignificant whitespace, UTC ISO-8601 timestamps with exactly millisecond precision, base-10 integers, and a documented shortest round-trip representation for finite doubles. Check in Dart/Node golden byte-and-digest fixtures; neither side may hash a reserialized arbitrary map.

### 3. Inspect/resume

`GET /api/v2/activities/{id}/sync-status`

- Return server progress, missing sequence ranges/batches, revision, and safe state.
- Ownership is required; never return another user's upload progress or route metadata.

### 4. Finalize

`POST /api/v2/activities/{id}/finalize`

- Verify metadata, expected counts, contiguous/valid sequence rules, status transitions, and digests.
- Mark complete and increment server revision atomically.
- Repeating finalize returns the same completed activity/version.
- Drafts are excluded from normal lists and are expired by a durable cleanup policy after a documented window.

## Pull/restore contract

- Cursor endpoint returns owner-only activity summaries changed after a server cursor, ordered by a stable `(updatedAt, id)` tuple.
- Each summary includes `clientSyncId`, server ID/revision, private visibility, core metrics/version, image summary, and deletion/tombstone state—but no route points.
- Detail and point pages are fetched only for missing/changed records.
- Point pagination uses stable sequence/cursor, not offset.
- The next cursor advances only after the page is durably applied locally.
- Tombstones retain at least `(userId, clientSyncId, deletedAt, revision)` for the life of the account unless a proven retention policy can prevent resurrection another way.

## Conflict policy

| Local state | Remote state | Action |
| --- | --- | --- |
| queued/retrying never-synced workout | absent | Push using `clientSyncId` |
| queued/retrying new workout | same `clientSyncId` complete | Verify identity/digest, then mark synced or surface conflict |
| synced same revision | newer complete revision | Pull safe editable metadata/detail and update |
| local unsynced journal edit | newer remote journal edit | Preserve both versions and require a narrow user choice; never overwrite route/metrics silently |
| local record proves prior remote ID/revision | explicit newer matching tombstone | Remote delete wins; cancel uploads under that identity and remove/hide locally |
| never-synced local record | tombstone collision on `clientSyncId` | Quarantine conflict and preserve local data; do not auto-delete or recreate remotely |
| local deletePending | remote complete | Send idempotent delete and wait for tombstone acknowledgement |
| remote-only complete | no local row | Import by `(userId, clientSyncId)` |
| item absent from a page | any local state | No action |

## Ordered work packages

### IP-4.1 — Add explicit local sync state and visible retry

**Primary files**

- `rythmrun_frontend_flutter/lib/core/services/local_db_service.dart` or extracted workout/sync DAO
- Workout entity/repository/local/remote data sources
- `rythmrun_frontend_flutter/lib/core/services/sync_coordinator.dart`
- History/detail state, providers, widgets/screens
- New migration and repository/provider tests

**Implementation**

1. Define and test every legacy combination before migration:
   - `deleted_locally=0, synced=0, remote_activity_id=NULL` → `queued`;
   - `deleted_locally=0, synced=0, remote_activity_id!=NULL` → `retrying/needsReconcile` and query server identity before upload;
   - `deleted_locally=0, synced=1, remote_activity_id!=NULL` → `synced`;
   - `deleted_locally=0, synced=1, remote_activity_id=NULL` → `needsReconcile` with `clientSyncId`, never blind duplicate creation;
   - `deleted_locally=1` plus a remote ID/queue → `deletePending`, reconstructing a missing queue row transactionally;
   - `deleted_locally=1` without any remote identity → local terminal cleanup.
   Preserve and reconcile image/delete-queue state, and quarantine impossible duplicates rather than guessing.
2. Use a lease/attempt ID so a stale async completion cannot mark a newer attempt or another account's row synced.
3. Classify errors:
   - network/timeouts/5xx/429 → retrying with bounded exponential backoff and jitter;
   - auth → pause and invoke IP-2 single-flight refresh once;
   - validation/413/conflict → failed/action required, no infinite retry;
   - cancellation/account change → return to queued safely.
4. Reset abandoned `syncing` rows after a lease timeout on startup.
5. Display a compact status in history/detail, last successful backup/sync time, safe error explanation, and a manual Retry for retryable or corrected failed items.
6. Sync triggers on completion, authenticated startup, reconnect, app resume, and manual action, while the coordinator serializes/leases work.
7. Connectivity service emits its current state immediately and relies on platform connectivity plus actual request outcomes; remove the recurring `8.8.8.8:53` classification probe.

**Tests**

- Every enumerated legacy boolean/remote-ID/delete-queue combination migrates correctly from fixtures.
- Crash during syncing resets to retryable/queued after lease expiry.
- Retry schedule is bounded and deterministic under a fake clock/random source.
- Permanent validation errors stop retrying and are visible.
- Manual retry does not duplicate an already completed remote activity.
- Account change prevents stale callback writes.

### IP-4.2 — Implement resumable versioned activity upload

**Primary backend files**

- `RythmRun_backend_nodejs/prisma/schema.prisma` and new migrations
- New v2 sync DTO/controller/service/routes
- `RythmRun_backend_nodejs/src/app.ts` route mounting
- Shared Prisma container and tests

**Primary Flutter files**

- Activity sync model/remote data source
- Workout repository sync loop/coordinator
- Durable batch progress fields/DAO

**Implementation**

1. Add server draft/sync-session state, point sequence/digest constraints, server revision, and tombstone protection.
2. Implement initiate, batch, status/resume, and finalize exactly as the target contract.
3. Validate every nested value and cap batch count/size independent of Express body limit.
4. Persist local next batch/progress only after the server acknowledges it; on ambiguity, query sync status rather than assume failure/success.
5. Retain v1 full upload temporarily. Record minimum mobile version and removal date/condition; v1 and v2 use the same `clientSyncId` uniqueness.
6. Make both v1 create and v2 initiate check owner tombstones throughout the compatibility window. V1 returns a stable deleted/conflict code and cannot resurrect a matching tombstone.
7. Add `GET /api/capabilities` returning a non-sensitive versioned document with supported activity sync versions, exact batch/body/count limits, and minimum client contract. Cache per API base URL for at most one hour; absence/404 means bounded v1 only during its declared window, while network/security/validation errors never trigger silent downgrade.
8. Make mobile choose v2 from that capability document and persist the selected protocol per attempt so a retry cannot switch formats mid-upload.
9. Check in the source-of-truth v2 JSON/OpenAPI schema plus Dart/Node golden canonical-byte/digest fixtures. Backend and Flutter contract tests consume them.

**Failure tests**

- Drop response after server commits a batch; retry is idempotent.
- Duplicate/reordered batches.
- Missing range at finalize.
- Same batch identity with different content.
- Process death between every mobile progress update.
- Token expiry mid-upload and one successful refresh/resume.
- Tombstone exists before initiate/finalize.
- A legacy v1 create matching a tombstone is rejected without recreation.
- Capability cache, 404 fallback window, v2 selection, and no-downgrade-on-error behavior are deterministic.
- Dart and Node produce identical canonical bytes/digests for edge-case finite numeric/timestamp fixtures.
- Multi-hour/max-supported route completes within bounded request size/memory.

**Acceptance**

- No single request grows with the complete route length.

### IP-4.3 — Separate summaries, details, and point pages

**Primary files**

- `RythmRun_backend_nodejs/src/services/activity.service.ts`
- Activity DTO/controller/routes
- Flutter local DB/workout DAO paths that currently load points/status per workout
- Flutter remote models/data sources for restore
- Contract and query-count tests

**Implementation**

1. Replace shared `activityInclude` with explicit projections:
   - list/restore summary: no locations/status arrays, limited image/count metadata;
   - owner detail: activity metadata and bounded status events;
   - route endpoint: owner-only point pages ordered by sequence;
   - image endpoint: existing signed metadata rules.
2. Avoid exact total counts in hot paths if measurements show they dominate; return a next cursor/hasMore for restore.
3. Keep existing v1 response compatible only through the declared support window.
4. Add response-size/query-count assertions so an accidental include of locations in list tests fails.
5. Remove/deprecate the local bulk `getWorkoutsFromLocalDatabase` 2N+1 path from supported list flows. Use summary queries without children and one explicit detail query, or batch child reads when a bulk export genuinely needs them.
6. Finalized route points/status are immutable in v2. Every detail/point cursor is bound to an activity revision; a revision mismatch restarts that detail download rather than mixing pages from different versions.

**Tests/acceptance**

- Listing 50 long activities returns no location arrays and stays below 256 KiB in the v2 contract fixture.
- Detail/route pages reconstruct the same ordered route as the original.
- Another user cannot page route points.
- Query count does not grow with the number of returned summaries through N+1 behavior.
- Local history list query count is constant/bounded and loads no route children; a single detail load uses the expected bounded child queries.

### IP-4.4 — Add PostgreSQL indexes and measured capacity evidence

**Primary files**

- `RythmRun_backend_nodejs/prisma/schema.prisma`
- Forward Prisma migration(s)
- `RythmRun_backend_nodejs/perf/k6/` guarded k6 scenarios and synthetic seed/cleanup tooling

**Indexes to start with**

- `Activity(userId, startTime DESC)` and revision/change cursor fields;
- `Location(activityId, sequence/timestamp)` plus uniqueness required by batching;
- `StatusChange(activityId, timestamp/sequence)`;
- `Comment(activityId, createdAt)` if comments remain mounted later;
- `Friend` indexes for each direction/status only if friend paths remain supported;
- cleanup job `(status, nextAttemptAt, leaseUntil)`;
- tombstone `(userId, updatedAt/id)` and unique `(userId, clientSyncId)`.

**Implementation**

1. Seed representative distributions including long point sets, not only empty tables.
2. Capture `EXPLAIN (ANALYZE, BUFFERS)` in staging/test for summary list, owner detail, route page, sync cursor, delete cascade, and cleanup lease queries.
3. Use non-blocking/concurrent index deployment where supported by the production migration procedure; Prisma-generated SQL may need a reviewed operational migration split.
4. Measure connection count after removing extra Prisma clients. Configure one pool per process within database limits.
5. Add k6 scenarios for authenticated summary paging, detail/route paging, upload batch/finalize, refresh pressure, and cleanup-safe delete using synthetic users/routes. The script refuses non-local/staging hosts unless `ALLOW_NON_PRODUCTION_LOAD_TEST=1` and an explicit host allowlist match; it always rejects the production hostname.
6. Seed deterministic small/long routes and run modeled 100- and 1,000-user stages; label them models/tests, not claims of production capacity.
7. Before implementation acceptance, commit `perf/performance-budget.json` with the environment and exact budgets. Initial release candidates target summary p95 ≤500 ms, upload-batch p95 ≤750 ms, HTTP error rate <1% excluding deliberate 4xx, and zero duplicate/finalization invariant failures; owner must revise budgets from measured staging capacity before production sign-off.
8. Record p50/p95/p99 latency, error rate, response bytes, DB CPU/connections, and rows scanned. Fix query/payload issues before considering cache or service decomposition.

**Acceptance**

- Query plans use intended indexes on representative data and load tests meet explicitly recorded budgets.

### IP-4.5 — Implement idempotent pull/restore and image restoration

**Primary files**

- New backend sync cursor/tombstone endpoints/services
- Flutter activity remote data source and sync coordinator
- Local workout/image schema and DAO
- History refresh/status UI

**Implementation**

1. Add cursor-based owner summary pull with revisions and explicit tombstones.
2. Store the cursor per authenticated user only after applying the page transactionally.
3. Upsert local workouts by `(userId, clientSyncId)`, never by server ID alone.
4. Fetch changed details/point pages and commit a complete remote workout atomically so history never sees a half-restored route.
5. Apply the conflict table above. Preserve local queued changes and surface true editable-field conflicts.
6. Apply tombstones transactionally only to local records whose remote ID/revision proves prior synchronization. A never-synced collision is quarantined and preserved for resolution; never infer deletion from absence.
7. Restore image metadata and expiring signed URLs. Update the local image schema to represent a remote-only image without inventing a nonexistent local path.
8. Define image cache behavior:
   - thumbnail/on-demand download after restore;
   - durable file write before recording a local path;
   - checksum/size verification;
   - bounded cache/storage handling;
   - offline UI distinguishes "not downloaded" from "failed/missing".
9. Re-running restore from cursor zero is idempotent and must not duplicate rows/files.

**Tests**

- Fresh device restores summaries/details/routes once.
- Kill after page download but before cursor commit safely replays.
- Remote tombstone prevents an old offline create from resurrecting; never-synced colliding local data is quarantined rather than erased.
- Local queued workout with matching remote identity reconciles by digest/version.
- Remote-only image displays online and caches safely on demand.
- Signed URL expiry refreshes metadata without duplicating images.
- Account A/B cursors and rows remain isolated.

### IP-4.6 — Make external deletion durable and replica-safe

**Primary files**

- Prisma schema/migration for object cleanup jobs/outbox
- Activity and activity-image delete services
- New worker entry point/service
- `RythmRun_backend_nodejs/src/app.ts` timer removal
- Mobile SQLite local-file cleanup outbox plus the activity-image file service
- Worker tests and deployment process documentation

**Implementation**

1. Generalize the minimal independent cleanup outbox/runner introduced for account deletion in IP-2.4. In the database transaction that deletes/marks an activity, image, avatar, or account, create an object-deletion job containing the validated S3 key and idempotency identity before ownership rows disappear.
2. Commit database state first. Never make S3 deletion a prerequisite for the DB transaction.
3. Worker leases ready jobs atomically using `leaseOwner/leaseUntil`, processes bounded batches, and records attempts/next retry/safe error category.
4. Multiple workers cannot own the same live lease. Expired leases are reclaimable after process death.
5. Treat "object not found" as successful deletion. Repeated deletion is idempotent.
6. Validate every job key against an approved prefix even though it originated server-side; never allow a generic arbitrary-key cleanup record.
7. Add dead-letter/alert state after a bounded retry policy, with manual safe retry.
8. Add leases/multi-replica coordination to the existing durable runner, then remove the per-web-process 15-minute image timer only after the worker is deployed and backlog is drained/owned.
9. Use the same injected Prisma client lifecycle in web code; worker may own one separately managed process client.
10. On mobile, persist validated app-private original/thumbnail paths to an owner-scoped local cleanup outbox in the same SQLite transaction that deletes an image row or cascades a workout. Delete only paths revalidated beneath the application image root, treat missing files as success, and acknowledge the job after deletion so process death cannot permanently strand files after their metadata rows disappear.

**Tests**

- DB transaction rollback creates neither deletion nor job.
- DB commit + S3 failure leaves retryable job.
- Worker death after S3 success but before DB acknowledgement retries safely.
- Two workers cannot process one active lease concurrently.
- Invalid prefix job is quarantined, not executed.
- Workout/image-row cascade plus process death leaves a replayable local file-cleanup job; another user's paths and any path outside the application image root are never deleted.

## Compatibility and rollout order

1. Add server schema/indexes/draft state without changing v1 behavior.
2. Deploy v2 endpoints and contract tests; keep them unused externally.
3. Add local sync-state migration and UI.
4. Release mobile v2 uploader behind capability/feature control.
5. Exercise partial uploads and resume in staging; gradually enable in production.
6. Deploy summary/detail/route paging and new restore endpoints.
7. Release pull/restore to internal users, then staged cohorts.
8. Deploy leased cleanup worker, verify leases/backlog, then remove the in-process timer.
9. Retire v1 only after the supported-client window and metrics show no active dependency.

## Rollback plan

- V2 drafts/batches remain in the database during mobile rollback and expire through the durable job; never expose drafts as complete.
- Mobile can fall back to bounded v1 only while the backend explicitly supports it and the route fits IP-1 limits.
- Restore can be disabled without deleting its per-user cursor or imported data.
- Summary/detail APIs retain versioned compatibility; do not re-add routes to list responses to fix an old client—use the declared v1 route/window.
- Cleanup worker rollback keeps jobs queued; do not restore S3-before-DB deletion.
- Index rollback occurs only after query-plan review; unused safe indexes may remain during incident recovery.

## Verification matrix

| Scenario | Expected result | Evidence |
| --- | --- | --- |
| Multi-hour route upload | Bounded batches finalize once | Contract/E2E test |
| Dropped batch response | Status query/retry, no duplicate | Failure-injection test |
| Token expires mid-sync | One refresh, resume from progress | Flutter/backend E2E |
| Activity list | No points/status arrays; bounded bytes | Contract test |
| Fresh-device restore | Same activities/routes, no duplicates | Device/E2E test |
| Remote delete + old offline client | Tombstone blocks resurrection | Conflict test |
| Remote-only image | Valid online display and optional verified cache | Repository/widget test |
| Process dies during S3 cleanup | Lease retry completes safely | Worker integration test |
| Two cleanup replicas | One job owner at a time | Concurrency test |
| 100/1,000 modeled users | Recorded latency/errors/DB metrics | Load report |

## Exit gate

- [ ] Local workout sync states and retry metadata migrate and display correctly.
- [ ] Retry classification, lease recovery, manual retry, and account-switch safety pass.
- [ ] V2 initiate/batch/resume/finalize is bounded, idempotent, and versioned.
- [ ] Multi-hour and failure-injection upload suites pass.
- [ ] List summaries contain no route arrays; detail/route paging reconstructs correctly.
- [ ] PostgreSQL indexes are deployed with representative query-plan evidence.
- [ ] One intended Prisma pool exists per web process.
- [ ] Fresh-device restore is cursor-based, transactional, owner-scoped, and idempotent.
- [ ] Tombstones prevent deletion resurrection.
- [ ] Remote image metadata/cache behavior is explicit and tested.
- [ ] Object deletion is DB-first, durable, leased, idempotent, and replica-safe.
- [ ] Initial connectivity state and actual request outcomes drive sync; public-DNS polling is removed.
- [ ] Compatibility/removal conditions for v1 are recorded.
- [ ] Representative 100/1,000-user load results are recorded without overstating capacity.

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| — | — | No implementation evidence yet | Not started | Planning document only |
| 2026-08-17 | Audit (pre-4.1) | [Sync reliability audit](../sync/sync-reliability-audit.md), static trace of `d0e5b92`; no device runs, no suites executed | NOT READY: one P0 (unsynced work deleted at session exit), P1 multi-device propagation absent | Gap list `SYNC-01`…`SYNC-18` is the ticket source; deferred decisions `D-01`…`D-14` |
