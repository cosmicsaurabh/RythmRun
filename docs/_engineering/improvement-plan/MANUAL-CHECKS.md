---
published: false
---

# Manual and hosted verification register

This register owns improvement work that cannot be proven by repository tests alone. It keeps hosted CI, deployment, incident-response, infrastructure, and controlled-rollout evidence visible while repository work continues.

Do not store secrets, tokens, raw logs, customer identifiers, exact routes, database snapshots, or incident details in Git. Put sensitive evidence in the access-controlled system named by the owner and record only a safe ticket or run reference here.

## Status rules

- `Pending`: no dated evidence has been reviewed.
- `In progress`: an owner and evidence location exist and execution has started.
- `Blocked`: the required access or decision is unavailable; record the blocker and keep affected routes contained.
- `Verified`: the pass condition has dated evidence and an independent reviewer.
- `Failed`: the check ran but did not meet its pass condition; execute the stated containment or rollback action.

Repository commits and local test results cannot change a manual check to `Verified`.

## Current register

| ID | Check | Owner | Status | Required safe evidence | Evidence/date | Reviewer | Notes/blocker |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MC-0.1 | Production route containment | Deployment owner | Pending | Dated edge/application route inventory and independent probe reference | — | — | — |
| MC-0.2 | Evidence preservation and exposure disposition | Security owner | Pending | Restricted incident-ticket reference covering log window, snapshot, and disposition | — | — | — |
| MC-0.3 | Credential/session rotation | Secret-store and database owners | Pending | Restricted rotation record plus proof that old credentials/sessions fail | — | — | — |
| MC-0.4 | Database migration and unsafe avatar-value quarantine | Database owner | Pending | Backup reference, migration run, classified counts, and rollback record | — | — | — |
| MC-0.5 | R2 access/delivery, database TLS, lifecycle, and backup posture | Infrastructure owner | Pending | Restricted configuration review and isolated restore reference | — | — | — |
| MC-0.6 | Isolated security staging | Deployment owner | Pending | Environment/run reference proving isolation and non-production credentials/data | — | — | — |
| MC-0.7 | Hosted `Backend security` success | Repository maintainer | Pending | Successful GitHub Actions run URL for the committed workflow | — | — | — |
| MC-0.8 | Intentional CI failure probe | Repository maintainer | Pending | Failed run URL from a temporary non-merge revision and cleanup reference | — | — | — |
| MC-0.9 | Required branch-protection check | Repository administrator | Pending | Ruleset reference showing stable `Backend security` check is required | — | — | — |
| MC-0.10 | Dated production dependency advisory review | Security maintainer | Blocked | Full dated report and one decision per advisory | — | — | Explicit approval is required before sending the dependency inventory to npm. |
| MC-0.11 | Supported mobile avatar lifecycle in staging | Mobile and QA owners | Pending | Build/version plus request, upload, confirm, display, replace, and logout run record | — | — | — |
| MC-0.12 | Controlled reopen and 24-hour observation | Deployment/on-call owner | Pending | Reopen timeline, dashboards, thresholds, rollback owner, and observation outcome | — | — | — |
| MC-1.1 | Legacy metric sampling and classification | Product-data and database owners | Pending | Restricted sample showing distance/active-duration/stored-speed ratios and approved classification rules | — | — | Never copy user routes or row-level personal data into Git. |
| MC-1.2 | Metric migration backups and staging exercise | Database and mobile owners | Pending | PostgreSQL/SQLite backup references, migration runs, version counts, and rollback rehearsal | — | — | Current repository migration only tags provenance; historic values are not rewritten. |
| MC-1.3 | Previous-client and device compatibility | Mobile and QA owners | Pending | Supported old-client matrix plus Android SQLite upgrade/reopen evidence | — | — | Backend migration must precede the corrected version-2 mobile writer. |
| MC-1.4 | Coordinated metric rollout and observation | Deployment, mobile, and on-call owners | Pending | Backend/mobile versions, staged rollout timeline, metric-version telemetry, thresholds, and outcome | — | — | IP-0 containment must remain active throughout. |
| MC-1.5 | GPS acceptance and pause behavior on devices | Mobile and QA owners | Pending | Release-build route run showing active/pause/resume distance, accepted route, persisted result, and sanitized-log review | — | — | Never attach exact coordinates, timestamps, or route exports to Git evidence. |
| MC-1.6 | User-scope exit and account-switch isolation | Mobile, backend, and QA owners | Pending | Staging build/run covering idle and active logout, forced auth loss, save recovery, sync drain, and A→B isolation | — | — | Use synthetic accounts and safe run references; never attach tokens, routes, profile objects, or local database contents to Git. |
| MC-1.7 | Android SQLite v5→v6 ownership migration | Mobile, database, and QA owners | Pending | Release-build in-place upgrade/reopen record covering FK diagnostics, retained valid rows, A/B known-ID denial, cascades, and forward-fix recovery | — | — | Use synthetic fixtures and restricted backup references. Do not attach database files, route rows, image paths, or account data to Git. |
| MC-1.8 | Bounded activity ingest and PATCH history in staging | Backend, mobile, deployment, and QA owners | Pending | Staging run covering edge/application size limits, UTC/legacy compatibility, mobile permanent/retry classification, long-workout sync, admission pressure, PATCH preservation/clear, PostgreSQL rollback/concurrency, and sanitized telemetry | — | — | Use synthetic activities only. Do not attach route payloads, coordinates, tokens, database rows, or raw logs to Git. |
| MC-1.9 | Hosted `Flutter CI` success | Repository maintainer | Pending | Successful GitHub Actions run URL for the reviewed commit and stable `Flutter CI` check | — | — | A local Flutter run or workflow file is not hosted evidence. |
| MC-1.10 | Independent CI regression probes | Repository maintainer and reviewer | Pending | Separate failed run URLs for backend type, Flutter test/format/analyzer-warning/new-information probes plus cleanup and final-green references | — | — | Run one fault per temporary non-merge revision so fail-fast cannot mask a later gate. MC-0.8 separately owns the backend-test probe. |
| MC-1.11 | Required backend/Flutter checks and protected CI controls | Repository administrator | Pending | Ruleset/review-policy reference proving both stable checks are required and workflow/comparator/baseline changes require independent review | — | — | Do not let a pull request weaken the gate that evaluates itself without protected review. |
| MC-1.12 | Prisma 7.8 on real PostgreSQL | Database, infrastructure, backend, and QA owners | Pending | Restricted staging run covering full migrations, adapter query/transaction behavior, TLS, schema selection, pool limits/timeouts, and connection counts | — | — | The repository built smoke deliberately does not connect to a database. Use synthetic data and never commit URLs, certificates, snapshots, rows, or raw logs. |
| MC-1.13 | Backend artifact order and deployed shutdown | Deployment, database, backend, and on-call owners | Pending | Artifact provenance plus install/build/migrate/prune/start and bounded SIGTERM run records | — | — | Prove one migration owner, the promoted artifact, listener drain, timer stop, Prisma pool closure, and deadline behavior on the actual host. |
| MC-1.14 | Android ad configuration and durable-completion gate | Mobile, release, monetization, and QA owners | Pending | Reviewed build matrix, merged-manifest classification, intentional configuration-failure record, and supported-device save/recovery run with ad-attempt counts | — | — | Use synthetic workouts and counts only. Do not record production IDs, routes, timestamps, database rows, or raw SDK logs. Consent and live production enablement remain IP-5.5. |
| MC-2.1 | Hosted PostgreSQL auth-session transaction gate | Repository maintainer and backend reviewer | Pending | Successful `Backend security` run URL for the reviewed SHA showing migration deploy and enabled auth PostgreSQL suite | — | — | Confirm the six database tests execute rather than skip and the two-client same-token race passes. Use only the disposable synthetic CI database; never record tokens or rows. |
| MC-2.2 | Auth-session destructive cutover and forced-login staging rehearsal | Database, deployment, backend, mobile, and QA owners | Pending | Restricted backup/upgrade-copy reference, old-instance drain, migration/artifact provenance, synthetic old-token rejection, new login/refresh/logout canary, rollback decision, and one-time-sign-in communication | — | — | Legacy JWTs cannot be backfilled. Never restore plaintext refresh rows or revoked sessions. Keep production rollout blocked until the matching artifact and migration order are rehearsed. |
| MC-2.3 | Android secure-credential migration and session lifecycle | Mobile, security, backend, and QA owners | Pending | Reviewed release-build/device matrix covering in-place preference migration and interruption recovery, encrypted-at-rest inspection, backup/restore exclusion, sanitized logs, concurrent expiry refresh, offline/invalid separation, the seven-day offline window and clock-rollback fail-closed behavior, offline server-mutation denial, login/register/password/logout roots, and rollback | — | — | Use synthetic accounts and sentinel credentials only in isolated staging. Store no token, device file, screenshot containing a token, profile body, route, or raw log in Git. Android is the promised platform under D-008; iOS evidence is optional until IP-5 changes scope. |

## Hosted CI procedure

### MC-0.7 — Successful backend security workflow

1. Push the reviewed branch and open a pull request through the normal protected path.
2. Confirm the workflow resolves the expected commit SHA and uses the `Backend security` job.
3. Verify the hosted job completes `npm ci --no-audit`, Prisma schema validation, Prisma generation, the production TypeScript typecheck, the complete native ESM Jest suite, the production build, and `npm run smoke:runtime`. Do not substitute a source-only transform for the emitted build. The separately approved advisory submission belongs only to MC-0.10.
4. Record the run URL and commit SHA in this register and the IP-0 evidence log.
5. If hosted behavior differs from local behavior, keep the check pending, fix the workflow in a separate reviewed commit, and rerun it.

Pass condition: one successful run for the reviewed commit with no skipped required step. A workflow file or local YAML parse is not sufficient evidence.

### MC-0.8 — Intentional failure probe

1. Create a temporary branch from the reviewed commit; never perform the probe on `main`.
2. Change one existing security assertion so the test fails deterministically. Do not weaken production code, publish exploit material, or include secrets.
3. Push the temporary revision and open or update a non-merge pull request so the same workflow runs.
4. Confirm `Backend security` fails at the backend-test step for the intentional assertion failure.
5. Record the failed run URL and temporary commit SHA, then close the temporary pull request and delete the remote branch.
6. Confirm the reviewed branch remains green and contains none of the probe change.

Pass condition: the intentional regression produces a failed required check and the probe revision is not merged.

### MC-0.9 — Branch protection

1. After MC-0.7 and MC-0.8 pass, add the stable `Backend security` job name to the `main` ruleset.
2. Require pull requests and require the branch to be current before merge if that is the repository policy.
3. Do not allow the check to be bypassed for ordinary merges; document narrowly controlled emergency administration separately.
4. Open a harmless test pull request or inspect the ruleset UI/API to prove the check is required.

Pass condition: an unpassed `Backend security` check prevents a normal merge to `main`.

### MC-1.9 — Successful Flutter workflow

1. Push the reviewed branch and open a pull request through the normal protected path. Use `pull_request`, never `pull_request_target`.
2. Confirm the run resolves the reviewed commit SHA and the stable job name is `Flutter CI` on Ubuntu 24.04 with Flutter 3.44.1/Dart 3.12.1. Confirm checkout and Flutter setup resolve the immutable action commits recorded in the workflow.
3. Confirm the job restores `pubspec.lock` with enforcement, checks only merge-base-changed/new Dart formatting, rejects analyzer warnings/errors, accepts only a sub-multiset of the committed 20-finding informational allowance with no new keys/count increases, and runs the complete Flutter suite including SQLite FFI tests.
4. Inspect the run configuration: permissions remain `contents: read`; checkout credentials are not persisted; no database, R2, JWT, signing, or environment secrets are exposed; no workspace, `.dart_tool`, generated config, or secret file is cached or uploaded.
5. Record the successful run URL and commit SHA here and in the IP-1 evidence log. If Linux SQLite/Flutter behavior differs from local behavior, keep this check pending, fix it in a reviewed commit, and rerun.

Pass condition: one successful unskipped `Flutter CI` run for the reviewed SHA. Source inspection, a local suite, or a run for a different commit is insufficient.

### MC-1.10 — Independent regression probes

1. Start each probe from the same reviewed green commit on a temporary non-merge branch. Use a separate commit/run for each fault; restore the branch to green or delete it before starting the next probe.
2. Add a deterministic TypeScript type error and confirm only the relevant `Backend security` type-check path is red. MC-0.8 separately proves a backend Jest assertion failure.
3. In separate Flutter revisions, introduce: one failing test assertion; one unformatted changed Dart file; one analyzer warning; and one additional informational lint (or an extra occurrence of an existing key). Confirm `Flutter CI` fails respectively at test, format, fatal warning analysis, and baseline comparison.
4. For the informational probe, do not edit the baseline or comparator. Confirm deleting one existing informational occurrence is accepted in a separate safe rehearsal or comparator fixture; do not merge unrelated lint cleanup through the probe branch.
5. Record every failed run URL, temporary commit SHA, expected failing step, cleanup/closed-PR reference, and the final green run for the unchanged reviewed commit. Do not publish exploit details, secrets, raw logs, or production data.

Pass condition: all faults fail at their intended independent gate, none of the probe revisions is merged, and the reviewed commit finishes green afterward. One fail-fast run containing several faults does not satisfy this check.

### MC-1.11 — Required checks and protected CI controls

1. After MC-0.7 through MC-0.9 and MC-1.9 through MC-1.10 pass, require both stable job names, `Backend security` and `Flutter CI`, in the `main` ruleset without path filters that leave a required check unreported.
2. Require pull requests and current-branch checks according to repository policy; do not permit ordinary merge bypass when either job is missing, pending, cancelled, or failed.
3. Configure independent review ownership for `.github/workflows/backend-security.yml`, `.github/workflows/ci.yml`, `rythmrun_frontend_flutter/tool/ci/analyzer_baseline.dart`, and `rythmrun_frontend_flutter/tool/ci/analyzer_baseline.json`. The reviewer must inspect baseline count additions and immutable action/toolchain changes rather than approving them mechanically.
4. Use a harmless test pull request or ruleset inspection to prove each missing/failed job blocks a normal merge and a CI-control change cannot self-approve. Record only safe ruleset/run references.

Pass condition: both checks block normal merges until green, and weakening a workflow/comparator/baseline requires an independent authorized review. Emergency administration, if allowed, is narrowly documented and audited.

## Prisma 7 and backend deployment procedure

### MC-1.12 — Exercise Prisma 7.8 against real PostgreSQL

1. Create an isolated PostgreSQL environment with synthetic data, a restricted evidence location, and a restorable pre-run backup. Record the PostgreSQL version and safe environment/run identifier, never its connection URL or certificate material.
2. Verify certificate validation and the exact TLS mode used by both the migration connection and runtime connection. Reject expired, untrusted, hostname-mismatched, or silently downgraded connections; do not add insecure certificate acceptance as a workaround.
3. From a clean checkout and locked install, run Prisma schema validation/generation, then apply the complete migration chain to a fresh database. Separately exercise the supported upgrade path on a representative previous schema and run `prisma migrate status`; no drift, failed migration, or unowned concurrent migration may remain.
4. Start the built native-ESM artifact with the Prisma PostgreSQL adapter and execute a bounded health/query fixture plus the representative serializable activity/avatar transactions. Prove commit and rollback behavior, uniqueness/cascade expectations, timestamp/float round trips, and retry classification without copying row data into Git.
5. If a non-`public` schema is supported, prove the configured schema is selected by both Prisma CLI and the runtime adapter. If only `public` is supported, document and enforce that deployment contract rather than relying on an ignored URL parameter.
6. Measure runtime pool behavior with the committed maximum, 5-second connection timeout, 300-second idle timeout, and the real number of application replicas. Record peak/idle/waiting connections, database capacity headroom, connection-failure latency, and recovery after database restart. Approve different values only through a reviewed configuration change and repeat the measurement.
7. Stop the application through its cleanup API and verify all Prisma/`pg` connections close. Then repeat under a database-down/slow-connection condition and confirm error output contains categories only—no credentials, URLs, SQL parameters, or private row data.

Pass condition: fresh and upgrade migrations, TLS verification, adapter queries/transactions, schema selection, pool bounds/timeouts, failure recovery, and disconnect all have dated owner/reviewer evidence. `prisma validate`, mocked transactions, or the no-database built smoke alone do not satisfy this gate.

### MC-1.13 — Prove artifact ordering and bounded deployed SIGTERM

1. Document and execute the host's exact sequence: locked install including build tools; Prisma generation/schema validation; production typecheck; native ESM Jest; production build; built runtime smoke; one-owner migration; optional development-dependency pruning; and start from the same emitted artifact. If the host installs with `--omit=dev` before build/migration, treat that as a failed deployment contract.
2. Record the reviewed commit, Node 22 runtime, lockfile digest, artifact identifier, migration set, and safe deployment reference. Promote the same artifact from isolated staging; do not rebuild production from a different dependency resolution.
3. Confirm `npm run smoke:runtime` imports the emitted Prisma/client/container/route graph, serves process liveness, rejects an unauthenticated protected request before persistence, and releases its local listener/timer/client wrapper. Record explicitly that this smoke uses an unreachable database and does not prove PostgreSQL, TLS, migrations, R2, pool capacity, or deployed signal behavior.
4. On the real host with synthetic traffic, send `SIGTERM` while one bounded safe request is active. Confirm the instance stops receiving new traffic, the listener drains within the approved grace period, retry/background timers stop, the active request finishes or is terminated according to policy, and the Prisma pool closes.
5. Repeat with an intentionally stuck request. Confirm the documented deadline triggers the approved force-close behavior, produces a failure exit/status visible to orchestration, and does not leave a migration, worker lease, or database session owned by the terminated instance.
6. Restart the promoted artifact and prove readiness/traffic recovery without duplicate migration execution. Full dependency-aware readiness remains IP-5.1; this check proves only the current artifact and shutdown contract.

Pass condition: the actual host demonstrates deterministic build/migrate/start ordering, one migration owner, identical artifact promotion, and bounded graceful/forced shutdown with closed database resources. A local signal unit test or source inspection is insufficient.

## Android ad-safety and durable-completion procedure

### MC-1.14 — Prove packaged ad configuration and recovery-first behavior

1. Use the reviewed commit, locked Flutter toolchain, one supported Android device, and a synthetic QA account. Record only the commit, build identifiers, device/OS class, safe test-case references, and aggregate ad-attempt outcomes. Never put an AdMob production ID, exact route, acquisition timestamp, local row, database file, or raw SDK log in Git.
2. Build the safe matrix from `rythmrun_frontend_flutter/CONFIGURATION.md`: development debug with ads disabled, staging profile with ads disabled, and production release with ads disabled. Inspect each **merged/package manifest**, not only the source manifest. Confirm the AdMob application metadata resolves to the official Google sample application ID and never to a supplied production value; `com.google.android.gms.ads.DELAY_APP_MEASUREMENT_INIT` resolves to `true`; and the `AD_ID`, `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION`, and `ACCESS_ADSERVICES_TOPICS` permissions are absent. Confirm Dart resolves the no-op provider, makes no Mobile Ads initialization/ad request, and disables start-of-day reward, post-activity, and banner behavior.
3. Run the documented negative release command with `ADS_ENV=production` and `ADS_ENABLED=true` but no IDs. The build must stop during configuration and produce no APK/AAB. Repeat through an aggregate/custom Gradle entry point and with a controlled malformed, Google-sample, or publisher-mismatched placeholder through the approved secret-injection path; every case must fail before packaging. Retain the full output only in restricted QA storage and record a sanitized failure reference here.
4. Do not use real production IDs merely to satisfy this check. A successfully packaged live-ID build, consent/privacy choices, production SDK/request verification, placement approval, and monetization rollout remain IP-5.5. Until that gate passes, keep `ADS_ENABLED=false` for every distributable build.
5. On the ads-disabled device build, complete one synthetic workout successfully. Verify the local transaction completes and the workout is visible from the local history path before the optional completion gate is reached. Confirm there is no ad surface or SDK request. Trigger duplicate Finish/back-navigation actions and confirm they do not create a second local workout or ad attempt.
6. In a controlled QA build, inject one local-save failure. Finish must retain the completed workout, block starting another workout, show Retry save and explicitly confirmed Discard actions, and record zero post-activity ad attempts. Fail one retry, then allow a successful retry; the workout must become durable and recovery must still record zero ad attempts.
7. Separately inject incomplete tracking-resource cleanup after a successful local save. Recovery UI must appear before any ad opportunity, Retry cleanup must remain available, and the ad-attempt count must remain zero. Confirm an ad/SDK failure or non-completing initialization/load callback cannot hang Finish, hide a committed workout, or replace save/cleanup recovery UI. Begin account exit during a delayed ad initialization/load and confirm no provider display occurs after the user scope changes.
8. Review sanitized device telemetry and the QA counter. It may record build mode, environment class, finalization status category, recovery category, and aggregate ad-attempt count only. It must not contain IDs, account values, coordinates, timestamps, route payloads, local paths/rows, or SDK request/response bodies.

Pass condition: safe debug/profile/ads-disabled release packages contain only the official sample application ID, delay native measurement startup, omit ad/privacy permissions, and run the no-op provider; an intentionally enabled but incomplete/invalid production configuration cannot package through direct or aggregate/custom tasks; and supported-device Finish behavior proves no ad attempt occurs before a newly committed local workout or during save/cleanup recovery. This gate does not enable live ads or satisfy IP-5.5 consent, privacy-choice, placement, iOS, or production-rollout requirements.

## Authentication session procedure

### MC-2.1 — Run the hosted PostgreSQL transaction gate

1. Push the reviewed IP-2.1 commit through the ordinary pull-request workflow. Confirm `Backend security` resolves that SHA, provisions its disposable `rythmrun_ci` PostgreSQL service, and applies the complete migration chain before tests.
2. Inspect the Jest summary and confirm all six `auth-session.postgres.test.ts` cases execute; a skipped database suite is a failed gate even when the job is otherwise green.
3. Confirm the run covers two independent Prisma clients racing one refresh token, committed replay-family revocation, digest-only registration/login rows, logout/password revocation, stale-login rejection during a password-change race, the five-session bound, and safe `/me` data. Do not expose raw tokens, connection strings, or database rows in logs/artifacts.
4. Record the run URL, reviewed commit, PostgreSQL image tag, and independent reviewer. Keep broader provider TLS/custom-schema/pool/deployment evidence under MC-1.12/MC-1.13.

Pass condition: the reviewed hosted SHA applies every migration and runs—not skips—the real-PostgreSQL auth suite with exactly one refresh winner at most and committed family revocation.

### MC-2.2 — Rehearse the destructive session cutover

1. Use an isolated staging upgrade copy and synthetic accounts. Verify a restorable backup and record only restricted references, never database contents, JWTs, or connection details.
2. Build and identify the session-aware artifact first. Drain every old backend instance before applying `20260713000000_rebuild_auth_sessions`; do not allow an old process to continue accepting legacy plaintext refresh rows during cutover.
3. Apply the migration once, confirm the legacy table is absent and the new constraints/indexes exist, then promote the already-reviewed matching artifact. Prove legacy access/refresh JWTs fail and a communicated one-time sign-in creates only digest records.
4. Run synthetic register, login, refresh, concurrent refresh, `/me`, logout, and password-change canaries. Verify logs contain only safe categories and no token/digest/profile body.
5. Exercise the rollback decision. Prefer roll-forward; never recreate plaintext refresh rows, restore revoked session state, or promote a backend that does not understand `sid`/`jti`/`typ`.

Pass condition: backup, drain, migration, matching-artifact promotion, forced-login communication, auth canaries, and safe roll-forward response have dated owner/reviewer evidence.

### MC-2.3 — Verify Android secure migration and session lifecycle

1. Build the reviewed release candidate against isolated staging with synthetic accounts. Record only the commit, artifact digest, Android/OS/device classes, and restricted run reference. Confirm the merged manifest has application backup disabled; do not weaken that control merely to inspect or transfer credentials.
2. On each supported Android device class, install the previously supported app and create a coherent synthetic IP-2.1 access/refresh pair in the historical preference keys. Upgrade in place. Confirm the app reaches online verification, the legacy secret keys are absent only after the complete secure envelope was read back, and cached non-secret user metadata remains coherent. Inspect storage through an approved restricted device-lab method and record only pass/fail: neither sentinel credential may appear in plaintext preferences, ordinary files, screenshots, exported diagnostics, or logs.
3. Repeat with controlled interruption before secure write, after secure write but before legacy-key cleanup, and during cleanup, restarting the process/device at each boundary. The next launch must either complete migration once or require verification/sign-in; it must never lose the only recoverable pair, construct protected UI from a partial pair, duplicate rotation, or restore a rejected pair as offline-authorized.
4. Exercise backup/restore, device-to-device transfer where supported, app-data clear, reinstall, and secure-store key loss. No operation may recreate an authenticated/offline session from cached user/SQLite data alone. A restored encrypted blob without its device-bound key must fail closed without logging values. Keep broader route/photo database encryption under IP-2.7.
5. Run login and registration and confirm both reach the same authenticated root. Force access expiry while three idempotent protected reads are active and verify one refresh plus one replay per request; confirm a non-idempotent mutation is not replayed. Test airplane-mode/service outage versus explicit refresh revocation: eligible verified history may enter bounded offline mode only for the former, while revocation blocks protected UI, preserves any required local workout recovery, and cannot regain offline admission after process death.
6. Exercise the IP-2.3 offline-window and clock-tamper policy on device. With no network, confirm eligible verified history is reachable inside seven days from the last successful server verification and is refused after it, always without deleting completed local workouts. Roll the device wall clock backward (and forward then backward) and confirm offline admission fails closed and requires fresh online verification rather than extending access; confirm the rollback tripwire persists across a process/device restart. Confirm offline mode denies server mutations — password change, avatar upload, and background sync — with a clear, non-alarming message, and that reconnecting restores them. Record only pass/fail and safe references; never attach tokens, routes, or raw logs.
7. Change the password and confirm the successful response immediately removes the exact local credential revision, completes or visibly blocks user-scope recovery, and ends at the guest root. Repeat logout and backend-forced revocation. Verify no newer login is deleted by a delayed old-session response and no sync/profile write appears after teardown completes.
8. Review release logs and exported diagnostics using unique synthetic sentinel values. Record only the safe report reference: no access/refresh token, password, authorization header, profile body, secure-store payload, exact route, coordinate, local path, or signed URL may appear. Exercise rollback as a forced local sign-in/credential clear; never restore plaintext preference tokens or downgrade to an app that can persist them.

Pass condition: every supported Android class passes migration, interruption, storage, backup, lifecycle, offline/revocation, seven-day-window and clock-rollback fail-closed, offline server-mutation denial, root-navigation, and redacted-log checks with dated owner and independent security/QA review. Repository tests or a debug APK alone cannot mark MC-2.3 verified.

## Dependency advisory procedure

### MC-0.10 — Dated production scan and triage

1. Obtain explicit approval before sending the dependency inventory to the npm advisory service.
2. From `RythmRun_backend_nodejs`, run `npm audit --omit=dev` and retain the complete dated report in an approved evidence location.
3. For every advisory, record package, installed path, severity, affected range, runtime reachability, chosen fix, owner, and due date.
4. Upgrade or remove reachable vulnerable packages. A suppressed or accepted advisory needs owner approval, reachability evidence, an expiry date, and a tracking reference.
5. Do not reopen affected routes while a reachable critical/high production advisory remains.
6. After remediation, rerun a clean install, Prisma validation/generation, the production TypeScript typecheck, native ESM Jest suite, production build, built runtime smoke, and the dated production audit.

Pass condition: no reachable critical/high production advisory remains, and every other result has a reviewed, time-bounded disposition. The 2026-07-10 count of 11 is discovery evidence, not a current result.

## Deployment and incident procedure

### MC-0.1 through MC-0.6 — Containment before rollout

1. Keep registration/profile/avatar paths restricted until containment is independently verified.
2. Preserve the relevant log window and database snapshot before cleanup; never copy raw evidence into Git.
3. Classify unsafe legacy avatar values using a reversible migration after a backup is verified.
4. If exposure cannot be excluded, rotate JWT, refresh/session, database, AWS, and CDN material in an order that keeps replacement credentials working before old credentials are revoked.
5. Verify R2 credential scope, bucket access/public-delivery policy, encryption, abandoned-object lifecycle, database TLS, backup retention, and an isolated restore.
6. Confirm the deployment host uses Node.js 22.x, then deploy only to isolated staging with non-production credentials and sanitized or synthetic data before any production reopen.

Pass condition: each row has a restricted evidence reference, dated owner sign-off, independent reviewer, and a tested containment/rollback response.

### MC-0.11 and MC-0.12 — Staged lifecycle and controlled reopen

1. Exercise the supported Flutter build through avatar request, multipart upload, confirmation, display, replacement, and logout in isolated staging.
2. Verify safe request IDs/error categories and confirm logs contain no secrets, signed URLs, raw object keys beyond operational need, filesystem paths, response bodies, or exact routes.
3. Reopen registration/profile text paths first and avatar request/confirm only after storage policy, quota, intent, and cleanup checks pass.
4. Define rollback thresholds for `4xx`, `5xx`, avatar-confirm, storage rejection, and R2 errors before reopening.
5. Observe continuously for 24 hours with a named on-call owner. Reapply containment before rollback if a threshold or security invariant fails.

Pass condition: the valid lifecycle passes, negative probes remain contained, monitoring stays within approved thresholds, and the 24-hour result is recorded.

## Evidence updates

When a check changes state, update its row with a safe evidence reference and add a dated entry to the applicable phase evidence log. Never infer completion of another row: for example, hosted CI does not prove staging, production deployment, dependency safety, or incident closure.

## IP-1 metric migration procedure

### MC-1.1 — Sample before interpreting legacy values

1. Work only from an access-controlled export containing the minimum fields needed: metric version, distance, active duration, stored average speed, and a non-identifying record reference.
2. Calculate `storedAverageSpeed / (distanceMeters / activeDurationSeconds)`. A result near `1.0` suggests canonical m/s; a result near `3.6` suggests the historical km/h defect. Treat zero, invalid, mixed, or ambiguous records as unresolved rather than guessing.
3. Record sample window, counts, classification thresholds, exclusions, and reviewer approval outside Git.
4. Do not divide `maxSpeed` or GPS point speed; those values were already m/s.

Pass condition: the affected version/time range and deterministic conversion rules are approved, or historic values remain version 1 and unchanged.

### MC-1.2 — Back up and exercise migrations

1. Verify restorable PostgreSQL and representative device/SQLite backups before any value rewrite.
2. Apply the additive backend column/check first and the SQLite version-5 migration to staged copies.
3. Prove existing rows become version 1 without numeric changes and new corrected rows persist as version 2.
4. Run any later approved value migration only where version 1 and the MC-1.1 classification rule both match; update the value and marker atomically and idempotently.
5. Reopen/restart twice, compare version counts and metric aggregates, and rehearse rollback from captured data rather than multiplying values blindly.

Pass condition: both stores preserve unresolved legacy data, version-2 writes round-trip, and the backup/rollback rehearsal succeeds.

### MC-1.3 and MC-1.4 — Compatibility and rollout

1. Deploy the additive backend migration, then backend support for versions 1 and 2, before releasing the corrected mobile writer.
2. Verify an old supported client still creates version-1 activities and the new client creates version-2 activities with m/s values.
3. Exercise Android database upgrade, process restart, local history/statistics, sync retry/idempotency, and rollback on representative devices.
4. Roll out the mobile build gradually and monitor version counts, speed/distance ratios, sync `4xx`/`5xx`, migration failures, and abnormal calorie/speed distributions without collecting exact routes.
5. Stop rollout on a threshold breach; preserve the provenance marker and restore only from approved backups.
6. Once any unsynced version-2 workout exists, do not roll back to a client that omits `metricsVersion`: it would upload canonical m/s as legacy version 1. Stop sync and forward-fix, or first prove every version-2 row has been finalized safely.

Pass condition: mixed-version compatibility, staged migration, and the observation window have dated owner/reviewer evidence while all IP-0 containment requirements remain enforced.

### MC-1.5 — GPS acceptance and pause behavior

1. Use an isolated test account and a reviewed release build on representative Android and iOS devices; record only build/device references in Git.
2. Walk or run a measured short route, pause, move a deliberate large distance, resume, and finish. Confirm paused movement and the first resumed sample add zero distance.
3. Compare the displayed map, completed local route, distance, active time, maximum speed, and synced route count. They must all derive from the same accepted sequence with visible breaks across pauses or sample gaps.
4. Exercise poor-accuracy and implausible-jump conditions in an approved simulator/device harness. Confirm rejection does not change route, distance, pace, maximum speed, elevation, or calories.
5. Finish once while paused and repeat pause/resume several times. Confirm the open pause closes once, active time is non-negative, and a duplicate finish does not create a second workout.
6. Inspect release logs and crash/analytics breadcrumbs for the run. Exact coordinates, acquisition timestamps, and route payloads must be absent; store sensitive device evidence only in the access-controlled QA system.

Pass condition: Android and iOS evidence shows one accepted route across UI/local/sync, deterministic pause timing, no resume bridge, and no exact-route logging.

### MC-1.6 — User-scope exit and account-switch isolation

1. Use two synthetic staging accounts, A and B, on a representative supported Android release build. Load A's history, workout details, activity images, profile/avatar, calculator/settings state, and a pending sync before exercising logout.
2. While A is idle, make only the remote logout endpoint unavailable and sign out. Confirm user-scoped work drains and local credentials/session state still clear, the landing screen appears, A's completed offline rows remain stored, and no A provider content flashes after logout. Server-side access-token revocation remains an IP-2 responsibility; do not infer it from this check.
3. In a controlled test build, inject a local `clearAuthData` failure separately. The exit must remain blocked on non-dismissible Retry cleanup UI, B must not authenticate, and a process restart must not silently restore usable A access. Remove the fault and confirm retry clears credentials before the landing screen or B activation is allowed.
4. Sign in as B without restarting the process. Confirm B starts with only B-scoped history, details, images, profile, and sync work even when local workout IDs overlap. Attempt no destructive cross-account probe against production; use only seeded staging fixtures.
5. Sign back in as A and confirm A's retained completed local rows are available only to A. Repository-level row-ID authorization is covered by IP-1.4; installed-device migration and driver behavior remain MC-1.7.
6. Start an A workout and attempt voluntary logout. Verify Stay signed in preserves tracking, Finish & logout saves exactly once before navigation, and Discard & logout explicitly removes the in-memory workout. Confirm timers and the GPS subscription stop in both exit paths.
7. In isolated staging, invoke the invalid-session result through a controlled QA hook/fault injection while A has an active workout; do not assume an arbitrary connected `401/403` naturally reaches this coordinator until IP-2 proves that wiring. Confirm forced authentication loss attempts a local save under A before clearing the session. Inject one local-save failure: account switching must remain blocked behind Retry/Discard, Retry must finish cleanup only after a successful save, and Discard must require an explicit action.
8. Separately hold a native GPS start, workout/image sync, avatar upload, token refresh, and synthetic login/registration response in flight during exit. Confirm new work is rejected, admitted work finishes or shuts down under A before credentials clear, and no late callback can persist or render A/B under the wrong session.
9. Review sanitized release logs and telemetry. They must contain no tokens, passwords, raw profile payloads, local file paths, exact coordinates, route points, or acquisition timestamps.

Pass condition: every exit path ends in one of two explicit outcomes—A remains blocked behind recovery UI, or A's work is drained, local credentials are cleared, and all A state is inaccessible before B activates. Record build, synthetic fixture, staging run, and reviewer references only. This check does not prove server-side revocation (IP-2), local row-ID authorization (IP-1.4), or durable recovery across process death (IP-3).

### MC-1.7 — Android SQLite v5→v6 ownership migration

1. In isolated QA, install the last supported v5-schema release build and seed only synthetic accounts A and B with valid completed workouts, points, status changes, activity-image metadata, and one queued remote deletion. Record safe aggregate counts and a restricted backup reference; never commit the database or route/image values.
2. Upgrade the same installation in place to the reviewed v6 release build. Do not clear app data. Open the app, terminate it normally, restart it twice, and confirm valid A and B history still loads under the correct account.
3. Through a controlled diagnostic build, record only pass/fail and aggregate counts showing `PRAGMA foreign_keys = 1`, an empty `PRAGMA foreign_key_check`, schema version 6, and the reviewed workout/point/status composite indexes with the expected columns, direction, and uniqueness.
4. With seeded known local IDs, confirm B receives no detail/image data and cannot delete, mark synchronized, attach, retry, refresh, or complete a delete queued for A. Repeat the equivalent valid operations as A and confirm normal behavior. Never run destructive cross-account probes against production data.
5. Delete one A-owned local-only workout and verify its point, status, and image database rows cascade while B's rows remain. Separately exercise a queued remote deletion and an image upload/delete held across account exit; completion must stay with A or remain retryable.
6. Exercise a synthetic duplicate `(user_id, client_sync_id)` fixture in an isolated copy. Confirm only one canonical identity is eligible to synchronize, additional rows remain locally quarantined, and conflicting pre-existing remote mappings make the upgrade roll back without advancing `user_version`.
7. Treat v6 as forward-only: do not install a v5 binary over a database already opened by v6. Rehearse restore of the synthetic pre-upgrade backup and the forward-fix path used if migration verification fails.
8. Inspect sanitized logs. Migration output may contain table names and aggregate repair counts only—never user IDs, client IDs, coordinates, route payloads, or image paths.

Pass condition: a supported Android release build upgrades a retained v5 synthetic database to v6, reopens repeatedly with foreign keys and exact indexes intact, preserves valid per-owner data, denies known foreign IDs, proves database cascades, and has a rehearsed backup/forward-fix response. Host FFI tests do not satisfy this device gate. SQLite orphan-image row cleanup can leave app-private files without database paths; durable physical-file cleanup remains an IP-4.6 design item and is not claimed by IP-1.4.

### MC-1.8 — Bounded activity ingest and PATCH history in staging

1. Use an isolated staging deployment, synthetic accounts, and generated routes only. Record build/commit, proxy configuration reference, aggregate point/status counts, response codes, and database count/digest comparisons; never retain raw coordinates, timestamps, request bodies, tokens, or row exports in Git.
2. Configure the edge and application so only `POST /api/activities` and `PATCH /api/activities/:activityId` can accept the reviewed 3 MiB application limit. Keep ordinary JSON routes at 100 KiB. Prove the proxy does not impose a smaller hidden limit and does not broaden large-body acceptance to unrelated endpoints.
3. Confirm from release history that metrics version 2 was not deployed before the IP-1.2 GPS contract. If it was, stop rollout and introduce distinct persisted tracking-policy provenance. With the current supported mobile build, verify activity, location, and status timestamps arrive with UTC offsets. Also sync one synthetic activity from the last supported pre-IP-1.5 client and prove its offset-less timestamps retain the intended interval; keep this backend compatibility path until that client is outside support.
4. From the supported mobile build, sync the reviewed 750-point fixture and a representative multi-hour fixture below 12,000 locations and 1,000 status changes. Confirm one activity is committed per `clientSyncId`, all expected child counts persist, and retries return the same activity rather than duplicating it.
5. Exercise the mobile failure matrix with synthetic responses. `400`, `413`, and `422` must record only a stable reason in the existing `sync_blocked_reason` column, stop retrying that row, and allow later rows to continue. An unknown server code must be reduced to the status-derived fallback rather than persisted. `401`, `403`, `429`, `5xx`, and a network interruption must remain eligible after credential refresh, backoff, or connectivity recovery. Switch accounts before a delayed permanent response and prove no block reason is written into the newly active user's scope and no later row is sent with the prior user's cached headers. UI visibility is not required until IP-4.
6. Send wide unknown-root, deeply nested scalar, and attacker-sized nested-key bodies below 3 MiB, then one maximum-size DTO-invalid fixture whose first location is structurally invalid and one DTO-valid fixture whose 12,000 locations are semantically invalid. Structural preflight must return a small static first-error response without reflecting the long key or reaching the service; the semantic response must contain at most 25 issues with `issuesTruncated: true`. All must remain inside the approved response-size/memory/latency envelope and perform no database write.
7. In the controlled harness, send a body above 3 MiB once with `Content-Length` and once using chunked transfer. Both must return JSON `413` with `ACTIVITY_PAYLOAD_TOO_LARGE`, perform no database write, and stay within the approved memory/latency envelope. Do not run oversized probes against production.
8. Verify an unauthenticated large request returns `401` before activity admission/parsing, then hold one request for the same synthetic user and four requests across distinct users. Confirm the same-user and fifth global requests return retryable `429` with `Retry-After`, do not reach validation/database work, and a released/closed request returns its slot exactly once.
9. Against staging PostgreSQL, seed one activity with known aggregate location/status counts and safe digests. A name-only PATCH must leave both unchanged; explicit `locations: []` and `statusChanges: []` must clear only the named collection while retaining valid aggregates, and a later metric PATCH must not reinterpret a route bridge after status history is gone. A malformed replacement must issue no write, and an injected nested-write failure must roll back the scalar and both collections to their prior digests. From two application processes, submit complementary location/status partial patches against the same starting row; a serialization conflict must retry/revalidate so the final row satisfies the merged contract rather than combining two stale snapshots.
10. Inspect sanitized staging telemetry for `413`, `429`, `400/422`, create/PATCH latency, process memory, bounded issue counts, and database transaction failures. Logs and traces may contain stable error codes, request IDs, sizes, truncation flags, and aggregate counts only—never authorization values, exact route data, timestamps, or request/response bodies.
11. Define rollback before rollout: restore the prior application release if error, latency, or memory thresholds breach, while retaining the 100 KiB ordinary-route cap. If 3 MiB proves unsafe, forward-fix the activity body limit and location/status caps together from measured fixtures; do not silently return to the default 100 KiB failure.

Pass condition: the deployed proxy/application path accepts ordinary long workouts, rejects malformed/oversized/over-complex/over-concurrent activity writes before persistence, preserves omitted PATCH history, rolls back and serializes PostgreSQL replacements, keeps unrelated routes small, proves current-UTC and supported-legacy timestamp behavior, durably classifies mobile retries without cross-account writes, and produces only sanitized operational evidence.
