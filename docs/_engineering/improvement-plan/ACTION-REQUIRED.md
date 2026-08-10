---
published: false
---

# What needs your attention

Everything on this page is work the repository **cannot** do for itself. Each
item needs production access, a provider account, a GitHub setting, a physical
device, or a staging environment. Code and local tests can never close one.

**Delete an item when it's done.** When this file is empty, the program is
finished. Nothing else in `_engineering/` tracks your to-do list — this is it.

**One rule for all of it:** never commit secrets, tokens, raw logs, customer
identifiers, exact routes, database snapshots, coordinates, or incident detail.
Keep sensitive evidence wherever you keep such things and write only a safe
reference here.

The `MC-x.y` IDs are referenced from the phase files. Keep them when you edit.

---

## 1. Blocking release — production incident work

Nothing ships until this group is done. The exposed profile/avatar path is the
reason IP-0 exists.

### MC-0.1 — Contain the exposed routes
Restrict the affected registration/profile/avatar routes at the edge. Record the
route inventory, the rule applied, the incident start time, and an owner. Prove
containment with anonymous and authenticated probes that both fail.

### MC-0.2 — Preserve evidence, decide exposure
Preserve the relevant log window and a database snapshot **before** any cleanup.
Review them and date the earliest possible exposure. If exposure can't be ruled
out, MC-0.3 is mandatory rather than optional.

### MC-0.3 — Rotate credentials
Rotate JWT, refresh/session, database, R2, and CDN material. Order matters: get
replacements working before revoking the old ones. Prove old credentials and
sessions now fail.

### MC-0.4 — Migrate and quarantine unsafe avatar values
Verify a restorable backup first. Then classify unsafe legacy avatar values with
a reversible migration. Record classified counts and the rollback path.

### MC-0.5 — Infrastructure posture review
Check R2 credential scope, bucket access, encryption, abandoned-object lifecycle
rules, database TLS, backup retention, and prove an isolated restore actually
works.

> Changed 2026-07-28: the app needs **no public delivery origin** for either
> bucket — all media reads are short-lived presigned GETs. Confirm public access
> is *disabled* on both buckets and any previously configured public/CDN origin
> is *retired*, not merely unused.

### MC-0.6 — Stand up isolated security staging
An isolated backend + Postgres + R2 prefix + secrets + synthetic accounts,
running the same migrations and build. Confirm the host is Node.js 22.x. Almost
every other item below needs this to exist first.

### MC-0.12 — Controlled reopen + 24-hour watch
Only after the rest of IP-0 passes. Reopen registration/profile text paths
first; avatar request/confirm only after storage policy, quota, intent, and
cleanup checks pass. Define rollback thresholds for `4xx`, `5xx`,
avatar-confirm, storage rejection, and R2 errors **before** reopening. Watch for
24 hours with a named on-call owner and reapply containment if a threshold or
security invariant breaks.

---

## 2. Accounts and consoles you own

These are the "set it up once" items. Two of them gate features that are already
written and merged but cannot be switched on.

### MC-2.5 — Email provider (Brevo/SMTP)
Gates **both** email verification (IP-2.9) and password reset (IP-2.4) — they
share one provider. Setup instructions:
[`EMAIL_VERIFICATION_SETUP.md`](../../../RythmRun_backend_nodejs/EMAIL_VERIFICATION_SETUP.md).

1. Apply the additive `emailVerified`/`VerificationToken` migration **and** the
   `PASSWORD_RESET` enum migration `20260721000000` on the release database
   before the linking code serves traffic.
2. Configure real Brevo/SMTP with sender-domain SPF, DKIM, and DMARC
   authenticated.
3. Staging: deliver a live verification email, render the verify page for
   success / already-verified / expired, consume a single-use token
   idempotently, and exercise the throttled resend.
4. On device: the banner shows only for unverified password accounts; resend and
   "I've confirmed" refresh clear it.
5. A verified-email Google sign-in auto-links; an unverified one returns
   `AUTH_EMAIL_UNVERIFIED_CONFLICT`.
6. Password reset: deliver a live reset email, render the form from the emailed
   link, submit it to consume the single-use 30-minute token once, prove every
   session is revoked, confirm a Google-only account request sends nothing, and
   drive the same flow from the Flutter forgot-password screen.
7. Confirm no token, digest, or recipient is written to logs for either flow.

Use a capture-only inbox or disposable mailbox. **Until this is done, don't
deploy the branch** — a reset request ends at "check your inbox" with no email
sent.

### MC-2.4 — Google identity: console, signing, migration, device
1. Record the Google Cloud project, consent-screen mode, one web/server OAuth
   client, the Android package name, and every approved debug/internal/release
   signing-certificate fingerprint. The exact web client ID configured as
   backend `GOOGLE_SERVER_CLIENT_ID` must be the audience supplied to Flutter.
   No OAuth client secret belongs in the mobile app.
2. On an upgrade copy, run the migration preflight that rejects blank or
   case/whitespace-colliding usernames. Drain and stop every old backend
   instance before applying `20260715000000_add_google_auth`, and keep traffic
   drained until the Google-aware artifact is promoted. Old and new artifacts
   must never be live together across the nullable-password schema boundary.
3. Confirm the hosted run applies the full migration chain and *executes* the
   seven-test PostgreSQL suite rather than skipping it.
4. On release-signed Android: chooser cancellation, first sign-in, repeat
   sign-in, process restart, access expiry/refresh, logout, account switching,
   and forced session revocation. Success must use the same credential envelope,
   authenticated root, offline policy, and teardown as password login;
   cancellation must create no session anywhere.
5. Collision policy with synthetic identities: an existing password account with
   the same email gets a safe conflict and is not linked; the same verified
   subject returns the same account; concurrent first exchanges create at most
   one account; a changed provider email does not replace subject identity.
   Google-only Settings hides password change.
6. Invalid, expired, wrong-audience, unverified-email, and malformed tokens plus
   a provider outage: invalid identity gets the generic typed rejection, outage
   gets only the safe retryable category, nothing is auto-replayed, and no
   client-supplied subject/email/name is trusted. All exchange traffic over
   HTTPS.
7. Check the release UI against Google's current branding requirements — the
   temporary plain `G` placeholder is not release evidence.
8. Android is the promised platform. If iOS enters scope, additionally prove the
   iOS client ID and reversed callback scheme in the signed artifact,
   physical-device sign-in/logout/switch, secure storage, and the App Store
   requirement for an equivalent Sign in with Apple option.

### MC-0.10 — Dependency advisory review *(blocked on your approval)*
Sending the dependency inventory to npm's advisory service needs your explicit
approval first. Then: run `npm audit --omit=dev` from the backend, keep the
dated report, and for every advisory record package, installed path, severity,
affected range, runtime reachability, chosen fix, owner, and due date. Upgrade
or remove reachable vulnerable packages; a suppressed advisory needs approval,
reachability evidence, an expiry date, and a tracking reference. Don't reopen
routes while a reachable critical/high production advisory stands. Re-run the
full local gate chain afterwards.

> The 2026-07-10 count of 11 advisories is discovery evidence, not a current
> result.

---

## 3. GitHub settings and hosted CI

Cheap to do, and they unlock the "is this actually green" question for
everything else.

### MC-0.7 — One successful hosted `Backend security` run
Push through the normal protected path. Verify the hosted job completes
`npm ci --no-audit`, Prisma validation, Prisma generation, the production
typecheck, the full native-ESM Jest suite, the production build, and
`npm run smoke:runtime` — with no skipped step and no source-only substitute for
the emitted build. Record the run URL and SHA.

### MC-0.8 — Intentional backend failure probe
On a temporary branch (never `main`), break one existing security assertion so
it fails deterministically. Confirm `Backend security` fails at the backend-test
step. Record the failed run URL, then close the PR and delete the branch.
Confirm the reviewed branch is still green and contains none of the probe.

### MC-0.9 — Require the backend check
After 0.7 and 0.8: add the stable `Backend security` job name to the `main`
ruleset, require PRs and current branches per policy, and don't allow ordinary
merges to bypass it. Prove an unpassed check blocks a normal merge.

### MC-1.9 — One successful hosted `Flutter CI` run
Use `pull_request`, never `pull_request_target`. Confirm the stable job name is
`Flutter CI` on Ubuntu 24.04 with Flutter 3.44.1 / Dart 3.12.1 and that
checkout/setup resolve the pinned action commits. Confirm it enforces
`pubspec.lock`, checks formatting only on merge-base-changed Dart files, rejects
analyzer warnings/errors, accepts only a sub-multiset of the committed
informational allowance, and runs the full suite including SQLite FFI tests.
Check permissions stay `contents: read`, checkout credentials aren't persisted,
and no secret or workspace artifact is cached or uploaded.

### MC-1.10 — Independent CI regression probes
One fault per temporary revision, each starting from the same green commit, so
fail-fast can't mask a later gate. Prove: a TypeScript type error reddens only
the type-check path; and in separate Flutter revisions, a failing assertion, an
unformatted changed file, an analyzer warning, and one extra informational lint
each fail at test, format, fatal-warning analysis, and baseline comparison
respectively. Don't edit the baseline or comparator for the informational probe.
Record every failed run URL, the cleanup, and the final green run. (MC-0.8 owns
the backend-test probe.)

### MC-1.11 — Require both checks, protect the CI controls
Require both `Backend security` and `Flutter CI` in the `main` ruleset, with no
path filters that leave a required check unreported. Then set independent review
ownership for `.github/workflows/backend-security.yml`, `.github/workflows/ci.yml`,
`tool/ci/analyzer_baseline.dart`, and `tool/ci/analyzer_baseline.json` — the
reviewer has to actually inspect baseline additions and toolchain changes. Prove
a CI-control change can't self-approve.

---

## 4. Isolated staging runs

All of these need MC-0.6 first.

### MC-1.12 — Prisma 7.8 against real PostgreSQL
The built smoke deliberately doesn't connect to a database, so nothing local
covers this.
1. Isolated Postgres, synthetic data, restorable pre-run backup. Record the
   version and a safe identifier — never the connection URL or certificates.
2. Verify certificate validation and the exact TLS mode on both the migration
   and runtime connections. Reject expired, untrusted, hostname-mismatched, or
   silently downgraded connections. Don't "fix" it by accepting bad certs.
3. From a clean checkout: validate/generate, apply the full migration chain to a
   fresh database, then separately exercise the upgrade path on a previous
   schema and run `prisma migrate status`. No drift, no failed migration.
4. Start the built ESM artifact with the Prisma adapter and run a bounded
   health/query fixture plus the serializable activity/avatar transactions.
   Prove commit and rollback, uniqueness/cascades, timestamp/float round trips,
   and retry classification.
5. If a non-`public` schema is supported, prove both the CLI and the runtime
   adapter select it. Otherwise document that `public` is the contract.
6. Measure pool behavior with the committed maximum, 5s connection timeout, 300s
   idle timeout, and the real replica count. Record peak/idle/waiting
   connections, capacity headroom, connection-failure latency, and recovery
   after a database restart.
7. Stop through the cleanup API and verify all connections close. Repeat with
   the database down and confirm error output has categories only.

### MC-1.13 — Deployment order and bounded shutdown
1. Execute the host's exact sequence: locked install *including* build tools;
   Prisma generation/validation; production typecheck; Jest; production build;
   runtime smoke; one-owner migration; optional dev-dependency pruning; start
   from the same emitted artifact. **If the host installs with `--omit=dev`
   before build/migration, that's a failed deployment contract.**
2. Record commit, Node 22 runtime, lockfile digest, artifact identifier,
   migration set. Promote the *same* artifact from staging — don't rebuild
   production from a different dependency resolution.
3. Note explicitly that `smoke:runtime` uses an unreachable database and proves
   nothing about PostgreSQL, TLS, migrations, R2, pool capacity, or signals.
4. On the real host with synthetic traffic, `SIGTERM` while one bounded request
   is active: traffic stops, the listener drains within the grace period, timers
   stop, the request finishes or terminates per policy, the pool closes.
5. Repeat with a deliberately stuck request. The documented deadline must
   force-close, produce a failure exit visible to orchestration, and leave no
   migration, worker lease, or database session owned by the dead instance.
6. Restart and prove recovery without duplicate migration execution.

### MC-2.1 — Hosted PostgreSQL auth-session gate
Push the current auth/session tree through the normal PR path. Confirm the run
provisions its disposable `rythmrun_ci` database, applies every migration, and
that **all seven** `auth-session.postgres.test.ts` cases *execute* — a skipped
database suite is a failed gate even when the job is green. The run must cover
two Prisma clients racing one refresh token, committed replay-family revocation,
digest-only rows, logout/password revocation, stale-login rejection during a
password-change race, the five-session bound, and safe `/me`.

### MC-2.2 — Auth-session destructive cutover rehearsal
Legacy JWTs cannot be backfilled — this cutover forces every user to sign in
once, so rehearse it.
1. Isolated staging upgrade copy, synthetic accounts, verified restorable
   backup.
2. Build and identify the session-aware artifact **first**. Drain every old
   instance before applying `20260713000000_rebuild_auth_sessions` — an old
   process must not keep accepting legacy plaintext refresh rows mid-cutover.
3. Apply once, confirm the legacy table is gone and new constraints/indexes
   exist, promote the matching artifact. Prove legacy JWTs fail and a
   communicated one-time sign-in creates only digest records.
4. Run register/login/refresh/concurrent-refresh/`/me`/logout/password-change
   canaries. Logs carry categories only.
5. Exercise the rollback decision. Prefer roll-forward; never recreate plaintext
   refresh rows or promote a backend that doesn't understand `sid`/`jti`/`typ`.

### MC-2.6 — Deployed edge configuration for abuse controls
The limiter is **in-process**: a restart clears every counter and a second
replica multiplies every limit. The replica count is part of what this verifies.
- Record the `TRUST_PROXY_HOPS` value *and the reasoning tying it to the actual
  hosting proxy depth*. Probe that a client-supplied `X-Forwarded-For` cannot
  change the address the limiter charges.
- Record the production `CORS_ALLOWED_ORIGINS` value. Probe that an allowlisted
  origin gets an exact `Access-Control-Allow-Origin` and a non-allowlisted one
  gets none — no wildcard, no `Access-Control-Allow-Credentials`.
- Deployment smoke: a production process with `CORS_ALLOWED_ORIGINS` absent must
  exit non-zero **before listening**.
- Drive one endpoint past its budget: stable `429` with `Retry-After`, recovering
  after the window.
- Confirm exactly one replica, or record a decision to move counters to a shared
  store before scaling.

> Don't confuse this `429` with the IP-1.5 admission-concurrency `429` in
> MC-1.8 step 8. Local tests prove the code honours the configured hop count,
> not that the configured value matches your real proxy.

### MC-1.2 — Metric migration backups and staging exercise
Verify restorable Postgres and device/SQLite backups before any value rewrite.
Apply the additive backend column/check and the SQLite v5 migration to staged
copies. Prove existing rows become version 1 with no numeric change and new rows
persist as version 2. Any later value migration runs only where version 1 *and*
the MC-1.1 classification rule both match, atomically and idempotently. Reopen
twice, compare version counts and aggregates, rehearse rollback.

### MC-1.6 — User-scope exit and account-switch isolation
Two synthetic accounts on a supported Android release build against staging.
1. Load A's history, details, images, profile/avatar, settings, and a pending
   sync.
2. While A is idle, make only the remote logout endpoint unavailable and sign
   out. Work drains, local credentials clear, landing screen appears, A's
   offline rows survive, and no A content flashes after logout. (Server-side
   token revocation is IP-2's job — don't infer it here.)
3. Inject a local `clearAuthData` failure: exit stays blocked behind
   non-dismissible Retry, B cannot authenticate, and a restart doesn't silently
   restore A.
4. Sign in as B without restarting. B sees only B-scoped data even when local
   workout IDs overlap.
5. Sign back in as A: A's retained rows are available only to A.
6. Start an A workout and attempt logout. "Stay signed in" preserves tracking,
   "Finish & logout" saves exactly once, "Discard & logout" removes the
   in-memory workout. Timers and the GPS subscription stop in both exit paths.
7. Through a QA hook, force an invalid session while A has an active workout.
   Forced auth loss attempts a local save under A before clearing. Inject a save
   failure: switching stays blocked behind Retry/Discard.
8. Hold a native GPS start, workout/image sync, avatar upload, token refresh,
   and a login response in flight during exit. New work is rejected, admitted
   work finishes under A, and no late callback renders A/B under the wrong
   session.

### MC-1.8 — Bounded activity ingest and PATCH history
1. Configure edge and app so only `POST /api/activities` and
   `PATCH /api/activities/:activityId` accept the 3 MiB limit; ordinary JSON
   routes stay at 100 KiB. Prove the proxy imposes no smaller hidden limit and
   doesn't broaden large-body acceptance elsewhere.
2. Confirm from release history that metrics version 2 wasn't deployed before
   the IP-1.2 GPS contract. Verify current-client timestamps arrive with UTC
   offsets, and sync one activity from the last supported pre-IP-1.5 client to
   prove its offset-less timestamps keep the intended interval.
3. Sync the 750-point fixture and a multi-hour fixture below 12,000 locations
   and 1,000 status changes. One activity per `clientSyncId`; retries return the
   same activity.
4. Failure matrix: `400`/`413`/`422` record a stable `sync_blocked_reason`, stop
   retrying that row, and let later rows continue. An unknown code reduces to
   the status-derived fallback. `401`/`403`/`429`/`5xx`/network stay eligible.
   Switch accounts before a delayed permanent response and prove no block reason
   lands in the new user's scope.
5. Send wide unknown-root, deeply nested, and attacker-sized nested-key bodies
   below 3 MiB, plus a max-size DTO-invalid fixture and a DTO-valid fixture with
   12,000 semantically invalid locations. Structural preflight returns a small
   static first-error without reflecting the long key or reaching the service;
   semantic response caps at 25 issues with `issuesTruncated: true`. No database
   write.
6. Send a body above 3 MiB with `Content-Length` and again chunked. Both return
   JSON `413` with `ACTIVITY_PAYLOAD_TOO_LARGE` and no write. Never run oversized
   probes against production.
7. An unauthenticated large request returns `401` before parsing. Then hold one
   request for a user and four across distinct users: the same-user and fifth
   global requests return retryable `429` with `Retry-After` without reaching
   validation, and a closed request releases its slot exactly once.
8. Against staging Postgres: a name-only PATCH leaves locations and status
   changes unchanged; explicit `locations: []` / `statusChanges: []` clears only
   the named collection; a later metric PATCH doesn't reinterpret a route bridge
   after status history is gone; a malformed replacement writes nothing; an
   injected nested-write failure rolls back to prior digests. From two
   processes, submit complementary partial patches against the same row — the
   serialization conflict must retry so the final row satisfies the merged
   contract, not two stale snapshots.
9. Define rollback before rollout. If 3 MiB proves unsafe, forward-fix the body
   limit and the location/status caps together from measured fixtures; don't
   silently revert to the 100 KiB failure.

---

## 5. On a real Android device

### MC-0.11 — Avatar lifecycle
**Re-run required — the mechanism changed 2026-07-28 (`76fa16f`).** Upload is no
longer a multipart POST to a policy-signed form; it's a `PUT` to a presigned URL
carrying exactly the `Content-Type` and `Content-Length` the server signed.
Display is no longer a public-origin fetch; it's an authenticated
`GET /avatar/read-url` returning a short-lived presigned GET. **Evidence from the
old mechanism does not carry over.**

1. Request → upload → confirm → display → replace → logout on the supported
   build in staging.
2. **Prove the byte bound at the storage boundary:** replay the presigned PUT
   with a body larger than the signed `Content-Length` and record that R2
   rejects it before accepting the object. This is the check that was never
   actually exercised — the old POST policy was unsupported by R2, so its
   `content-length-range` enforced nothing.
3. With the read URL expired and no session, confirm the object cannot be
   fetched from any public R2 or CDN origin.
4. Confirm logs contain no secrets, signed URLs, raw keys beyond operational
   need, filesystem paths, response bodies, or exact routes.

### MC-2.3 — Secure credential migration and session lifecycle
1. Release candidate against staging, synthetic accounts. Confirm the merged
   manifest has application backup disabled — don't weaken it to inspect
   credentials.
2. Per device class: install the previous app, create a coherent synthetic
   access/refresh pair in the historical preference keys, upgrade **in place**.
   Legacy keys must disappear only *after* the secure envelope is read back.
   Neither sentinel credential may appear in plaintext preferences, files,
   screenshots, diagnostics, or logs.
3. Repeat with interruption before secure write, after write but before legacy
   cleanup, and during cleanup — restarting at each boundary. The next launch
   either completes migration once or requires sign-in; it must never lose the
   only recoverable pair, build protected UI from a partial pair, duplicate
   rotation, or restore a rejected pair as offline-authorized.
4. Backup/restore, device transfer, app-data clear, reinstall, and secure-store
   key loss. None may recreate a session from cached user/SQLite data. A
   restored blob without its device-bound key fails closed silently.
5. Login and registration both reach the same authenticated root. Force access
   expiry with three idempotent reads active: one refresh plus one replay per
   request, and a non-idempotent mutation is *not* replayed. Airplane mode vs.
   explicit revocation: only the former may enter bounded offline mode.
6. Offline window and clock tamper: with no network, verified history is
   reachable inside seven days of the last server verification and refused
   after — never deleting completed local workouts. Roll the clock backward (and
   forward then backward): offline admission fails closed and needs fresh online
   verification; the tripwire survives a restart. Offline mode denies password
   change, avatar upload, and background sync with a clear message, and
   reconnecting restores them.
7. Change the password: the success response immediately removes the exact local
   credential revision, completes or visibly blocks recovery, and ends at the
   guest root. Repeat for logout and forced revocation. No newer login is
   deleted by a delayed old-session response.
8. Review release logs with unique synthetic sentinels — no token, password,
   authorization header, profile body, secure-store payload, exact route,
   coordinate, local path, or signed URL. Rollback is a forced sign-in, never a
   downgrade to an app that persists plaintext tokens.

### MC-1.5 — GPS acceptance and pause behavior
Release build, isolated account, supported Android device. Walk or run a
measured route, pause, move a deliberate large distance, resume, finish. Paused
movement and the first resumed sample must add **zero** distance. The map,
stored route, distance, active time, max speed, and synced route count all
derive from the same accepted sequence with visible breaks. Exercise
poor-accuracy and implausible-jump conditions and confirm rejection changes
nothing. Finish while paused, and repeat pause/resume: the open pause closes
once, active time is non-negative, a duplicate finish creates no second workout.
Confirm exact coordinates, acquisition timestamps, and route payloads are absent
from release logs and crash breadcrumbs.

### MC-1.7 — SQLite v5→v6 ownership migration
1. Install the last v5 release build; seed synthetic accounts A and B with
   completed workouts, points, status changes, image metadata, and one queued
   remote deletion.
2. Upgrade **in place** to v6 — do not clear app data. Open, terminate, restart
   twice, confirm A and B history still loads under the right account.
3. Via a diagnostic build, record pass/fail for `PRAGMA foreign_keys = 1`, an
   empty `PRAGMA foreign_key_check`, schema version 6, and the composite indexes
   with expected columns, direction, and uniqueness.
4. With known local IDs, B must receive no A data and be unable to delete, mark
   synchronized, attach, retry, refresh, or complete anything queued for A.
5. Delete an A-owned local-only workout: point, status, and image rows cascade;
   B's rows survive. Exercise a queued remote deletion and an image
   upload/delete held across account exit — completion stays with A or stays
   retryable.
6. On a duplicate `(user_id, client_sync_id)` fixture, only one identity is
   eligible to sync, extras are quarantined locally, and a conflicting remote
   mapping rolls the upgrade back without advancing `user_version`.
7. v6 is forward-only — never install a v5 binary over a v6 database. Rehearse
   restore and the forward-fix path.

### MC-1.14 — Ad configuration and durable-completion gate
1. Build the safe matrix from
   [`CONFIGURATION.md`](../../../rythmrun_frontend_flutter/CONFIGURATION.md):
   dev debug ads-off, staging profile ads-off, production release ads-off.
   Inspect the **merged/package manifest**, not the source manifest. AdMob app
   metadata must resolve to the official Google sample ID and never to a
   supplied production value; `DELAY_APP_MEASUREMENT_INIT` resolves `true`; and
   `AD_ID`, `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION`, and
   `ACCESS_ADSERVICES_TOPICS` are absent. Dart resolves the no-op provider and
   makes no initialization or ad request.
2. Run the negative release command with `ADS_ENV=production ADS_ENABLED=true`
   and no IDs: the build must stop during configuration with no APK/AAB. Repeat
   through an aggregate/custom Gradle entry point, and with malformed,
   Google-sample, and publisher-mismatched placeholders. Every case fails before
   packaging.
3. **Do not use real production IDs to satisfy this check.** Live IDs, consent,
   placement approval, and rollout are IP-5.5. Keep `ADS_ENABLED=false` for every
   distributable build until then.
4. On the ads-disabled build, complete a synthetic workout. The local
   transaction completes and the workout appears in history *before* any
   completion gate; no ad surface, no SDK request. Duplicate Finish/back actions
   create no second workout or ad attempt.
5. Inject a local-save failure: Finish retains the workout, blocks starting
   another, offers Retry save and explicitly confirmed Discard, and records zero
   ad attempts. Fail one retry, then succeed — the workout becomes durable, still
   zero ad attempts.
6. Separately inject incomplete tracking-resource cleanup after a successful
   save. Recovery UI appears before any ad opportunity, Retry stays available,
   ad attempts stay zero. An ad/SDK failure or hanging callback must not hang
   Finish, hide a committed workout, or replace recovery UI. Begin account exit
   during a delayed ad load and confirm no provider display after the scope
   changes.

### MC-1.3 — Previous-client and device compatibility
Build the supported old-client matrix and prove Android SQLite
upgrade/reopen behavior against it. **The backend migration must be deployed
before the corrected version-2 mobile writer ships.**

---

## 6. Data analysis (no code, no device)

### MC-1.1 — Sample legacy metrics before interpreting them
From an access-controlled export with only metric version, distance, active
duration, stored average speed, and a non-identifying reference:
calculate `storedAverageSpeed / (distanceMeters / activeDurationSeconds)`.
Near `1.0` suggests canonical m/s; near `3.6` suggests the historical km/h
defect. Treat zero, invalid, mixed, or ambiguous records as **unresolved** rather
than guessing. Do not divide `maxSpeed` or GPS point speed — those were already
m/s. Record the sample window, counts, thresholds, exclusions, and approval.

### MC-1.4 — Coordinated metric rollout and observation
Deploy the additive backend migration, then backend support for versions 1 and
2, **then** release the corrected mobile writer. Verify an old client still
creates version-1 activities and the new client creates version-2 with m/s
values. Roll out gradually while watching version counts, speed/distance ratios,
sync `4xx`/`5xx`, migration failures, and abnormal calorie/speed distributions —
without collecting exact routes. Stop on a threshold breach.

> Once any unsynced version-2 workout exists, **do not roll back** to a client
> that omits `metricsVersion` — it would upload canonical m/s as legacy version
> 1. Stop sync and forward-fix instead.

---

## Cross-item rules

- A check is done only when its evidence is dated and someone other than the
  doer has looked at it. Repository commits and local test results can never
  close one of these.
- Never infer one from another. Hosted CI does not prove staging; staging does
  not prove production; a passing deploy does not prove incident closure.
- If a check runs and fails, execute its containment or rollback action rather
  than leaving it half-done.
- When you close an item, delete it here and add a dated line to the relevant
  phase evidence log in `IP-*.md`.
