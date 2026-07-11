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
| MC-0.5 | S3, CloudFront, database TLS, lifecycle, and backup posture | Infrastructure owner | Pending | Restricted configuration review and isolated restore reference | — | — | — |
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

## Hosted CI procedure

### MC-0.7 — Successful backend security workflow

1. Push the reviewed branch and open a pull request through the normal protected path.
2. Confirm the workflow resolves the expected commit SHA and uses the `Backend security` job.
3. Verify the hosted job completes `npm ci --no-audit`, Prisma schema validation, Prisma generation, TypeScript typecheck, and all backend tests. The separately approved advisory submission belongs only to MC-0.10.
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

## Dependency advisory procedure

### MC-0.10 — Dated production scan and triage

1. Obtain explicit approval before sending the dependency inventory to the npm advisory service.
2. From `RythmRun_backend_nodejs`, run `npm audit --omit=dev` and retain the complete dated report in an approved evidence location.
3. For every advisory, record package, installed path, severity, affected range, runtime reachability, chosen fix, owner, and due date.
4. Upgrade or remove reachable vulnerable packages. A suppressed or accepted advisory needs owner approval, reachability evidence, an expiry date, and a tracking reference.
5. Do not reopen affected routes while a reachable critical/high production advisory remains.
6. After remediation, rerun a clean install, Prisma validation/generation, TypeScript typecheck, backend build/tests, and the dated production audit.

Pass condition: no reachable critical/high production advisory remains, and every other result has a reviewed, time-bounded disposition. The 2026-07-10 count of 11 is discovery evidence, not a current result.

## Deployment and incident procedure

### MC-0.1 through MC-0.6 — Containment before rollout

1. Keep registration/profile/avatar paths restricted until containment is independently verified.
2. Preserve the relevant log window and database snapshot before cleanup; never copy raw evidence into Git.
3. Classify unsafe legacy avatar values using a reversible migration after a backup is verified.
4. If exposure cannot be excluded, rotate JWT, refresh/session, database, AWS, and CDN material in an order that keeps replacement credentials working before old credentials are revoked.
5. Verify S3 public-access block, object ownership, encryption, origin controls, abandoned-object lifecycle, database TLS, backup retention, and an isolated restore.
6. Confirm the deployment host uses Node.js 22.x, then deploy only to isolated staging with non-production credentials and sanitized or synthetic data before any production reopen.

Pass condition: each row has a restricted evidence reference, dated owner sign-off, independent reviewer, and a tested containment/rollback response.

### MC-0.11 and MC-0.12 — Staged lifecycle and controlled reopen

1. Exercise the supported Flutter build through avatar request, multipart upload, confirmation, display, replacement, and logout in isolated staging.
2. Verify safe request IDs/error categories and confirm logs contain no secrets, signed URLs, raw object keys beyond operational need, filesystem paths, response bodies, or exact routes.
3. Reopen registration/profile text paths first and avatar request/confirm only after storage policy, quota, intent, and cleanup checks pass.
4. Define rollback thresholds for `4xx`, `5xx`, avatar-confirm, storage rejection, and S3 errors before reopening.
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
