---
published: false
---

# IP-5: Release readiness and focused retention

| Field | Value |
| --- | --- |
| Status | Planned |
| Priority | P2 after all P0/P1 gates |
| Target | 3–6 weeks for IP-5.1–IP-5.6 release controls; IP-5.7 estimated separately after the gate |
| Owner | Unassigned |
| Last updated | 2026-07-10 |
| Depends on | Verified exit gates for IP-0 through IP-4 |
| Exit condition | Staging, operations, CI/E2E, platform, documentation, and focused-product release gates pass |

## Outcome

After the IP-5 release gate, RythmRun has a repeatable staging-to-production release process, dependency-aware readiness and graceful shutdown, privacy-safe diagnostics, mandatory risk-based CI, an explicit Android/iOS scope, and accurate product/legal documentation. IP-5.7 is a separately estimated post-gate product epic for the private workout journal; it does not delay release hardening.

## Audit evidence

- `/health` reports process availability only and does not verify PostgreSQL or storage dependencies.
- A read-only probe showed roughly 16–20 seconds of likely cold-start latency.
- `app.ts` constructs middleware/routes, starts an in-process job, and calls `listen` in one module, complicating integration tests and graceful shutdown.
- There is no tracked CI workflow before IP-1, no staging configuration, no IaC, and no production observability contract.
- Flutter analysis reported 159 findings (6 warnings, 153 informational), including deprecated APIs and unguarded prints.
- Root/backend/configuration documentation contains stale features, versions, routes, scripts, and secret names.
- Privacy/delete documentation claims behavior not fully present in the app.
- Android embeds a production AdMob application ID; ad placement can appear before the user receives value.
- iOS lacks complete photo, AdMob, and proven background configuration.
- The strongest real product is the track → finish → history/map → photos loop; goals/trends/journal completion are more aligned than social or AI work.

## Scope

- App/server lifecycle, liveness/readiness, shutdown, and deployment runbooks.
- Staging with isolated data/secrets and production-like migrations.
- Structured redacted logging, crash/error reporting, metrics, alerting, and initial SLOs.
- Mandatory CI expansion: contracts, migrations, security regressions, lifecycle, E2E, builds, and dependency review.
- Analyzer/deprecation/debug-log cleanup to a release gate.
- Explicit platform readiness and ads/consent configuration.
- Verified README/setup/architecture/privacy/account/recovery/operations documentation.
- A separate implementable specification for post-workout summary/journal, trends, and personal bests; delivery begins only after the release gate is stable.

## Non-goals

- Social feed, likes/comments/friends, challenges, or public exact routes.
- AI summaries.
- Cadence/audio coaching, wearables, Health Connect, or HealthKit.
- Redis, Kafka, Kubernetes, microservices, or generalized event infrastructure.
- Scaling work unsupported by IP-4 measurements.

## Release principles

1. No open P0/P1 security, metric, cross-account, data-loss, refresh, or privacy defect is waived for a feature deadline.
2. Staging is isolated from production credentials/data but runs the same migrations and application artifacts.
3. A release artifact is promoted; production is not rebuilt from a different source/configuration.
4. Liveness answers "is the process running?"; readiness answers "should it receive traffic?" and is bounded.
5. Diagnostics collect the minimum useful data and exclude precise routes, tokens, signed URLs, passwords, private filenames, and request bodies.
6. Monetization follows value and consent.
7. Documentation describes verified shipped behavior, not the roadmap.

## Ordered work packages

### IP-5.1 — Build testable server lifecycle and dependency-aware health

**Primary files**

- `RythmRun_backend_nodejs/src/app.ts`
- New `src/server.ts`, app factory/bootstrap/lifecycle modules
- `RythmRun_backend_nodejs/package.json` and deployment start command
- Environment/container/Prisma/S3/worker services
- Health/readiness tests and deployment documentation

**Implementation**

1. Extend the app/bootstrap seam introduced in IP-0.5 into a complete Express app factory that configures middleware/routes but does not listen, start timers, or create extra clients at import time; do not create a second competing bootstrap.
2. Make `server.ts` the only production entry point:
   - load/validate environment first;
   - create shared dependencies;
   - start the HTTP server;
   - start/attach the IP-4 durable worker according to deployment topology.
3. Update `package.json` main/start/dev/build behavior and the hosting start command so the compiled `server` entry is what runs. Prove a clean build artifact contains and starts the intended file.
4. Add endpoints:
   - liveness: fast process/event-loop response with no sensitive configuration;
   - readiness: bounded PostgreSQL query and required dependency state; S3/CDN checks are cached/bounded or represented through recent worker/upload health so every probe does not create external cost;
   - never expose hostnames, credentials, stack traces, table counts, or internal network details.
5. On `SIGTERM`/`SIGINT`:
   - mark not ready;
   - stop accepting new connections;
   - drain in-flight requests for a bounded grace period;
   - release/stop worker leases safely;
   - disconnect Prisma and other clients;
   - force exit only after the documented deadline.
6. Measure cold and warm startup. Remove unnecessary startup work and configure hosting health/start timeouts based on evidence, not by masking a failed dependency.
7. Document migration-before-traffic ordering and one-running-migration ownership.

**Tests**

- App imports without opening a socket/timer.
- Liveness remains fast when DB is down; readiness fails safely and recovers.
- Readiness dependency checks time out within their budget.
- `SIGTERM` stops new requests, finishes an in-flight safe request, releases resources, and exits.
- A worker lease is recoverable after forced termination.

**Acceptance**

- Deployment orchestration can distinguish a live process from one ready for user traffic.

### IP-5.2 — Add privacy-safe observability and operational objectives

**Primary areas**

- Backend logging/error middleware and request context
- Flutter centralized logging/crash boundary
- Monitoring vendor/configuration selected by the owner
- New runbooks under this engineering documentation area, without incident secrets

**Implementation**

1. Create a data classification/redaction policy before enabling a vendor. Explicitly ban:
   - access/refresh/reset tokens, authorization headers, passwords;
   - raw request/response bodies on auth/profile/activity endpoints;
   - precise latitude/longitude, complete route arrays, and home/start/end points;
   - presigned/signed URLs and private S3/local paths;
   - raw incident evidence.
2. Backend structured events include timestamp, level, environment, version, request ID, route template, safe status/error code, duration, and pseudonymous/bounded correlation only when approved.
3. Flutter logs use a single release-aware interface. Remove `print`, exact coordinate logs, debug configuration dumps, and test-retrieval logging from production paths.
4. Add crash/error reporting with source maps/symbols and redacted breadcrumbs. Confirm deletion/retention controls before shipping.
5. Measure at minimum:
   - request latency/error rate by route template;
   - auth refresh success/failure/reuse categories;
   - workout checkpoint creation/recovery/finalization failure;
   - sync queued/retrying/failed age and `413`/validation errors;
   - restore success/duplicate/conflict counts;
   - cleanup queue depth/age/dead-letter count;
   - DB connections/query latency and readiness failures.
6. Establish initial SLOs only after a staging/production baseline. Recommended first objectives to approve explicitly:
   - zero known workout loss through tested supported flows;
   - zero cross-account/unauthorized exact-route access;
   - at least 99.5% successful eligible auth/activity API requests over the agreed window, excluding deliberate client validation errors;
   - at least 99% of valid queued workouts reach synced within the agreed connected-device window;
   - route-summary p95 and readiness latency budgets derived from IP-4 tests.
7. Add actionable alerts tied to user impact/backlog, not raw log volume. Each alert links to an owner and runbook.

**Verification**

- Automated redaction tests feed representative secrets/coordinates/URLs and prove they do not reach the sink.
- A staging crash/error is symbolicated and contains no banned data.
- Alert drills cover DB unavailable, refresh failures, sync backlog, and cleanup backlog.
- Telemetry deletion/retention behavior is documented and reflected in privacy policy where required.

### IP-5.3 — Expand CI into a release quality system

**Primary files/areas**

- `.github/workflows/` and required-check configuration
- Backend test/config/migration/contract tooling
- Flutter test, analyzer, build, and integration-test configuration
- Optional test-only PostgreSQL service/container in CI

**Required CI jobs**

1. Backend quality:
   - clean install and Prisma generation;
   - TypeScript no-emit typecheck;
   - unit/integration tests;
   - Prisma schema validation;
   - migrate a fresh database and upgrade a representative previous schema;
   - auth/security/avatar/activity contract suites.
2. Flutter quality:
   - format check;
   - `flutter analyze` with zero errors/warnings and a planned removal of remaining touched deprecation/info debt;
   - unit/widget/repository/provider/migration tests;
   - checkpoint/recovery failure suite.
3. Contract/E2E:
   - backend/mobile JSON fixture compatibility;
   - register → auth expiry/refresh → track fixture → sync → restore → delete journey;
   - privacy/owner checks.
4. Build/security:
   - Android release-like build with non-production signing/config in CI;
   - dependency/advisory report with an explicit triage policy;
   - secret scan and license/config checks appropriate to the repository;
   - no production secret material in artifacts/logs.
5. Scheduled/controlled suites:
   - multi-hour synthetic route;
   - 100/1,000-user representative load test against isolated staging;
   - cleanup worker concurrency and restore-from-zero.

**Implementation rules**

- Pin toolchain major/minor versions and update deliberately.
- Do not use blanket analyzer/test exclusions to make a job green.
- Quarantined flaky tests require an owner, issue, expiry date, and non-blocking visibility; core security/data-loss tests cannot be quarantined.
- Protect the main branch with required jobs after a successful proving period.
- Preserve test artifacts only for a bounded period and ensure they contain synthetic data.

**Acceptance**

- Deliberate failures in each critical layer block merge/release.
- A clean checkout can reproduce the build and test result.

### IP-5.4 — Establish staging, release, and rollback discipline

**Implementation**

1. Mature the minimal isolated staging environment bootstrapped in IP-0.1A: add email sandbox, ads test configuration, monitoring, repeatable reset/seed, and production-like topology. No copied production user data without approved anonymization.
2. Define environment configuration inventory and ownership in the secret manager; `.env.example` remains value-free and complete.
3. Promote the identical backend artifact/image and migration set from staging to production. For mobile, produce reproducible flavor-specific staging and production artifacts from the same reviewed commit/toolchain, with distinct endpoints, signing, and ad IDs; record provenance/hashes. An identical mobile binary is required only if runtime configuration safely supports both environments.
4. Release sequence:
   - backup/snapshot and migration dry run;
   - deploy backward-compatible backend/schema;
   - run readiness/security/contract smoke tests;
   - roll out mobile/capabilities gradually;
   - observe phase metrics;
   - retire compatibility only after minimum-version evidence.
5. Define rollback triggers for auth failures, checkpoint/finalization errors, sync backlog, cross-account/privacy failures, crash rate, and readiness.
6. A rollback never reopens IP-0 paths, restores public exact routes, reverts private defaults, loses checkpoints, or reintroduces plaintext tokens.
7. Maintain runbooks for credential rotation, DB restore, stuck migration, sync backlog, cleanup dead letter, auth outage, and mobile forced-minimum-version decision.

**Verification**

- Disaster exercise restores a staging backup and validates referential/data integrity.
- Roll back one representative backend release while preserving new schema/checkpoints/sessions safely.
- Rotate staging credentials without source changes.
- Cold start/readiness and migration timing fit hosting budgets.

### IP-5.5 — Decide and prove platform/monetization scope

**Android release checklist**

- Resolve duplicate `build.gradle`/`build.gradle.kts`; retain one authoritative build.
- Verify signing, package ID, min/target SDK, foreground location, notification, photo picker/storage, network security, and release shrinking rules.
- Inject AdMob app/unit IDs per environment; development/staging always use test IDs.
- Add the applicable consent flow and privacy choices before requesting/serving personalized ads.
- Do not show the start-of-day rewarded prompt before the user receives core value; ads cannot block Start, Finish, recovery, sync, privacy, or account deletion.
- Test release builds on the IP-3 device matrix.

**iOS decision gate**

Either:

1. Keep the product explicitly Android-only and remove iOS readiness claims; or
2. Complete and prove iOS photo-library text/flows, AdMob app ID/consent, background location modes/permissions, signing, foreground/background lifecycle, secure storage, and physical-device recovery tests.

An iOS project folder compiling is not evidence of store readiness.

**Acceptance**

- Production IDs never appear in development/test behavior, consent is verified, and the release description names only proven platforms.

### IP-5.6 — Reconcile product, technical, privacy, and operational documentation

**Files to review**

- Root `README.md`
- `RythmRun_backend_nodejs/README.md`
- `rythmrun_frontend_flutter/frontend_readme.md`
- `rythmrun_frontend_flutter/CONFIGURATION.md`
- `docs/privacy-policy.md`, `docs/delete-account.md`, `docs/terms.md`, `docs/index.md`
- Existing image HLD/LLD documents
- New architecture/runbook/ADR documentation

**Implementation**

1. Describe current product truth: Android-first private offline workout/photo journal, supported workout types, local-first behavior, sync/restore/recovery guarantees, and known scope.
2. Remove or label unimplemented claims about rhythm/music, social, offline maps, automatic refresh, iOS, privacy controls, staging, notifications, or scripts/routes that do not exist.
3. Document exact canonical units, sync protocol/version, payload/batch limits, privacy defaults, retention/deletion behavior, offline-session window, and checkpoint loss objective.
4. Provide setup commands that a clean checkout proves, with environment variable names matching fail-closed config.
5. Mark old design documents as historical when shipped behavior differs; link to the current architecture rather than letting contradictory HLD/LLD remain authoritative.
6. Legal/privacy text must be reviewed by a qualified owner and match actual storage, encryption, ads, telemetry, account deletion, location handling, and retention. Engineering must supply verified facts, not legal conclusions.
7. Keep this improvement directory unpublished from the policy site and free of incident evidence/secrets.

**Acceptance**

- Every documented command/route/feature is checked against a release candidate, and public policy pages agree with the application.

### IP-5.7 — Post-gate focused-retention epic

This work starts only after IP-5.1 through IP-5.6 release controls are operating. It has its own estimate/evidence and is not required to mark the IP-5 release-readiness gate complete.

**Step A: post-workout completion/journal**

- Primary change surface: Track completion flow; a new post-workout summary screen/provider; owner-scoped workout update methods in the domain repository, local DAO, and backend v2 contract; history detail; existing activity-image provider; journal conflict tests.
- After Finish, show a summary using trusted metrics, local-save confirmation, and explicit sync state.
- Let the user add/edit the already-modeled workout name and notes and attach photos without requiring immediate connectivity.
- Move large image decode/resize/JPEG work off the UI isolate before expanding photo use; preserve the existing durable original/thumbnail/checksum state machine and add frame-time/failure tests.
- Add local `journalDirty`, journal revision/last-edited metadata, and a queued idempotent metadata-update operation. Save name/notes locally in one owner-scoped transaction before network work.
- Add the versioned backend metadata PATCH/operation with expected remote revision. A concurrent edit preserves both versions and invokes the narrow IP-4 journal conflict UI; route/metric data is immutable.
- Never interrupt save/recovery with an ad.
- Tests: offline edit/restart, repeated save, auth expiry/retry, cross-account row ID, concurrent remote edit, image failure, and sync-status rendering. Rollback hides the new screen but retains queued edits and schema fields.

**Step B: trends and personal bests**

- Primary change surface: version-aware SQL aggregate/query service, new trends/PB domain models/providers/screens, unit-aware formatters, and fixed metric fixtures.
- Add weekly/monthly distance, duration, activity count, and type filters from canonical versioned metrics.
- Before coding, commit exact PB eligibility rules by workout type/distance/duration and treatment of rejected/legacy metric versions; do not compare ineligible records.
- Compute locally first from indexed data; verify with fixtures and avoid misleading comparisons across unit/metric versions.
- Tests cover empty/sparse history, ties, unit changes, paused duration, legacy version exclusion, calendar boundaries, and incremental update after a new workout.

**Step C: goals and streaks**

- Add only after trends/PB usage and correctness are measured.
- Make goals user-owned and offline-capable; sync with version/conflict rules if cross-device support is required.
- Use local calendar/time-zone rules explicitly and test travel/daylight-saving boundaries.
- No manipulative notifications; reminders are opt-in and separately permissioned.

**Deferred after measurement**

- Social/challenges, cadence/rhythm coaching, health/wearable integration, and AI summaries.

**Acceptance**

- The core loop is Track → Finish/confirm local save → Review/journal → See sync/restore confidence → Return for personal progress.
- Journal work has offline/update/conflict/rollback evidence; trends/PBs have exact eligibility fixtures. Goals/streaks remain a separate decision after measured usage.

## Final release journey

Run on a release candidate with synthetic accounts/data:

1. Register and enter the authenticated state.
2. Start a workout, accept/reject representative GPS points, pause, and move.
3. Kill the process, reopen, and recover.
4. Resume, finish while offline, and see a durable local summary/queued state.
5. Attach a photo offline using the already-supported image journey.
6. Reconnect; refresh expired auth once; sync workout/photo in bounded requests.
7. Install/clear app data on another device; log in and restore without duplicates.
8. Verify a second account cannot access route, checkpoint, image, or local row IDs.
9. Exercise password change/recovery and confirm old sessions fail.
10. Delete the account and verify remote/local rows, files, sessions, tombstones/cleanup behavior, and user-facing confirmation.

Any failure involving security, cross-account access, workout loss/duplication, exact-route privacy, refresh, or deletion is a release blocker.

## Rollback plan

- Promote/rollback immutable artifacts while retaining forward-compatible schemas.
- Preserve checkpoint, tombstone, session revocation, private visibility, and cleanup queue data during rollback.
- Disable new retention UI by capability flag if needed; core save/sync/recovery remains available.
- Monitoring/alerts remain active during rollback.
- If documentation no longer matches after rollback, update release notes/support immediately and restore accurate source docs in the next change.

## Exit gate

- [ ] App construction is testable; server lifecycle/readiness/shutdown are bounded and verified.
- [ ] Staging is isolated; the same backend artifact/migrations are promoted, and mobile flavor artifacts are reproducible/provenanced from the same reviewed commit/toolchain.
- [ ] Logs, crashes, metrics, and alerts are redacted and have owners/runbooks.
- [ ] Initial SLOs and rollback triggers are approved from measured baselines.
- [ ] CI blocks security, type, test, migration, contract, analyzer, E2E, and build regressions.
- [ ] Backend production dependencies have a dated triage with no unaccepted critical/high exposure.
- [ ] Flutter has zero analyzer errors/warnings; remaining infos/deprecations have a bounded cleanup plan and none exist in critical touched flows.
- [ ] Android release configuration, physical-device tests, consent, and test-vs-production ad IDs pass.
- [ ] iOS is either fully proven or explicitly not supported.
- [ ] Root/backend/configuration/architecture docs match the release candidate.
- [ ] Privacy, terms, and deletion pages match verified data/ads/telemetry behavior and have the required review.
- [ ] The complete final release journey passes.
- [ ] No open P0/P1 finding remains.
- [ ] IP-5.7 is recorded as a separately estimated post-gate epic; its incomplete status does not weaken or block the release-readiness result.
- [ ] Deferred social/AI/infrastructure work remains out of scope unless a new evidence-backed plan replaces this decision.

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| — | — | No implementation evidence yet | Not started | Planning document only |
