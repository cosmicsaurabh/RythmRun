---
published: false
---

# RythmRun improvement program

> Program status: IP-0 remains the release blocker and its operational evidence is still open. The maintainer has explicitly selected repository-only IP-2 work in parallel. IP-2.4 remains the current canonical package: profile edit and password recovery are now delivered, leaving account deletion as the last IP-2.4 slice, pending its retention/reauthentication decision gate. Password recovery is repository-delivered on branch `feat/email-verification` (backend `34a14a9` + frontend `6b7dc97`), reusing IP-2.9's hashed token/email plumbing; its production exposure is gated by MC-2.5 and address-dimension rate limits remain IP-2.6. If the deletion decision is unavailable, IP-2.5 is the next implementable package. A separately selected Google identity extension is merged, and a further IP-2.9 email-verification/safe-linking extension is repository-delivered on the same branch (PR pending); both still require provider, migration, device, and staging proof; none of this authorizes migration execution, deployment, or production enablement.

This directory turns the repository audit dated 2026-07-10 into an implementation-ready hardening program. It is the canonical place to track the current improvement phase, the next five phases, their decisions, and the evidence required to mark work complete.

These files use `published: false` because `docs/` is also the GitHub Pages policy site. They are engineering source documents, not public policy pages. Do not add secrets or private incident evidence: the repository contents may still be visible even when GitHub Pages does not render them.

This plan is now part of repository history and must be treated as non-confidential. Keep active incident detail and sensitive evidence in an access-controlled tracker. `published: false` and the `_engineering` directory prevent normal Pages rendering; they do not make raw repository files confidential.

The audit used the word "phase" for review categories. This program uses `IP` (Improvement Phase) identifiers to avoid confusing audit sections with implementation work.

## Immediate warning

`IP-0` is the current phase and is a release blocker. The deployed backend must be treated as potentially exposed until the profile-path vulnerability is contained, suspicious access is investigated, and potentially exposed credentials are rotated or exposure is confidently ruled out.

The first code-remediation slice, commit `e33f314`, is merged into `origin/main` through merge commit `54a5b26`. It has not been deployed or exercised against staging/production. Merging code and passing local tests did **not** restrict production, inspect production logs, rotate credentials, apply the migration, configure bucket lifecycle, or prove the deployed service safe. Those actions require deployment and secret-management access and must begin before normal feature work.

## Selected work now

- **Human-operated first action:** IP-0.1 — contain the affected production routes and preserve evidence.
- **Merged code delivery:** IP-0.2 through IP-0.5 profile/avatar/configuration hardening and its local automated suite are in `origin/main` via `e33f314`/`54a5b26`; they are not deployed or production-verified.
- **Repository-delivered; hosted verification pending:** IP-0.7a Express HTTP security regressions and minimum backend CI are committed in `c52fb87`; MC-0.7 through MC-0.9 remain open.
- **Repository-delivered; advisory verification pending:** IP-0.7 dependency-surface reduction is committed in `fc33dca`; MC-0.10 remains open and no current advisory-clean claim is made.
- **Repository-delivered; rollout pending:** IP-1.1 canonical metric contracts and provenance are committed in `ba7b288`; production sampling, backup, rollout, and compatibility remain MC-1.1 through MC-1.4.
- **Repository-delivered; device verification pending:** IP-1.2 one GPS acceptance policy, deterministic pause timeline, provider-owned route, and map/elevation segmentation is committed in `c41d3dc`; MC-1.5 remains open.
- **Repository-delivered; device/staging verification pending:** IP-1.3 explicit nullable-state clearing, serialized live/auth operations, restart-safe credential cleanup, active-workout exit decisions, and A→B cache isolation is committed in `06369b7`. MC-1.6 remains open.
- **Repository-delivered; device/hosted verification pending:** IP-1.4 owner-bound local workout/image access plus SQLite v6 foreign-key, orphan-repair, duplicate-quarantine, cascade, and index enforcement is committed in `a976f4c`. MC-1.7 Android in-place migration proof and MC-1.9 hosted FFI execution remain open.
- **Repository-delivered; staging verification pending:** IP-1.5 preserves omitted PATCH history, serializes conflicting partial PATCH merges, bounds nested workout validation and error output, and gives only authenticated activity create/PATCH routes a measured 3 MiB parser behind interim per-user/process admission. The mobile client emits UTC timestamps and durably stops retrying permanent `400`/`413`/`422` activity rejections. Repository delivery is committed in `d2c1b95`; MC-1.8 still owns deployed proxy, resource, PostgreSQL, compatibility, and telemetry proof.
- **Repository-delivered; hosted verification pending:** IP-1.6 preserves the stable `Backend security` check and completes the Prisma 7.8/NodeNext ESM and pinned Flutter CI modernization. Its committed local evidence remains valid; hosted, real-database, deployment, and device evidence remains in the applicable manual checks.
- **Repository-delivered; packaged-device verification pending:** IP-1.7 makes advertising fail closed by default, keeps non-production and ads-disabled releases on the no-op provider, validates production IDs before packaging, and places the only configurable ad opportunity after durable workout completion. MC-1.14 remains open, and IP-5.5 still owns consent, approved placement, live IDs, and production enablement.
- **Repository-delivered; hosted/staging verification pending:** IP-2.1 is committed in `d8f6a9f`. It replaces plaintext backend refresh rows with digest-only bounded sessions, standard claims, serializable rotation/replay revocation, active-session access checks, presented-session logout, all-session password revocation, and safe `/users/me`. MC-2.1 and MC-2.2 remain open.
- **Repository-delivered; device verification pending:** IP-2.2 moves the mobile access/refresh pair into one read-back-verified secure-storage envelope using stable `flutter_secure_storage` 10.3.1, safely migrates coherent IP-2.1 preference pairs, centralizes revision-safe single-flight refresh/replay, quarantines rejected/password-revoked sessions before teardown, distinguishes invalid sessions from network unavailability, removes raw-token APIs, guards the production `/home` route, and normalizes login/registration to one authenticated root. The locked restore, 275-test Flutter suite, 10-information/zero-warning/zero-error analyzer result and baseline check, and Android debug APK build pass locally. MC-2.3 still owns physical-device storage, upgrade-interruption, backup/restore, sanitized-log, and staging lifecycle proof.
- **Repository-delivered; device verification pending:** IP-2.3 defines offline-session behavior: it anchors offline admission to an integrity-sensitive `lastVerifiedAtMs` inside the secure envelope, bounds it to seven days from a successful server verification, fails closed on clock rollback below a persisted observed high-water mark, a future-dated verification, or a window overrun without deleting completed local data, and adds a data-layer `OnlineOperationGuard` that denies server mutations (password change, avatar upload, coordinated sync) in offline mode beneath the presentation `FeatureGate`. The startup state machine keeps its five documented branches and reuses IP-1.4 owner-scoped queries. The locked restore, 291-test Flutter suite, 10-information/zero-warning/zero-error analyzer result and baseline check, formatting, Android debug APK build, and an independent adversarial multi-agent review (two confirmed medium clock-observation defects fixed and retested) pass locally. MC-2.3 still owns physical-device offline/rollback, airplane-mode-versus-revocation, backup, and sanitized-log proof; defeating a fully attacker-controlled device clock is future platform-monotonic/server hardening.
- **Current canonical package; delivered in slices:** IP-2.4 profile edit is repository-delivered: `PUT /profile` returns the updated safe `/me`-shaped user with unchanged mass-assignment rejection, and the mobile app gains the name-edit flow that commits only server-confirmed, same-owner first/last name through the authenticated coordinator, denied offline by the IP-2.3 guard. Password recovery is now repository-delivered too (branch `feat/email-verification`, backend `34a14a9` + frontend `6b7dc97`): an anti-enumerating request endpoint, a one-transaction single-use reset that revokes all sessions and refuses Google-only accounts, a deep-link-free backend web form, and a Flutter forgot-password screen — reusing IP-2.9's hashed-token store. Its production exposure is gated by MC-2.5 and address-dimension rate limits remain IP-2.6. Account deletion with a durable object-cleanup outbox and runner is the last IP-2.4 slice, selected next after its retention/reauthentication decision gate. If that decision is unavailable, proceed to IP-2.5 without claiming IP-2.4 complete. The recovery/edit/delete audit finding remains open until account deletion and all three slices' MC-level proof land.
- **Repository-delivered identity extension; operational verification pending:** Google Sign-In is merged into `origin/main` through `c805f62`. The backend verifies Google ID tokens against the configured web-client audience, requires verified email, keys identity by stable provider subject, refuses implicit email linking (on `origin/main`; the branch-pending IP-2.9 narrows this to auto-link a **verified**-email account only — see D-017/D-018), and issues the existing revocable RythmRun session. Flutter uses the Google Sign-In 7.2 API, refuses cleartext exchange, serializes chooser/sign-out work with account teardown, and normalizes success through the same session root as password login. On Node 22.22.3, Prisma validation, typecheck, 307 executable Jest tests with seven PostgreSQL tests skipped locally, production build, and built runtime smoke pass; locked Flutter restore, 330/330 tests, 9 informational findings with zero warnings/errors, counted baseline, formatting, and Android debug APK also pass. MC-2.4 owns the non-rolling migration, OAuth-console/signing, provider, device, staging, branding, and optional-iOS proof.
- **Manual/hosted gates:** use [MANUAL-CHECKS.md](./MANUAL-CHECKS.md) for hosted CI, intentional-failure, branch-protection, dependency-audit, deployment, incident, infrastructure, staging, and controlled-reopen evidence. MC-1.9 through MC-1.11 keep Flutter/required-check evidence separate from repository delivery; MC-1.12 through MC-1.14 own database/deployment/ad-device proof; MC-2.1 through MC-2.5 own the hosted auth transaction, destructive server cutovers, mobile secure-storage lifecycle, Google identity-provider/device, and email-verification provider/delivery/device gates.
- **Concurrent owner action:** IP-0.6 — determine exposure and rotate/revoke credentials when it cannot be excluded.

For subsequent work, take the lowest-numbered unblocked work package in the current phase. A maintainer may combine tightly coupled packages, but must not mark either complete until both sets of acceptance criteria pass. See [audit finding traceability](./AUDIT-TRACEABILITY.md) for the complete mapping.

### Next five repository steps

1. **IP-2.4 account deletion:** decide retention and password-versus-fresh-Google reauthentication, then add transactional session revocation, durable object-cleanup outbox/runner, remote deletion state, and complete local database/file/key purge. This is now the last undelivered IP-2.4 slice — password recovery has been delivered on branch `feat/email-verification` (reset endpoints + Flutter UI, reusing the IP-2.9 token/email primitives); its production exposure is gated by MC-2.5.
2. **IP-2.5 route privacy:** migrate activities private, make exact route/image detail owner-only, and unmount unfinished friend/comment/like paths.
3. **IP-2.6 abuse and upload controls:** deploy an explicit CORS/proxy contract, rate-limit auth/account routes including Google exchange, finish typed error mapping, and enforce actual storage size/type/integrity plus abandoned-upload cleanup.
4. **IP-2.7 retained-data protection:** complete the threat-model/library/performance design gate, then migrate SQLite routes and activity photos to approved user-scoped at-rest protection with backup/key-loss recovery.
5. **IP-3.1 durable checkpoint engine:** begin schema/engine development and dev/test checkpoint persistence behind a disabled-by-default feature flag in parallel with later account work. Do not enable persistence for user data or release the feature until the IP-2.7 design gate approves its at-rest format, key handling, backup behavior, and recovery limits.

MC-2.4 Google provider/migration/device proof and the older pending MC rows proceed in parallel but are not substitutes for these repository packages. The Samsung Health and Strava documents remain deferred design work.

## Product direction

The near-term product is a privacy-first, offline-reliable GPS workout and photo journal for Android. The program optimizes for user trust in this order:

1. The service cannot expose files, secrets, or exact routes unexpectedly.
2. Recorded metrics are correct.
3. One account cannot see or mutate another account's local state.
4. A workout survives pause, screen-off operation, process death, and poor connectivity.
5. Completed workouts visibly sync, restore on a new device, and delete consistently.
6. Releases are measurable and repeatable before retention features are expanded.

## Phase roadmap

| Phase | Status | Priority | Intended outcome | Depends on |
| --- | --- | --- | --- | --- |
| [IP-0: Security containment](./IP-0-security-containment.md) | **In progress** | P0 | Contain arbitrary file access, fail closed on secrets, harden the single avatar path, and complete exposure response | Production, log, database, AWS, CDN, and secret-store access |
| [IP-1: Tracking correctness and local integrity](./IP-1-tracking-correctness.md) | **Verification** | P1 | Trustworthy metrics, pause/outlier semantics, per-user local access, working cascades, and minimum CI | Repository packages delivered; hosted, device, staging, rollout, and operational evidence remains open |
| [IP-2: Authentication, account, and privacy](./IP-2-auth-account-privacy.md) | **In progress** | P1 | One working refresh contract, secure token storage, revocation, account basics, and safe route visibility | IP-1 user isolation rules and minimum CI |
| [IP-3: Workout durability](./IP-3-workout-durability.md) | Planned | P1 | Checkpoint/recover active workouts and prove Android screen-off tracking | IP-1 metric state machine; IP-2.1–IP-2.3 identity/offline-session core gate |
| [IP-4: Sync, data contracts, and restore](./IP-4-sync-data-restore.md) | Planned | P1/P2 | Bounded resumable sync, lightweight API reads, visible status, indexed data, and cross-device restore | IP-2 refresh; IP-3 durable local state |
| [IP-5: Release readiness; retention follow-on](./IP-5-release-retention.md) | Planned | P2 | Mature staging, observability, release evidence, platform scope, and documentation; specify a separate post-gate journal epic | Exit gates for IP-0 through IP-4 |

Phases are ordered by risk and dependency, not by ease. Work inside a phase may run in parallel when the phase document says so, but a later phase must not delay a safety fix in an earlier phase.

## Parallel dependency matrix

| Workstream | May start after | Must wait before production enablement |
| --- | --- | --- |
| IP-0 containment, isolated staging, code fix, and incident response | Immediately, in parallel | All IP-0 exit gates before affected routes reopen |
| IP-1 metric/local-integrity packages | IP-0 code deployed and containment maintained | IP-1 migrations/tests for each changed behavior |
| IP-2.1–IP-2.3 auth/session core | IP-1 user-scope rules and minimum CI | Rotation, secure storage, offline-policy gates |
| IP-3.1–IP-3.2 checkpoint engine/schema development | IP-1 metric engine; can run alongside later IP-2 account work | IP-2.1–IP-2.3 identity rules and IP-2.7 approved checkpoint-at-rest protection before user rollout |
| IP-3 recovery/background integration | Checkpoint engine plus IP-2.1–IP-2.3 | Physical-device and process-kill gates |
| IP-4.3/IP-4.4 summary/index work | IP-1 backend/local contract fixes | Privacy and compatibility contract tests |
| IP-4 upload/restore/tombstone work | IP-2 auth/privacy core and IP-3 stable sequences/finalization | Full IP-4 conflict, restore, and failure gates |
| IP-5 release controls | Can be prepared earlier; formal gate follows IP-0–IP-4 | No P0/P1 waiver for release |

External email or later account features must not delay checkpoint-engine development. Conversely, parallel development is not permission to enable a feature before its production dependency gates pass.

The maintainer explicitly selected IP-1 repository development on 2026-07-11 while IP-0 operational work remains manual. This exception permits local code/tests only; the dependency matrix still controls migrations, deployment, and user rollout.

## What remains unchanged

- Keep Flutter, Riverpod, Express, Prisma, PostgreSQL, SQLite, and Cloudflare R2 through its S3-compatible API.
- Keep the backend as a modular monolith.
- Keep local-first workout completion.
- Preserve `(userId, clientSyncId)` idempotency.
- Preserve queued remote workout deletion.
- Preserve the activity-image upload/retry/replace/delete state machine.
- Keep direct-to-R2 upload and the reviewed public/signed read contracts after hardening them.
- Keep history list payloads lightweight and load route points only for details.
- Do not introduce Redis, Kafka, Kubernetes, microservices, event streaming, or generalized AI infrastructure without measured evidence that a completed phase cannot meet its target without them.

## Program rules for implementing agents

1. Read this file and the active phase file completely before changing code.
2. Confirm the phase status is `CURRENT` or that the maintainer explicitly selected the task.
3. Select the lowest-numbered unblocked work package unless the phase explicitly identifies concurrent human/agent work.
4. Reproduce or encode the failure before changing behavior wherever safe. Never attempt exploit verification against production.
5. Implement one work package or one tightly coupled dependency set per pull request.
6. Add focused tests in the same change as the behavior. A manual-only test is acceptable only when automation is infeasible and the phase document explicitly calls for device or infrastructure evidence.
7. Preserve existing unrelated worktree changes. Do not reformat or refactor unrelated files.
8. Include migration, rollout, rollback, privacy, and compatibility effects in the handoff.
9. Record evidence in the phase file and update the phase table only after its exit gate passes.
10. Treat unchecked exit criteria as incomplete work; a passing happy-path test alone does not complete a phase.
11. Do not place production secrets, tokens, exact user routes, raw coordinates, or incident log extracts in the repository.

## Status vocabulary

Use only these values in the roadmap and phase headers:

- `Planned`: sequenced but not started.
- `Current — not implemented`: selected next, with no claim of remediation.
- `In progress`: at least one work package is actively being implemented.
- `Blocked`: external access or an explicit decision prevents progress; document the blocker and owner.
- `Verification`: implementation is complete but one or more exit checks remain.
- `Complete`: every exit criterion passed and evidence is linked.
- `Deferred`: deliberately removed from the active program with a reason.

## Global definition of done

Every phase must meet all applicable conditions:

- Code, tests, migrations, configuration examples, and user-facing behavior agree.
- Negative and failure-path tests exist for the risk being fixed.
- Existing backend and Flutter test suites pass.
- TypeScript type checking passes.
- Flutter analyzer results introduce no new warnings or errors; the known baseline must be recorded until the backlog is cleared.
- Forward migration and rollback/compensation have been exercised on non-production data.
- Observability does not log tokens, passwords, raw secrets, exact routes, raw coordinates, or private file paths.
- Deployment order and rollback trigger are written down.
- Compatibility with at least the previous supported mobile version is either proven or intentionally rejected with a forced-upgrade plan.
- The phase exit matrix contains dated evidence (CI run, test report, staging run, query plan, or incident ticket reference).

## Standard verification commands

Run from the repository root unless a phase adds more specific commands.

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

For dependency review, use MC-0.10 in the [manual verification register](./MANUAL-CHECKS.md). Run the outbound command only after explicit approval, record the date and full report in the approved evidence location, and do not silently accept advisories:

```bash
cd RythmRun_backend_nodejs
npm audit --omit=dev
```

The audit baseline on 2026-07-10 was 25 backend tests passing, TypeScript passing, 15 Flutter tests passing, and 159 Flutter analyzer findings (6 warnings and 153 informational findings). IP-1.6 reduced that to 20 informational findings and zero warnings/errors; IP-2.2 reduced it to 10, and the merged Google identity tree is locally at 9 informational findings and zero warnings/errors. The current suites contain 330 Flutter tests and 314 backend tests, of which 307 execute locally while seven real-PostgreSQL tests remain intentionally gated. The committed multiset baseline prevents increases but does not make the remaining findings acceptable forever.

## Required evidence format

At the bottom of each phase file, maintain a table like this:

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| YYYY-MM-DD | IP-x.y | PR/commit, CI URL, staging run, or ticket reference | Pass/Fail | No secrets or personal data |

Do not mark a phase complete using only a commit hash. Include the test or operational result that demonstrates the exit condition.

## Decisions already made

| ID | Decision | Reason |
| --- | --- | --- |
| D-001 | Security containment is the current phase. | It is the only confirmed P0 and can expose files or credentials. |
| D-002 | Use `IP-0` through `IP-5` for implementation planning. | The audit already labels its review sections as phases. |
| D-003 | Canonical workout units will be meters, seconds, and meters/second; presentation converts at the boundary. | GPS speed and the existing entity contract are already expressed as m/s, and this avoids double conversion. |
| D-004 | Completed local workouts remain local-first and are retained per account across logout, but all reads/mutations must be user-scoped. | Offline history is core product value; access isolation is mandatory. Account deletion must purge the user's local and remote data. |
| D-005 | The Cloudflare R2 avatar pipeline is the target implementation; the local filesystem avatar pipeline is retired after a controlled compatibility window. | Two pipelines create conflicting security and lifecycle behavior. |
| D-006 | New activities default to private. Public sharing requires an explicit privacy model and route redaction. | Exact GPS start/end points are sensitive. |
| D-007 | Social work remains disabled/deferred until authentication, privacy, moderation, and route visibility are complete. | Current social routes are broken and there is no frontend journey. |
| D-008 | Android is the only promised platform until IP-5 either proves iOS readiness or explicitly keeps iOS out of release scope. | iOS currently lacks required photo, AdMob, and background behavior configuration. |
| D-009 | Offline local access lasts at most seven days from a successful server verification and is limited to the verified user's local data. | It preserves offline value without treating a stale local identity as indefinite server authorization. Clock rollback triggers conservative online verification. |
| D-010 | Access tokens include a session ID and authenticated requests verify that the session remains active. | Logout/password/account revocation must take effect before natural access-token expiry at current MVP scale. |
| D-011 | Voluntary logout/account switch requires Finish or Discard while a workout is active; forced authentication loss attempts local finalization and blocks cleanup on failed save/GPS shutdown until recovery; direct cross-user authentication is rejected until prior-user live, sync, profile, and auth work drains and durable credentials clear. | Tracking and late callbacks must never continue silently or move state to another account. Durable process-death recovery remains IP-3. |
| D-012 | For an exact same-user `client_sync_id` collision, retain one deterministic canonical row and quarantine additional local rows from synchronization; if the rows already map to different remote activities, fail and roll back the migration. Never turn an ambiguous duplicate into a new uploadable identity. | A new uploadable ID could create a second remote activity after a lost response. Quarantine preserves local data while failing closed on remote identity ambiguity. |
| D-013 | Keep stable backend and Flutter CI as separate required checks; pin runners, toolchains, and action commits; baseline informational analyzer findings as a counted multiset while warnings/errors remain fatal. | Separate stable names preserve existing branch-protection evidence, and counted fingerprints prevent line movement or duplicate lints from bypassing the quality gate. |
| D-014 | Run the backend on exact Prisma 7.8 with the `prisma-client` generator, PostgreSQL driver adapter, one DI-owned client/pool, and native NodeNext ESM. | The dependency-only Prisma 7 update could not validate or run against the Prisma 6 schema/client construction model. Completing the configuration, adapter, generated-output, module, and lifecycle migration removes that hidden local-client dependency while keeping PostgreSQL as the datastore. |
| D-015 | Backend refresh sessions have a seven-day absolute lifetime and a five-session cap; issuing a sixth session revokes the least-recently-used active session. Legacy refresh rows are dropped rather than backfilled. | Rotation must never extend the compromise window, login must remain usable at the cap, and legacy JWTs lack the session/token claims needed for a safe migration. The cutover intentionally forces one sign-in. |
| D-016 | Store the mobile access/refresh pair as one versioned secure-storage envelope; treat its revision as the credential-pair generation; require server verification before a migrated pair gains offline eligibility; and durably quarantine a backend-rejected revision before user-scope recovery. | Atomic pair writes, metadata-stable revisions, exact-revision deletion, and a restart-safe cleanup marker prevent split credentials, refresh races, stale-session offline re-entry, and deletion of a newer login. Android application backup is disabled pending the broader IP-2.7 local-protection design. |
| D-017 (amended 2026-07-20) | Google authentication exchanges only a provider-verified ID token at the backend, keys accounts by Google's stable subject, and issues the same bounded RythmRun session as password login. It links onto an existing local account **only** when that account's own email is verified (`emailVerified === true`) and it is not already linked (`googleSubject === null`), via a race-safe update plus revocation of the account's other sessions; every other collision is refused with `AUTH_EMAIL_UNVERIFIED_CONFLICT` (409). | A **verified** email proven on both sides is a safe linking proof; email *alone* is not (the original "never link" rule over-corrected). One first-party session contract preserves revocation, secure storage, offline policy, and account-scope teardown. Superseded the categorical no-link rule once IP-2.9 delivered email verification (see D-018). |
| D-018 | Email verification uses a single-use, SHA-256-digest-at-rest token emailed via one optional, feature-flagged transactional provider (**Brevo** free SMTP relay; sender domain **reshapeapp.ai**); `register()` never verifies and sends the link post-commit best-effort; the migration backfills `emailVerified=true` **only** where `googleSubject IS NOT NULL` and never blanket-verifies password accounts; the Flutter `emailVerified` defaults to `true` as a deliberate fail-open compatibility choice and is presentation-only (the server alone gates linking). | Verification is the prerequisite that makes D-017's auto-link safe. Digest-at-rest and never-logging the token satisfy the IP-2 recovery-token rule and let password recovery reuse the same primitives (the token table's `purpose` enum is built to extend to `PASSWORD_RESET`). Blanket-verifying password accounts would re-open the account-takeover window the gate exists to close. |

## Decisions that still require an owner

These do not block IP-0 or IP-1 but must be resolved before the named phase starts.

| Needed by | Decision | Recommended default |
| --- | --- | --- |
| IP-2 | Device location/photo protection at rest | Approve library/performance/backup recovery first; prefer per-user data keys wrapped by the platform keystore, encrypted DB/files, and exclusion from unencrypted backups. |
| IP-4 | Cross-device conflict policy | A remote tombstone auto-deletes only a locally proven previously-synced identity/revision; an unsynced collision is quarantined, not erased or resurrected. Ask the user only for true editable journal conflicts. |
| IP-5 | iOS release commitment | Keep the release Android-only unless real-device background and image/ads checks pass. |
| IP-5 | Crash/metrics vendor and retention | Choose the smallest provider that supports redaction, regional requirements, and short retention. |

> Resolved 2026-07-20: **Password-recovery email provider and sender domain** — Brevo free transactional SMTP relay + `reshapeapp.ai`, feature-flagged, tokens stored digest-only and never logged. Recorded as [D-018](#decisions-already-made) and delivered by IP-2.9.

## Deferred backlog

The following findings are real but intentionally do not outrank the trust program:

- Social feed, likes, comments, discovery, and friend journeys.
- Cadence, music, rhythm coaching, wearables, and health-platform integration. The separate [Samsung Health](../../samsung-health-integration-plan.md) and [Strava](../../strava-integration-plan.md) documents are design artifacts only; they do not authorize implementation or supersede lower-numbered security, account-deletion, privacy, or durability work.
- AI-generated summaries.
- Offline map tile caching.
- Banner-ad expansion.
- Broad file/module restructuring that is not needed for a phase task.
- Cursor pagination, larger IDs, or partitioning until IP-4 measurements justify them.
- General analyzer cleanup beyond release-blocking or touched-code findings until safety work is protected by CI.

## Plan maintenance

When a phase changes state:

1. Update the phase status and `Last updated` value in its file.
2. Update the phase table here.
3. Append evidence rather than overwriting failed attempts.
4. Add or amend a decision entry when behavior or scope changes.
5. Move newly discovered work to the earliest phase whose exit condition depends on it.
6. If the plan and code disagree, treat the code as current behavior and update the plan in the same implementation change; never claim unverified behavior in documentation.
