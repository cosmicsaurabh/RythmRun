---
published: false
---

# RythmRun improvement program — status tracker

A single-page roll-up of every improvement phase, its work packages, and the
open manual/hosted gates. It is derived from the phase files at their
`Last updated: 2026-07-17` state, plus the reconciliation of the 2026-07-20
email-verification delivery (see the final section).

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
| IP-2 Auth, account, privacy | **In progress** | 4 of 8 (+ IP-2.4 profile slice only) | IP-2.5, 2.6, 2.7 | MC-2.1–2.4 |
| IP-3 Workout durability | **Planned** | 0 of 5 | all | — |
| IP-4 Sync & restore | **Planned** | 0 of 6 | all | — |
| IP-5 Release readiness | **Planned** | 0 of 7 | all (5.7 Deferred) | — |

**Manual/hosted checks: 0 of 29 verified** (28 pending, MC-0.10 blocked). No
package can reach `Complete` until its gates carry dated evidence.

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
| IP-2.4 Profile, password recovery, account deletion | **In progress** | partial | **Only the profile slice is delivered.** Password recovery: prerequisite now unblocked (see below) — reset endpoints/UI still to build. Account deletion: still blocked on the retention/reauth decision, then transactional revocation + durable object-cleanup outbox/runner + full local+remote purge. |
| IP-2.5 Private routes; disable social | Planned | ✗ | Not started. Default `isPublic=false`, one-way migrate existing rows to private, owner-only exact-route/image detail, unmount friend/comment/like paths. |
| IP-2.6 API abuse controls & typed errors | Planned | ✗ | Not started. CORS allowlist, rate limits (login/register/recovery/password/**Google exchange**), finish typed error mapping, storage size/type/integrity + abandoned-upload cleanup. |
| IP-2.7 Protect retained routes/photos at rest | Planned | ✗ | Not started; gated on an owner design spike (threat model, library/perf, backup/key-loss recovery) before migrating SQLite + photos to user-scoped at-rest protection. |
| IP-2.8 Google identity extension | Verification | ✓ | Merged `c805f62`. Left: MC-2.4 non-rolling migration, OAuth-console/signing, provider, device, staging, branding proof. **Note: partially superseded by the 2026-07-20 delivery below.** |

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

## Manual / hosted gates — 0 of 29 verified

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
  · MC-2.4 Google identity migration/provider/device.
- **Product-data analysis:** MC-1.1 legacy metric sampling · MC-1.4 rollout
  observation.

---

## ⚠ Recent delivery not yet folded into the plan

**Email verification + safe Google account linking** — 7 commits
(`7432e9c`…`4f0983f`) on branch **`feat/email-verification`** (not yet merged;
PR pending). Backend **347** Jest tests pass; Flutter **343** tests pass. The
plan predates this work and is now partly inaccurate. Per program rule 6 and
maintenance step 4, the plan should be updated to match shipped code.

### What it changes in the plan

| Impact | Detail |
| --- | --- |
| **Resolves an owner decision** | "Password-recovery email provider and sender domain" → **Brevo** free SMTP relay (300/day, no card) + **reshapeapp.ai** sender domain, feature-flagged, tokens stored SHA-256-digest-only and never logged. Move this row from *Decisions that still require an owner* → *Decisions already made*. |
| **Unblocks IP-2.4 password recovery** | The provider prerequisite is cleared and the reusable primitives are delivered: the `VerificationToken` table (single-use `consumedAt`, `expiresAt`, unique `(userId,purpose)`, sweep-timer purge) and a `VerificationTokenPurpose` enum explicitly built to add `PASSWORD_RESET`. Only the reset endpoints/UI remain. Account **deletion** stays blocked on its own retention/reauth decision. |
| **Contradicts D-017** | D-017 says the system "never implicitly links an existing password account by email" — now false. `googleLogin()` auto-links when `emailVerified === true` **and** `googleSubject === null` (race-safe `updateMany` + revoke other sessions), else `AUTH_EMAIL_UNVERIFIED_CONFLICT` (409). **Amend, don't delete** — the rationale ("email alone is not safe proof") holds; both sides now prove the same mailbox. |
| **Falsifies IP-2.8 prose** | "refuses implicit linking when a password account owns the email" and "explicit account linking is not implemented" now hold only for the **unverified** case. Scope both to unverified; note verified-email safe linking is delivered. The IP-2 non-goal "implicit email-based account linking" needs the same verified/unverified split. |
| **New capability the plan has no concept of** | `User.emailVerified` + hash-at-rest `VerificationToken`; migration `20260718000000` backfills `emailVerified=true` only where `googleSubject IS NOT NULL` (never blanket-verifies password rows); post-commit best-effort send; public idempotent `GET /verify-email` (CSP + `no-referrer`); throttled `POST /verify-email/resend`; optional SMTP feature flag; Flutter banner (unverified password accounts only) + `/me` refresh + new error-code mapping. |

### Suggested plan edits (not yet applied)

1. Amend **D-017** to the shipped gated-linking rule; add **D-018** for the
   email-verification policy (register never verifies; verification is the
   prerequisite that makes auto-link safe; backfill only Google rows; Flutter
   defaults `emailVerified=true` as deliberate fail-open compat).
2. Move the email-provider row into *Decisions already made*.
3. Update the four "blocked on the email-provider decision" statements
   (README program status, README next-steps #1, IP-2 header *External
   prerequisites*, IP-2.4 implementation state) — prerequisite resolved.
4. Add a dated IP-2 evidence-log row (~2026-07-20) and an implementation-state
   subsection (new **IP-2.9** or an IP-2.8 extension) for the delivery; refresh
   the test-count baselines (backend 347 / Flutter 343) and re-check the
   analyzer baseline for the new banner/error-mapping code.
5. Fix the now-false IP-2.8 prose and the IP-2 non-goal line.
6. Add a manual gate (extend **MC-2.4** or add **MC-2.5**): real Brevo/SMTP
   config, sender-domain DKIM/SPF, staging delivery + verify-page, on-device
   banner/resend proof.

---

## Next actionable repository work

Lowest-numbered unblocked packages (operational IP-0 gates run in parallel but
are not substitutes):

1. **Reconcile this plan** with the email-verification delivery (the 6 edits
   above) — cheap, and the plan's own rules require it.
2. **IP-2.4 password recovery** — now unblocked; reuse the delivered token/
   email plumbing.
3. **IP-2.4 account deletion** — pending the retention/reauth decision.
4. **IP-2.5 route privacy** — default activities private; owner-only detail;
   unmount social paths.
5. **IP-2.6 abuse controls** — CORS + rate limiting (including the Google and
   the new verify/resend endpoints) + typed errors + upload integrity.

_Last regenerated: 2026-07-20 (from phase files at 2026-07-17)._
