---
published: false
---

# RythmRun improvement program — status tracker

A single-page roll-up of every improvement phase, its work packages, and the
open manual/hosted gates. It is derived from the phase files at their
`Last updated: 2026-07-17` state, plus the reconciliations of the 2026-07-20
email-verification and 2026-07-21 password-recovery deliveries (see the two
"Recent delivery" sections below).

The individual phase files and [MANUAL-CHECKS.md](./MANUAL-CHECKS.md) remain
**canonical** for evidence. This tracker summarizes them; it does not replace
them. If they disagree, the phase file wins and this tracker should be
regenerated.

## Legend

`Complete` · `Verification` (code merged + local tests pass; hosted/device/
staging proof open) · `In progress` · `Planned` · `Blocked` · `Deferred`.

**Repo-delivered** means code is merged and local tests pass — it is *not*
"done". Nothing in this program is `Complete`, because every delivered package
still owes at least one manual/hosted gate.

## Program at a glance

| Phase | Status | Packages delivered (repo) | Packages not started | Open manual gates |
| --- | --- | --- | --- | --- |
| IP-0 Security containment (P0) | **In progress** | 6 of 10 (code); 4 operational packages not started | IP-0.1, 0.1A, 0.6, 0.7 (all operational) | MC-0.1–0.12 |
| IP-1 Tracking correctness | **Verification** | 7 of 7 | — | MC-1.1–1.14 |
| IP-2 Auth, account, privacy | **In progress** | 5 of 8 + IP-2.9 merged to main, plus the IP-2.6 abuse-control slice on branch (IP-2.4 account deletion and IP-2.6 storage boundary left) | IP-2.7 | MC-2.1–2.6 |
| IP-3 Workout durability | **Planned** | 0 of 5 | all | — |
| IP-4 Sync & restore | **Planned** | 0 of 6 | all | — |
| IP-5 Release readiness | **Planned** | 0 of 7 | all (5.7 Deferred) | — |

**Manual/hosted checks: 0 of 32 verified** (31 pending, MC-0.10 blocked;
MC-2.5 added 2026-07-20 for the IP-2.9 email delivery, extended 2026-07-21 to
also gate the IP-2.4 password-reset delivery on the same provider; MC-2.6 added
2026-07-27 for the IP-2.6 abuse-control slice). No package can reach `Complete`
until its gates carry dated evidence.

The single most important fact: **IP-0 is a P0 release blocker and its blocking
work is operational, not code.** Containment, exposure investigation, and
credential rotation cannot be closed from the repository — they need
production, log, database, R2/CDN, and secret-store access.

---

## IP-0 — Security containment `In progress`

| Pkg | Status | Repo | What's left |
| --- | --- | --- | --- |
| IP-0.1 Contain production & preserve evidence | Planned | ✗ | **Operational.** Edge-restrict the 6 exposed routes; record incident start/rule/owner; preserve edge+app logs and a DB snapshot; verify anon + authed probes fail. |
| IP-0.1A Bootstrap isolated security staging | Planned | ✗ | **Operational.** Stand up an isolated backend + Postgres + R2 prefix + secrets + synthetic accounts; run the same migration/build. |
| IP-0.2 Writable-field allowlists | Verification | ✓ | Merged `e33f314`; both exit boxes checked. Undeployed; re-runs under IP-0.7 controlled reopen. |
| IP-0.3 Retire filesystem avatars | Verification | ✓ | Route/sink removed + tested. Left: production route-containment proof; inventory/quarantine of suspicious legacy avatar rows (shared with IP-0.6). |
| IP-0.4 Harden S3 avatar pipeline | Verification | ✓ | Ownership/key/intent/type/size proven in tests. Left: single-use + storage-enforced policy against **real S3**, quota, and an independent bucket-lifecycle cleanup rule. |
| IP-0.5 Fail closed on config/secrets | Verification | ✓ | Local fail-closed proven. Left: hosted deployment smoke proving a prod process with a missing/placeholder/short/reused JWT secret exits non-zero before listening. |
| IP-0.6 Investigate exposure & rotate | Planned | ✗ | **Operational.** Query suspicious avatar paths; review logs; date earliest exposure; if not excludable, rotate DB/R2/CDN/JWT secrets + revoke sessions; tighten IAM; verify infra posture. |
| IP-0.7 Regression, staging rollout, controlled reopen | In progress | ✗ | Regression corpus committed; the package itself is operational: MC-0.10 advisory scan, full staging sequence, backend security CI (MC-0.7–0.9), controlled reopen + 24h watch. |
| IP-0.7-dep Dependency-surface reduction | Verification | ✓ | Committed `fc33dca`; AWS v2/joi/pg/winston removed. Left: MC-0.10 (blocked pending approval), MC-0.6 hosted Node 22 confirmation. |
| IP-0.7a HTTP security regressions + min CI | Verification | ✓ | Committed `c52fb87`; boundary suite passes locally. Left: MC-0.7 hosted run URL, MC-0.8 failure probe, MC-0.9 branch protection. |

## IP-1 — Tracking correctness & local integrity `Verification`

All seven packages are repo-delivered; each waits on a device/staging/hosted gate.

| Pkg | Status | Repo | What's left |
| --- | --- | --- | --- |
| IP-1.1 Metric contracts & legacy handling | Verification | ✓ | Production metric migration: sampled-data approval, backup, version guard, safe idempotent run (MC-1.1–1.4). |
| IP-1.2 GPS acceptance & pause state machine | Verification | ✓ | MC-1.5: walk/run a known route on-device; confirm distance = active route only; no raw coordinates in release logs. |
| IP-1.3 Nullable-state repair & user-scope teardown | Verification | ✓ | MC-1.6: idle/active/forced exit + A→B isolation on a supported release build with restart. |
| IP-1.4 Local ownership, FKs, indexes | Verification | ✓ | MC-1.7 Android v5→v6 in-place upgrade/owner-denial/cascades on device; MC-1.9 hosted FFI DAO tests. |
| IP-1.5 Preserve backend history & bound payload | Verification | ✓ | MC-1.8: deployed 3 MiB proxy alignment, resource bounds, real-Postgres PATCH rollback, prev-client compat, sanitized telemetry. |
| IP-1.6 Minimum CI & phase gates | Verification | ✓ | Hosted `Backend security` + `Flutter CI` runs (MC-0.7/1.9), failure probes (MC-0.8/1.10), branch protection (MC-1.11), real-Postgres (MC-1.12). |
| IP-1.7 Ads fail-closed until durable completion | Verification | ✓ | MC-1.14: safe merged-manifest + recovery-before-ads on a supported Android device (last APK build exhausted host disk). |

## IP-2 — Authentication, account lifecycle, privacy `In progress`

| Pkg | Status | Repo | What's left |
| --- | --- | --- | --- |
| IP-2.1 Rebuild session/refresh semantics | Verification | ✓ | Digest-only bounded sessions, serializable rotation, revocation, safe `/me`. Left: MC-2.1 hosted-Postgres transaction gate, MC-2.2 destructive cutover rehearsal. |
| IP-2.2 Secure mobile token storage | Verification | ✓ | Versioned secure envelope + single-flight refresh. Left: MC-2.3 physical-device storage/upgrade/backup/log lifecycle. |
| IP-2.3 Offline-session behavior | Verification | ✓ | 7-day fail-closed offline window + online-operation guard. Left: MC-2.3 device offline/rollback/airplane-vs-revocation proof. |
| IP-2.4 Profile, password recovery, account deletion | **In progress** | partial | **Profile and password-recovery slices delivered and merged to main** (PR #164; backend `34a14a9` + frontend `6b7dc97`): anti-enumerating request, one-transaction single-use reset revoking all sessions + refusing Google-only accounts, backend web form, and the Flutter forgot-password screen — reusing the IP-2.9 hashed-token store. The account/address recovery budget is delivered by the IP-2.6 abuse-control slice; production exposure/staging delivery remains gated by MC-2.5. **Account deletion** still awaits the retention/reauth decision, then transactional revocation + durable object-cleanup outbox/runner + full local+remote purge. |
| IP-2.5 Private routes; disable social | Verification | ✓ | **Delivered and merged to main** (PR #165; `bd78d9a`). `isPublic` defaults false + backfill migration to private, `getActivityById` owner-only (cross-user route/image/identity closed), friend/comment/like routers unmounted (`404`), README/seed corrected. Public policy pages were reconciled with the repository behavior on 2026-07-27. 290 backend tests. Left: apply the migration on staging/production and complete qualified IP-5.6 policy review against the release candidate. |
| IP-2.6 API abuse controls & typed errors | **In progress** | partial | **Abuse-control slice delivered** on branch `feat/api-abuse-controls`: required-in-production exact-match CORS allowlist (fail-closed before listen, https-only), `TRUST_PROXY_HOPS`-driven `trust proxy` defaulting to 0, in-process sliding-window budgets on login/register/Google exchange/recovery request+submit/password change/verification resend returning a typed `AUTH_RATE_LIMITED` 429 with `Retry-After`, typed `ActivityImageServiceError` replacing exact-message branching in the mounted image controller, request IDs + fixed-field privacy-safe security events, and readable Flutter handling for rate limits and invalid credentials. 452 backend / 355 Flutter tests. Left: **storage-boundary items 6–8** (enforceable activity-image upload grant, real ContentType/ContentLength/checksum confirmation, per-user object/byte quotas, abandoned-upload lifecycle, volume alarms), the unmounted social controllers' message-string branching, and **MC-2.6** deployed edge configuration. |
| IP-2.7 Protect retained routes/photos at rest | Planned | ✗ | Not started; gated on an owner design spike (threat model, library/perf, backup/key-loss recovery) before migrating SQLite + photos to user-scoped at-rest protection. |
| IP-2.8 Google identity extension | Verification | ✓ | Merged `c805f62`. Left: MC-2.4 non-rolling migration, OAuth-console/signing, provider, device, staging, branding proof. **Note: its no-implicit-link behavior is superseded by IP-2.9 below.** |
| IP-2.9 Email verification & safe linking | Verification | ✓ | **Merged to main** (PR #164). Delivers `emailVerified` + hashed token table, optional SMTP send, verify/resend, and the emailVerified-gated Google auto-link. Left: **MC-2.5** — real Brevo/SMTP + DKIM/SPF, staging delivery + verify page, on-device banner/resend. Resolves D-018; its hashed-token store is reused by the merged IP-2.4 password recovery. |

## IP-3 — Workout durability `Planned`

Nothing delivered. IP-3.1 durable engine + checkpoint DAO · IP-3.2 exactly-once
finalize + recoverable failures · IP-3.3 current-user recovery UX · IP-3.4
Android foreground/screen-off tracking (needs Gradle/AGP/Kotlin bumps) · IP-3.5
remove long-session quadratic UI. Gated on IP-1 metric engine + IP-2.1–2.3
identity/offline core; at-rest checkpoint format gated on the IP-2.7 design.

## IP-4 — Sync, data contracts, cloud restore `Planned`

Nothing delivered. IP-4.1 explicit sync-state enum + retry UI · IP-4.2
resumable versioned `/api/v2` upload · IP-4.3 summary/detail/point projections
+ cursor pagination · IP-4.4 Postgres indexes + capacity evidence · IP-4.5
idempotent pull/restore + image restoration · IP-4.6 durable replica-safe
deletion worker (generalizes the IP-2.4 outbox). Gated on IP-2 auth/privacy +
IP-3 durable local state.

## IP-5 — Release readiness; retention follow-on `Planned`

Nothing delivered. IP-5.1 testable server lifecycle/health · IP-5.2
privacy-safe observability · IP-5.3 release-grade CI · IP-5.4 staging/release/
rollback discipline · IP-5.5 platform/monetization scope (open iOS decision) ·
IP-5.6 documentation reconciliation · **IP-5.7 post-gate retention epic —
`Deferred`.** Gate follows the exit of IP-0 through IP-4.

---

## Manual / hosted gates — 0 of 32 verified

Every row is unevidenced. Grouped by who can close it:

- **Human incident/infra (production access):** MC-0.1 containment · MC-0.2
  evidence/exposure · MC-0.3 credential rotation · MC-0.4 DB migration +
  avatar quarantine · MC-0.5 R2/TLS/lifecycle/backup posture · MC-0.6 isolated
  staging · MC-0.10 dependency advisory (**Blocked** pending approval) ·
  MC-0.12 controlled reopen.
- **Hosted CI / repo admin:** MC-0.7 backend-security run · MC-0.8 failure
  probe · MC-0.9 branch protection · MC-1.9 Flutter CI run · MC-1.10 CI probes
  · MC-1.11 required checks.
- **Physical Android device / QA:** MC-0.11 avatar lifecycle · MC-1.3 client
  compat · MC-1.5 GPS/pause · MC-1.7 SQLite v5→v6 · MC-1.14 ads/completion ·
  MC-2.3 secure-credential lifecycle.
- **Isolated staging:** MC-1.2 metric migration · MC-1.6 user-scope isolation ·
  MC-1.8 bounded ingest/PATCH · MC-1.12 Prisma 7.8 on real Postgres · MC-1.13
  deploy order/shutdown · MC-2.1 auth-session transaction · MC-2.2 auth cutover
  · MC-2.4 Google identity migration/provider/device · MC-2.5
  email provider/delivery + on-device banner (IP-2.9) — extended to also gate
  the IP-2.4 password-reset email delivery/flow, which shares the same provider
  · MC-2.6 deployed abuse-control edge configuration (proxy depth, production
  origins, fail-closed boot, live 429 recovery, single-replica assumption).
- **Product-data analysis:** MC-1.1 legacy metric sampling · MC-1.4 rollout
  observation.

---

## Recent delivery — reconciled into the plan 2026-07-20

**Email verification + safe Google account linking** — 7 commits
(`7432e9c`…`4f0983f`) on branch **`feat/email-verification`** (not yet merged;
PR pending). Backend **347** Jest tests pass; Flutter **343** tests pass. The
plan has been updated to match shipped code (per program rule 6 and
maintenance step 4): D-017 amended, D-018 added, the email-provider owner
decision resolved, IP-2.8 prose scoped, and the delivery recorded as **IP-2.9**
with an evidence-log row and manual gate **MC-2.5**.

### What it changed in the plan

| Impact | Detail |
| --- | --- |
| **Resolves an owner decision** | "Password-recovery email provider and sender domain" → **Brevo** free SMTP relay (300/day, no card) + **reshapeapp.ai** sender domain, feature-flagged, tokens stored SHA-256-digest-only and never logged. Move this row from *Decisions that still require an owner* → *Decisions already made*. |
| **Unblocks IP-2.4 password recovery** | The provider prerequisite is cleared and the reusable primitives are delivered: the `VerificationToken` table (single-use `consumedAt`, `expiresAt`, unique `(userId,purpose)`, sweep-timer purge) and a `VerificationTokenPurpose` enum explicitly built to add `PASSWORD_RESET`. Only the reset endpoints/UI remained then (delivered 2026-07-21 — see the next section). Account **deletion** stays blocked on its own retention/reauth decision. |
| **Contradicts D-017** | D-017 says the system "never implicitly links an existing password account by email" — now false. `googleLogin()` auto-links when `emailVerified === true` **and** `googleSubject === null` (race-safe `updateMany` + revoke other sessions), else `AUTH_EMAIL_UNVERIFIED_CONFLICT` (409). **Amend, don't delete** — the rationale ("email alone is not safe proof") holds; both sides now prove the same mailbox. |
| **Falsifies IP-2.8 prose** | "refuses implicit linking when a password account owns the email" and "explicit account linking is not implemented" now hold only for the **unverified** case. Scope both to unverified; note verified-email safe linking is delivered. The IP-2 non-goal "implicit email-based account linking" needs the same verified/unverified split. |
| **New capability the plan has no concept of** | `User.emailVerified` + hash-at-rest `VerificationToken`; migration `20260718000000` backfills `emailVerified=true` only where `googleSubject IS NOT NULL` (never blanket-verifies password rows); post-commit best-effort send; public idempotent `GET /verify-email` (CSP + `no-referrer`); throttled `POST /verify-email/resend`; optional SMTP feature flag; Flutter banner (unverified password accounts only) + `/me` refresh + new error-code mapping. |

### Plan edits applied 2026-07-20

1. ✅ **D-017** amended to the shipped gated-linking rule; **D-018** added for
   the email-verification policy.
2. ✅ Email-provider owner decision moved to *Decisions already made* (D-018).
3. ✅ The "blocked on the email-provider decision" statements updated (README
   program status, README next-steps #1, IP-2 header *External prerequisites*,
   IP-2.4 implementation state).
4. ✅ IP-2 evidence-log row added (2026-07-20) and an **IP-2.9**
   implementation-state subsection recorded; test counts noted as
   branch-pending (347 / 343), not overwriting the merged-main baseline.
5. ✅ The now-false IP-2.8 prose and the IP-2 non-goal line scoped to the
   unverified case.
6. ✅ **MC-2.5** added: real Brevo/SMTP config, sender-domain DKIM/SPF, staging
   delivery + verify-page, on-device banner/resend proof.

---

## Recent delivery — reconciled into the plan 2026-07-21

**IP-2.4 password recovery** — backend `34a14a9` + frontend `6b7dc97` on branch
**`feat/email-verification`** (same branch as IP-2.9; PR pending). Backend **364**
Jest tests pass; Flutter **347** tests pass. Recovery is now repository-delivered,
so IP-2.4 has two of its three slices done (profile + recovery); **account
deletion** is the only remaining slice.

| Impact | Detail |
| --- | --- |
| **Delivers IP-2.4 password recovery** | Anti-enumerating `POST /password-reset/request` (missing/Google-only/60s-cooldown all resolve to one generic success, email sent post-commit best-effort, token/recipient never logged); one-transaction `resetPassword` with a single-use 30-minute digest that revokes every session and refuses to add a password to a Google-only account, all failures collapsing to `AUTH_VERIFICATION_TOKEN_INVALID`; a deep-link-free backend web form (`GET`/`POST /password-reset`, tightened CSP + `no-referrer`); and a Flutter `forgot_password` screen wired from the login link. |
| **Reuses IP-2.9 primitives, not a new table** | An additive `ALTER TYPE ... ADD VALUE IF NOT EXISTS 'PASSWORD_RESET'` migration (`20260721000000`) extends the hashed-token store; `@@unique([userId,purpose])` keeps verification and reset tokens independent. No separate reset table is introduced. |
| **Closes the IP-2.8 Google-only concern** | The reset's `password IS NOT NULL` guard means recovery cannot silently password-enable a Google-only account. |
| **Extends a manual gate, not the count** | At this 2026-07-21 snapshot, recovery's production exposure and real reset-email/flow proof folded into **MC-2.5** (same Brevo provider), so the then-current 0-of-31 manual-gate count was unchanged and address-dimension limiting still belonged to IP-2.6. The 2026-07-27 slice below subsequently delivered that budget and added MC-2.6, bringing the current register to 32 gates. |

## Recent delivery — reconciled into the plan 2026-07-27

**IP-2.6 abuse-control slice** — branch **`feat/api-abuse-controls`**. Backend
**452** Jest tests pass (7 real-PostgreSQL cases intentionally skipped), up from
373 on main; Flutter **355** tests pass, up from 347. Production build and the
built-ESM smoke pass, and the smoke now supplies the newly required production
CORS variable, so it proves the built artifact reads it.

| Impact | Detail |
| --- | --- |
| **Closes the "no rate limits and permissive CORS" audit finding at code level** | `app.use(cors())` becomes an exact-match `CORS_ALLOWED_ORIGINS` allowlist, required and https-only under `NODE_ENV=production` and validated before the listener binds; wildcards, paths, and credentials in entries are rejected, and `Access-Control-Allow-Credentials` is never sent because the API is bearer-authenticated. In-process sliding-window budgets cover login (5 failed / account+address / 15 min), register (5 / address / hour), recovery request (3 / account+address / hour), password change (5 / account / hour), plus Google exchange, reset submission, and verification resend. Login carries an added second ceiling of 20 failed attempts per address / 15 min: the account+address key bounds guessing one account's password but would never trip against credential spraying, where every attempt names a different account and mints a fresh key. |
| **Makes the limits actually bind** | `TRUST_PROXY_HOPS` drives `trust proxy` and defaults to 0, so a forged `X-Forwarded-For` cannot select a limiter key; a test rotates the header and proves it buys no budget. Budgets are charged on admission and refunded when a `client_failures` response turns out not to be a 4xx — an adversarial review probe showed that deciding at response time instead admitted 40 concurrent guesses against a limit of 5, and a regression test now pins that burst at exactly 5. A 5xx outage never spends a caller's budget, and rejections are not charged so a limited key recovers on schedule rather than being pushed forward by continued abuse. |
| **Advances typed errors (item 4)** | `AUTH_RATE_LIMITED` joins the typed auth codes. The mounted activity-image controller stops choosing an HTTP status by comparing `error.message` to exact English sentences and raises typed `ActivityImageServiceError` values instead; its 500 branch no longer logs the raw error object, which could carry a presigned URL. The unmounted social controllers still branch on message strings. |
| **Adds privacy-safe observability (item 5)** | Server-minted `X-Request-Id` on every response, ignoring any inbound header so a client cannot forge a log trail. Rate-limit rejections emit one JSON `security_event` line built from a fixed allowlisted field set — never a spread of caller input — with identifying values reduced to a truncated SHA-256 digest. |
| **Required Flutter error handling** | `AUTH_RATE_LIMITED` now renders a stable wait-and-retry message instead of the raw `HttpStatusException(429): …` string. The final follow-up also maps `AUTH_INVALID_CREDENTIALS` explicitly and reads the clean message carried by typed exceptions, fixing the real login failure text `UnauthorizedInvalid username or password` and making unmapped future codes degrade without exposing a class name or status line. |
| **Adds one manual gate** | **MC-2.6**: recorded proxy depth tied to the real hosting proxy, recorded production origins with allow/deny probes, a fail-closed boot smoke, a live 429-and-recovery run, and confirmation the deployment still runs exactly one replica. The limiter is in-process, so restart clears counters and a second replica would multiply every limit. |
| **Does NOT close IP-2.6** | Storage-boundary items 6–8 are untouched: the activity-image grant still cannot enforce size at the storage boundary (avatars already can, from IP-0.4), confirmation still trusts declared metadata, and there are no per-user object/byte quotas, abandoned-upload cleanup, or volume alarms. |

## Next actionable repository work

Lowest-numbered unblocked packages (operational IP-0 gates run in parallel but
are not substitutes):

1. **IP-2.6 storage boundary (items 6–8)** — an enforceable activity-image
   upload grant, confirmation against actual `ContentType`/`ContentLength`/
   checksum, per-user object/count/byte quotas, abandoned-upload lifecycle
   cleanup, and presign/storage volume alarms. Changing the grant alters the
   client upload contract, so it needs a coordinated Flutter change and
   real-storage proof.
2. **IP-2.4 account deletion** — pending the retention/reauth decision, then
   transactional revocation + durable object-cleanup outbox/runner + full
   local+remote purge. (Password recovery and IP-2.5 route privacy are now
   merged to main — see the "Recent delivery" sections above.)
3. **IP-2.7 retained-data protection** — gated on the owner design spike
   (threat model, library/perf, backup/key-loss recovery).

_Last regenerated: 2026-07-27 (from phase files at 2026-07-17; plan reconciled
with the IP-2.9 delivery 2026-07-20, the IP-2.4 password-recovery + IP-2.5
route-privacy deliveries 2026-07-21, and the IP-2.6 abuse-control slice
2026-07-27). The IP-2.9 email-verification (PR #164) and IP-2.5 route-privacy
(PR #165) branches are merged to main; the "branch / PR pending" wording in the
dated snapshots above is historical (true at the snapshot date). The IP-2.6
abuse-control slice is on branch `feat/api-abuse-controls` and not yet merged._
