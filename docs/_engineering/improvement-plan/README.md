---
published: false
---

# RythmRun improvement program

This directory turns the repository audit dated 2026-07-10 into an
implementation program: six phases (`IP-0`…`IP-5`), the decisions behind them,
and the evidence required to call anything done. The audit used "phase" for its
review categories; `IP-` identifiers exist to avoid confusing the two.

These files are `published: false` because `docs/` is also the GitHub Pages
policy site. They are engineering source documents, not public policy pages.
**They are still non-confidential** — `published: false` stops Pages rendering,
it does not make raw repository files private. Keep active incident detail and
sensitive evidence in an access-controlled tracker, never here.

## Where to look

| I want to know… | Read |
| --- | --- |
| What do *I* need to do? | **[ACTION-REQUIRED.md](./ACTION-REQUIRED.md)** — everything blocked on production access, a device, a provider account, or a GitHub setting. Delete an item when it's done. |
| Where does the program stand? | **[STATUS.md](./STATUS.md)** — phase status, what's left per package, audit-finding traceability, delivery history. |
| How do I work in this program? | This file — rules, decisions, definition of done, verification commands. |
| What exactly does phase *N* require? | The phase file. Delivered packages keep only their evidence log; unbuilt packages keep their full spec. |

Phase files: [IP-0 security containment](./IP-0-security-containment.md) ·
[IP-1 tracking correctness](./IP-1-tracking-correctness.md) ·
[IP-2 auth, account, privacy](./IP-2-auth-account-privacy.md) ·
[IP-3 workout durability](./IP-3-workout-durability.md) ·
[IP-4 sync & restore](./IP-4-sync-data-restore.md) ·
[IP-5 release readiness](./IP-5-release-retention.md)

## Immediate warning

**IP-0 is a release blocker, and its blocking work is operational, not code.**
The deployed backend must be treated as potentially exposed until the
profile-path vulnerability is contained, suspicious access is investigated, and
potentially exposed credentials are rotated — or exposure is confidently ruled
out. Merging code and passing local tests did none of those things.

## Product direction

A privacy-first, offline-reliable GPS workout and photo journal for Android. The
program optimizes for user trust in this order:

1. The service cannot expose files, secrets, or exact routes unexpectedly.
2. Recorded metrics are correct.
3. One account cannot see or mutate another account's local state.
4. A workout survives pause, screen-off operation, process death, and poor
   connectivity.
5. Completed workouts visibly sync, restore on a new device, and delete
   consistently.
6. Releases are measurable and repeatable before retention features are
   expanded.

## Phase intent and dependencies

| Phase | Priority | Intended outcome | Depends on |
| --- | --- | --- | --- |
| IP-0 | P0 | Contain arbitrary file access, fail closed on secrets, harden the single avatar path, complete exposure response | Production, log, database, R2, CDN, and secret-store access |
| IP-1 | P1 | Trustworthy metrics, pause/outlier semantics, per-user local access, working cascades, minimum CI | IP-0 code deployed, containment maintained |
| IP-2 | P1 | One working refresh contract, secure token storage, revocation, account basics, safe route visibility | IP-1 user-isolation rules and minimum CI |
| IP-3 | P1 | Checkpoint and recover active workouts; prove Android screen-off tracking | IP-1 metric state machine; IP-2.1–2.3 identity/offline core |
| IP-4 | P1/P2 | Bounded resumable sync, lightweight reads, visible status, indexed data, cross-device restore | IP-2 refresh; IP-3 durable local state |
| IP-5 | P2 | Mature staging, observability, release evidence, platform scope, documentation | Exit gates for IP-0 through IP-4 |

Phases are ordered by risk and dependency, not by ease. Work inside a phase may
run in parallel when the phase document says so, but a later phase must never
delay a safety fix in an earlier one.

**Parallel work is allowed; parallel *enablement* is not.** IP-3.1/3.2
checkpoint-engine development may start alongside later IP-2 account work, but
user rollout still waits on IP-2.1–2.3 identity rules and the IP-2.7 approved
at-rest format. IP-5 release controls can be prepared early; the formal gate
still follows IP-0–IP-4. The maintainer explicitly selected repository-only
IP-1/IP-2 development while IP-0 operational work remains manual — that
exception permits local code and tests only.

## What remains unchanged

- Keep Flutter, Riverpod, Express, Prisma, PostgreSQL, SQLite, and Cloudflare R2
  through its S3-compatible API.
- Keep the backend as a modular monolith.
- Keep local-first workout completion.
- Preserve `(userId, clientSyncId)` idempotency.
- Preserve queued remote workout deletion.
- Preserve the activity-image upload/retry/replace/delete state machine.
- Keep direct-to-R2 upload and the reviewed signed-read contracts.
- Keep history list payloads lightweight; load route points only for details.
- Do not introduce Redis, Kafka, Kubernetes, microservices, event streaming, or
  generalized AI infrastructure without measured evidence that a completed phase
  cannot meet its target without them.

## Program rules

1. Read this file and the active phase file completely before changing code.
2. Take the lowest-numbered unblocked work package unless the phase identifies
   concurrent work or the maintainer selects otherwise.
3. Reproduce or encode the failure before changing behavior wherever safe. Never
   attempt exploit verification against production.
4. One work package (or one tightly coupled set) per pull request.
5. Add focused tests in the same change as the behavior. Manual-only proof is
   acceptable only where the phase explicitly calls for device or infrastructure
   evidence.
6. Preserve unrelated worktree changes. Do not reformat or refactor unrelated
   files.
7. Include migration, rollout, rollback, privacy, and compatibility effects in
   the handoff.
8. Record evidence in the phase file; update status only after the exit gate
   passes. Unchecked exit criteria are incomplete work — a passing happy path is
   not a completed phase.
9. Never place production secrets, tokens, exact user routes, raw coordinates,
   or incident log extracts in the repository.

## Status vocabulary

`Planned` sequenced but not started · `In progress` at least one package is
actively being implemented · `Blocked` external access or a decision prevents
progress · `Verification` implementation complete, exit checks remain ·
`Complete` every exit criterion passed with linked evidence · `Deferred`
deliberately removed with a reason.

## Global definition of done

- Code, tests, migrations, configuration examples, and user-facing behavior
  agree.
- Negative and failure-path tests exist for the risk being fixed.
- Backend and Flutter suites pass; TypeScript type checking passes.
- The Flutter analyzer introduces no new warnings or errors, and the counted
  informational baseline does not grow.
- Forward migration and rollback have been exercised on non-production data.
- Observability logs no tokens, passwords, secrets, exact routes, raw
  coordinates, or private file paths.
- Deployment order and rollback trigger are written down.
- Compatibility with at least the previous supported mobile version is proven,
  or intentionally rejected with a forced-upgrade plan.
- The phase evidence log has a dated entry (CI run, test report, staging run,
  query plan, or ticket reference). A commit hash alone is not evidence.

## Standard verification commands

```bash
cd RythmRun_backend_nodejs
npm ci --no-audit
npx --no-install prisma validate
npx --no-install prisma generate
npm run typecheck
npm test -- --ci --runInBand
npm run build
npm run smoke:runtime
```

```bash
cd rythmrun_frontend_flutter
flutter pub get --enforce-lockfile
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos
dart analyze --format machine > /tmp/rythmrun-analyzer.machine
dart run tool/ci/analyzer_baseline.dart check \
  --input /tmp/rythmrun-analyzer.machine \
  --baseline tool/ci/analyzer_baseline.json \
  --repository-root .. \
  --package-root .
```

The baseline comparator refuses to run on a toolchain other than the one it was
stamped with (currently Flutter 3.44.1 / Dart 3.12.1, matching CI). On a newer
local SDK it exits with a mismatch error by design — the raw analyzer result is
still reproducible, the counted comparison is not.

Dependency review is MC-0.10 in [ACTION-REQUIRED.md](./ACTION-REQUIRED.md). Run
the outbound command only after explicit approval:

```bash
cd RythmRun_backend_nodejs
npm audit --omit=dev
```

## Evidence format

Each phase file ends with a table:

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| YYYY-MM-DD | IP-x.y | PR/commit, CI URL, staging run, or ticket reference | Pass/Fail | No secrets or personal data |

Append evidence; never overwrite a failed attempt.

## Decisions already made

| ID | Decision | Reason |
| --- | --- | --- |
| D-001 | Security containment is the current phase. | It is the only confirmed P0 and can expose files or credentials. |
| D-002 | Use `IP-0` through `IP-5` for implementation planning. | The audit already labels its review sections as phases. |
| D-003 | Canonical workout units are meters, seconds, and meters/second; presentation converts at the boundary. | GPS speed and the existing entity contract are already m/s, and this avoids double conversion. |
| D-004 | Completed local workouts stay local-first and are retained per account across logout, but all reads and mutations must be user-scoped. | Offline history is core product value; access isolation is mandatory. Account deletion must purge local and remote data. |
| D-005 | The Cloudflare R2 avatar pipeline is the target; the local filesystem pipeline is retired after a controlled compatibility window. | Two pipelines create conflicting security and lifecycle behavior. |
| D-006 | New activities default to private. Public sharing requires an explicit privacy model and route redaction. | Exact GPS start/end points are sensitive. |
| D-007 | Social work stays disabled until authentication, privacy, moderation, and route visibility are complete. | Current social routes are broken and there is no frontend journey. |
| D-008 | Android is the only promised platform until IP-5 either proves iOS readiness or explicitly excludes it. | iOS lacks required photo, AdMob, and background configuration. |
| D-009 | Offline local access lasts at most seven days from a successful server verification, limited to the verified user's local data. | Preserves offline value without treating a stale local identity as indefinite server authorization. Clock rollback forces online verification. |
| D-010 | Access tokens carry a session ID and authenticated requests verify the session is still active. | Logout, password change, and account revocation must take effect before natural token expiry. |
| D-011 | Voluntary logout during an active workout requires Finish or Discard; forced authentication loss attempts local finalization and blocks cleanup on a failed save; cross-user authentication is rejected until the prior user's live, sync, profile, and auth work drains. | Tracking and late callbacks must never continue silently or move state to another account. |
| D-012 | For a same-user `client_sync_id` collision, retain one deterministic canonical row and quarantine the others from sync; if they already map to different remote activities, fail and roll back the migration. | A new uploadable ID could create a second remote activity after a lost response. Quarantine preserves local data while failing closed on remote ambiguity. |
| D-013 | Keep backend and Flutter CI as separate required checks; pin runners, toolchains, and action commits; baseline informational analyzer findings as a counted multiset while warnings and errors stay fatal. | Separate stable names preserve branch-protection evidence, and counted fingerprints stop line movement or duplicate lints from bypassing the gate. |
| D-014 | Run the backend on exact Prisma 7.8 with the `prisma-client` generator, PostgreSQL driver adapter, one DI-owned client/pool, and native NodeNext ESM. | The dependency-only Prisma 7 update could not validate against the Prisma 6 model. Completing the migration removes the hidden local-client dependency while keeping PostgreSQL. |
| D-015 | Refresh sessions have a seven-day absolute lifetime and a five-session cap; a sixth revokes the least-recently-used. Legacy refresh rows are dropped, not backfilled. | Rotation must not extend the compromise window, login must stay usable at the cap, and legacy JWTs lack the claims for a safe migration. The cutover intentionally forces one sign-in. |
| D-016 | Store the mobile access/refresh pair as one versioned secure-storage envelope; treat its revision as the credential generation; require server verification before a migrated pair gains offline eligibility; durably quarantine a rejected revision before user-scope recovery. | Atomic pair writes and exact-revision deletion prevent split credentials, refresh races, stale-session offline re-entry, and deletion of a newer login. Android application backup is disabled pending IP-2.7. |
| D-017 *(amended 2026-07-20)* | Google authentication exchanges only a provider-verified ID token, keys accounts by Google's stable subject, and issues the same bounded RythmRun session as password login. It links onto an existing account **only** when that account's email is verified and it is not already linked, via a race-safe update plus revocation of its other sessions; every other collision is refused with `AUTH_EMAIL_UNVERIFIED_CONFLICT` (409). | A *verified* email proven on both sides is safe linking proof; email alone is not — the original "never link" rule over-corrected. One session contract preserves revocation, secure storage, offline policy, and teardown. |
| D-018 | Email verification uses a single-use, SHA-256-digest-at-rest token sent through one optional, feature-flagged provider (**Brevo** free SMTP relay; sender domain **reshapeapp.ai**). `register()` never verifies; the link is sent post-commit best-effort. The migration backfills `emailVerified=true` **only** where `googleSubject IS NOT NULL`. The Flutter `emailVerified` defaults to `true` as a deliberate fail-open presentation choice — the server alone gates linking. | Verification is the prerequisite that makes D-017's auto-link safe. Digest-at-rest and never logging the token let password recovery reuse the same primitives. Blanket-verifying password accounts would reopen the takeover window the gate exists to close. |

## Decisions that still require an owner

| Needed by | Decision | Recommended default |
| --- | --- | --- |
| IP-2 | Device location/photo protection at rest | Approve library, performance, and backup recovery first; prefer per-user data keys wrapped by the platform keystore, encrypted DB and files, and exclusion from unencrypted backups. |
| IP-2.4 | Account-deletion retention and reauthentication | Password accounts re-enter the password; Google-only accounts present a fresh provider assertion the backend re-verifies. Decide retention before building the cleanup outbox. |
| IP-4 | Cross-device conflict policy | A remote tombstone auto-deletes only a locally proven previously-synced identity; an unsynced collision is quarantined, not erased. Ask the user only for true editable journal conflicts. |
| IP-5 | iOS release commitment | Keep the release Android-only unless real-device background and image/ads checks pass. |
| IP-5 | Crash/metrics vendor and retention | The smallest provider that supports redaction, regional requirements, and short retention. |

## Deferred backlog

Real findings that intentionally do not outrank the trust program:

- Social feed, likes, comments, discovery, friend journeys.
- Cadence, music, rhythm coaching, wearables, health-platform integration. The
  [Samsung Health](../../samsung-health-integration-plan.md) and
  [Strava](../../strava-integration-plan.md) documents are design artifacts
  only — they do not authorize implementation or supersede lower-numbered
  security, deletion, privacy, or durability work.
- AI-generated summaries.
- Offline map tile caching.
- Banner-ad expansion.
- Broad file/module restructuring not needed for a phase task.
- Cursor pagination, larger IDs, or partitioning until IP-4 measurements justify
  them.
- General analyzer cleanup beyond release-blocking or touched-code findings.

## Plan maintenance

1. Update the phase file first — it is canonical. Then update
   [STATUS.md](./STATUS.md).
2. Append evidence; never overwrite a failed attempt.
3. Add or amend a decision when behavior or scope changes.
4. Move newly discovered work to the earliest phase whose exit condition depends
   on it.
5. **If the plan and the code disagree, the code is current behavior.** Update
   the plan in the same change. Never claim unverified behavior in
   documentation.
6. When a delivered package's step-by-step is no longer needed, delete it and
   keep the evidence log. Git history holds the rest.
