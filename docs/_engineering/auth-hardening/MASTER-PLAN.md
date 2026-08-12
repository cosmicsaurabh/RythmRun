---
published: false
---

# Auth Hardening & Tunable Timing — Master Plan

**Status:** Phases 0–2 done · Phase 3 complete (3a + 3b) — awaiting review · **Owner:** maintainer · **Created:** 2026-08-11
**Source:** auth + refresh audit (16 confirmed findings, 1 plausible, 2 refuted)
**Relationship to the improvement program:** this is IP-2 follow-up work. It does
not replace `IP-2-auth-account-privacy.md`; when a phase here lands, its evidence
row goes into `STATUS.md` and this file shrinks. Delete this file when the
tracker below is fully checked.

---

## 0 · Charter

### What we are building

Two things, deliberately bundled because the first makes the second testable:

1. **A configuration spine** — every auth timing constant becomes a tunable knob
   instead of a hardcoded literal, so real-world scenarios can be forced on a
   deployed system in minutes rather than simulated in tests.
2. **The audit fixes** — 16 confirmed defects in the seams around a fundamentally
   sound design.

### Why the config comes first

You cannot honestly verify "does a lost refresh response recover correctly?"
against a 15-minute access token and a 7-day session. With
`ACCESS_TOKEN_TTL_SECONDS=30`, that scenario reproduces on demand.

**Phase 0 is the test harness for Phases 2–6.**

### Scope

- ✅ Backend auth timing, session policy, abuse budgets
- ✅ Client offline-admission policy and request timeout
- ✅ The 16 confirmed + 1 plausible audit findings
- ✅ Docs kept truthful in the same commits

### The clean-code dividend (no backward compatibility)

There are **no production users**, so nothing must keep an old installed app
working. That is not just permission to skip migration guards — it is a mandate
to **delete every line that exists only for backward compatibility.** Two piles
qualify, both verified in code:

- **Legacy-token migration + `requiresServerVerification`** — 43 references across
  5 files (`auth_persistence_service.dart`, `auth_token_store.dart`,
  `authenticated_request_coordinator.dart`, `auth_local_datasource.dart`,
  `auth_repository_impl.dart`). It migrates plaintext SharedPreferences tokens
  from a pre-Keystore build. Nobody holds those tokens. Deleting it also
  **de-tangles the M2 fix** — the verification-stamp branch is the seam.
- **The `code`/`error` heuristic** — the client guesses whether the backend's
  `error` string is a stable code via a regex. Backend sends `code`, client reads
  `code`, regex and dead `error` fallback both go.

> **Not on the table: rewriting auth from scratch.** The audit confirmed the core
> crypto and session model are sound, protected by 464 backend + 359 client tests.
> A rewrite discards working, tested machinery to fix problems that live in the
> seams. We simplify and delete; we do not rebuild.

### Non-goals

- ❌ No DB migrations — no finding needs a schema change (not a compat rule; just true)
- ❌ No new dependencies (the backend dependency surface is deliberately minimal)
- ❌ Not touching IP-2.7 local-DB encryption (design spike owned elsewhere)
- ❌ Not touching `local_db_service.dart` SQLite schema versioning — that is real
  data evolution, not compat cruft
- ❌ Not reviving the unmounted friend/comment/like routers (D-007)

### Operating constraints that shape every decision

| Constraint | Consequence |
| --- | --- |
| No production users | Ship backend + client together; change any wire shape freely; delete compat code |
| Single user (the maintainer) | Severity is calibrated to real damage, not checklist weight |
| Android-only (D-008) | iOS paths are not release scope |
| Clean code for one reader | Prefer deleting a seam over guarding it |

---

## 1 · HLD

### 1.1 System shape

```
┌──────────────────────────┐        HTTPS/JSON        ┌──────────────────────────┐
│  Flutter app (Android)   │ ───────────────────────► │  Express 5 · Node 22 ESM │
│                          │                          │                          │
│  SecureAuthTokenStore    │  Bearer <access JWT>     │  authMiddleware          │
│   └ Keystore envelope    │                          │   └ verify + DB session  │
│     · pair               │                          │                          │
│     · revision (CAS)     │  POST /refresh-token     │  AuthSessionService      │
│     · lastVerifiedAtMs   │  { refreshToken }        │   └ rotate / revoke      │
│                          │ ◄─────────────────────── │                          │
│  RequestCoordinator      │  new pair                │  UserService             │
│   └ single-flight        │                          │   └ register/login/reset │
│   └ replay policy        │                          │                          │
└──────────────────────────┘                          └────────────┬─────────────┘
                                                                   │
                                                      ┌────────────▼─────────────┐
                                                      │ PostgreSQL (Prisma 7.8)  │
                                                      │  AuthSession             │
                                                      │  RefreshTokenRecord      │
                                                      │  VerificationToken       │
                                                      │  ObjectCleanupJob        │
                                                      └──────────────────────────┘
```

### 1.2 Data flow — the life of a session

**Issue.** Login/register runs bcrypt, then one serializable transaction: sweep
expired sessions → enforce the active-session cap → create `AuthSession` +
`RefreshTokenRecord`. Returns two HS256 JWTs signed with **separate secrets**.

**Use.** Every authenticated request carries `Authorization: Bearer <access>`.
The middleware verifies the JWT *and* looks up the session row — so revocation
is immediate and the JWT alone is never sufficient.

**Refresh.** The client's coordinator single-flights by credential revision.
The server validates the presented token by SHA-256 digest, marks it consumed,
mints a new pair on the **same session**, and links old → new. Reuse of a
consumed token revokes the whole session.

**Die.** Three exits — voluntary logout (revokes the session server-side),
forced loss (refresh rejected / session revoked elsewhere), and account deletion
(cascades every auth row). Access tokens die instantly in all three because the
per-request session lookup finds no `ACTIVE` row.

### 1.3 The configuration spine (new)

```
        BACKEND                                    CLIENT
        ───────                                    ──────
  env vars (runtime)                        --dart-define (compile-time)
        │                                             │
        ├─ ACCESS_TOKEN_TTL_SECONDS ──┐               ├─ OFFLINE_WINDOW_HOURS
        ├─ REFRESH_SESSION_TTL_SECONDS┤               ├─ CLOCK_SKEW_TOLERANCE_SECONDS
        ├─ MAX_ACTIVE_SESSIONS        │               ├─ BACKEND_SYNC_INTERVAL_HOURS
        ├─ REFRESH_REUSE_GRACE_SECONDS│               └─ REQUEST_TIMEOUT_MS
        ├─ *_TTL_SECONDS (tokens)     │
        └─ *_COOLDOWN_SECONDS         │
                                      │
                                 JWT `exp` claim
                                      │
                                      ▼
                    client reads expiry from the token itself
                    (JwtDecoder.isExpired — no client constant)
```

**The load-bearing insight:** the client never hardcodes token lifetimes. It reads
`exp` out of the JWT (`auth_persistence_service.dart:200,210-211,344`). So
**changing a backend TTL env var immediately changes the installed app's refresh
cadence — no rebuild, no reinstall.**

That splits the two knob families cleanly:

| Family | Mechanism | Changing it requires | Use for |
| --- | --- | --- | --- |
| **Token/session timing** | Backend env var | Env change + restart | Live testing against the installed app |
| **Client policy** | `--dart-define` | A test build + install | Offline grace, skew, sync cadence, timeout |

### 1.4 Phase order (no deploy asymmetry to respect)

With no installed app to keep alive, backend and client changes ship together per
phase. Order is driven by **build logic**, not deploy safety: config first because
it is the test harness; simplification before the fixes that touch the same code;
error-contract rename as one atomic both-sides change.

---

## 2 · LLD

### 2.1 Database schema — reference only, **zero migrations**

No finding in this plan requires a schema change. The grace window (Phase 2)
reuses columns that already exist. Recorded here so the runbook is self-contained.

**`AuthSession`** — one row per signed-in device.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` PK | becomes the JWT `sid` claim |
| `userId` | `int` FK → User | `onDelete: Cascade` |
| `familyId` | `uuid` unique | write-only vestige; 1:1 with `id` |
| `status` | `AuthSessionStatus` | `ACTIVE` \| `REVOKED`, default `ACTIVE` |
| `createdAt` / `lastUsedAt` | `timestamp` | `lastUsedAt` touched on each rotation |
| `expiresAt` | `timestamp` | `createdAt + REFRESH_SESSION_TTL`; **absolute, never extended** |
| `revokedAt` | `timestamp?` | set on revoke |

Indexes: `[userId,status,expiresAt]`, `[familyId,status]`, `[status,expiresAt]`, `[expiresAt]`

**`RefreshTokenRecord`** — one row per issued refresh token.

| Field | Type | Notes |
| --- | --- | --- |
| `jti` | `uuid` PK | matches the JWT `jti` claim |
| `sessionId` | `uuid` FK → AuthSession | `onDelete: Cascade` |
| `tokenDigest` | `char(64)` unique | SHA-256 hex of the raw refresh JWT — the token itself is never stored |
| `issuedAt` / `expiresAt` | `timestamp` | `expiresAt` = the session's |
| `usedAt` | `timestamp?` | single-use consumption marker |
| `revokedAt` | `timestamp?` | set on revoke |
| `replacedByJti` | `uuid?` unique | self-relation forming the rotation chain — **Phase 2 reads this** |

Indexes: `[sessionId,usedAt,revokedAt]`, `[expiresAt]`

**`VerificationToken`** — email verification + password reset share one table.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `cuid` PK | |
| `userId` | `int` FK | `onDelete: Cascade` |
| `purpose` | `enum` | `EMAIL_VERIFICATION` \| `PASSWORD_RESET` — **Phase 5 starts checking this on the verify path** |
| `tokenDigest` | `char(64)` unique | shared digest namespace across both purposes |
| `expiresAt` / `consumedAt` / `lastSentAt` | `timestamp` | `lastSentAt` anchors the cooldown |

Constraint: `@@unique([userId, purpose])` → at most one live token per user per purpose.

**`ObjectCleanupJob`** — deletion outbox. No FK to User (rows must outlive the user).

| Field | Type | Notes |
| --- | --- | --- |
| `status` | `enum` | `PENDING` \| `PROCESSING` \| `COMPLETED` \| `FAILED` |
| `bucket` / `key` | `text` | explicit bucket per job |
| `attempts` / `nextAttemptAt` | `int` / `timestamp` | exponential backoff `2^n · 10s`, `FAILED` at 5 |

### 2.2 Configuration contract — backend env vars

All new. **Every default equals today's hardcoded value, so behavior is unchanged
until a variable is set.** All are optional; absent → default.

| Variable | Default | Bounds | Replaces |
| --- | --- | --- | --- |
| `ACCESS_TOKEN_TTL_SECONDS` | `900` (15m) | 30 … 86400 | `ACCESS_TOKEN_LIFETIME_SECONDS` |
| `REFRESH_SESSION_TTL_SECONDS` | `604800` (7d) | 60 … 7776000 | `REFRESH_SESSION_LIFETIME_SECONDS` |
| `MAX_ACTIVE_SESSIONS_PER_USER` | `5` | 1 … 100 | same-named const |
| `REFRESH_REUSE_GRACE_SECONDS` | `60` | 0 … 300 | **new** (Phase 2); `0` = strict, no grace |
| `EMAIL_VERIFICATION_TTL_SECONDS` | `86400` (24h) | 60 … 604800 | `VERIFICATION_TOKEN_TTL_MS` |
| `EMAIL_VERIFICATION_COOLDOWN_SECONDS` | `60` | 0 … 3600 | `VERIFICATION_RESEND_COOLDOWN_MS` |
| `PASSWORD_RESET_TTL_SECONDS` | `1800` (30m) | 60 … 86400 | `PASSWORD_RESET_TTL_MS` |
| `PASSWORD_RESET_COOLDOWN_SECONDS` | `60` | 0 … 3600 | `PASSWORD_RESET_COOLDOWN_MS` |
| `RETRY_SWEEP_INTERVAL_SECONDS` | `900` (15m) | 10 … 86400 | `server.ts` literal |

**Parsing.** One shared helper in `env.ts`, following the existing
`parseTrustProxyHops` shape:

```ts
function parseIntEnv(
  source: EnvironmentSource,
  name: string,
  { fallback, min, max }: { fallback: number; min: number; max: number },
): number {
  const raw = source[name];
  if (raw === undefined || raw.trim().length === 0) return fallback;

  const value = Number(raw.trim());
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new EnvironmentValidationError(
      `${name} must be an integer between ${min} and ${max}`,
    );
  }
  return value;
}
```

Bounds are typo protection, not policy — `ACCESS_TOKEN_TTL_SECONDS=9000000` should
fail at boot, not silently mint a 3-month token. Boot is already fail-closed
(`loadAndValidateEnvironment` at `server.ts:114`).

**New exported type** in `env.ts`, resolved once at boot and injected:

```ts
export interface AuthTimingEnvironment {
  accessTokenTtlSeconds: number;
  refreshSessionTtlSeconds: number;
  maxActiveSessionsPerUser: number;
  refreshReuseGraceSeconds: number;
  emailVerificationTtlSeconds: number;
  emailVerificationCooldownSeconds: number;
  passwordResetTtlSeconds: number;
  passwordResetCooldownSeconds: number;
}
```

Registered in the DI container as `'AuthTiming'`, consumed by `AuthSessionService`
and `UserService`.

**`RETRY_SWEEP_INTERVAL_SECONDS` is deliberately not in this interface.** It
configures the sweep timer in `server.ts` and no service reads it, so it is parsed
directly at bootstrap (`options.retryIntervalMs`) rather than injected.

**Injection is required, not optional.** Export a `DEFAULT_AUTH_TIMING` constant
(today's values) and make the constructor param a required, non-null field read as
`this.authTiming.accessTokenTtlSeconds` — one path, no `?? CONST` fallbacks in
method bodies. The ~20 manual `new AuthSessionService(...)` / `new UserService(...)`
call sites in tests pass `DEFAULT_AUTH_TIMING` explicitly. We update the tests; we
do not weaken the constructor to protect them.

### 2.3 Configuration contract — frontend `--dart-define`

Compile-time. Same pattern the app already uses for `APP_ENV` and `ADS_*`.

| Define | Default | Replaces |
| --- | --- | --- |
| `OFFLINE_WINDOW_HOURS` | `168` (7d) | `AuthPersistenceService.offlineWindow` |
| `CLOCK_SKEW_TOLERANCE_SECONDS` | `120` (2m) | `AuthPersistenceService.clockSkewTolerance` |
| `BACKEND_SYNC_INTERVAL_HOURS` | `168` (7d) | `needsBackendSync` default parameter |
| `REQUEST_TIMEOUT_MS` | per-env map | `AppConfig._timeouts` lookup |

Shape (must stay `const` — `int.fromEnvironment` is compile-time):

```dart
/// Maximum offline access after a successful server verification (D-009).
/// Override with --dart-define=OFFLINE_WINDOW_HOURS=<n> to force the
/// re-verification path in a test build.
static const int _offlineWindowHours =
    int.fromEnvironment('OFFLINE_WINDOW_HOURS', defaultValue: 168);
static const Duration offlineWindow = Duration(hours: _offlineWindowHours);
```

**Explicit limitation, documented for the reader:** these are baked into the
binary. They cannot be changed on an installed Play build — that is what makes
the backend knobs the primary live-testing lever.

### 2.4 API contracts

Base path `/api/users`. One contract change: the error envelope's `error` field
becomes `code` in Phase 4 (both sides, same commit).

**`POST /login`** · **`POST /register`** · **`POST /refresh-token`** — all return
the same `AuthResponse`:

```jsonc
// POST /api/users/login   { "username": "a@b.com", "password": "..." }
// POST /api/users/refresh-token   { "refreshToken": "<refresh JWT>" }
// 200 OK
{
  "id": "1",
  "username": "a@b.com",
  "firstname": "Sam",
  "lastname": "Reshape",
  "profilePicturePath": "avatars/1/abc.jpg",
  "profilePictureType": "image/jpeg",
  "hasPassword": true,
  "emailVerified": true,
  "accessToken":  "<HS256 JWT · typ=access · exp=iat+ACCESS_TOKEN_TTL>",
  "refreshToken": "<HS256 JWT · typ=refresh · exp=session.expiresAt>"
}
```

JWT claims (both tokens):

```jsonc
{ "sub": "1", "sid": "<session uuid>", "jti": "<token uuid>",
  "typ": "access" | "refresh", "iat": 1770000000, "exp": 1770000900 }
```

**`DELETE /me`** — re-auth is mandatory; the branch is chosen by whether the
account has a password, not by which field the client sends.

```jsonc
// password account
{ "password": "..." }
// google-only account
{ "googleIdToken": "..." }
// 200 OK  → { "status": "success", "message": "Account deleted" }
```

**Error envelope** — the stable code lives in `error`:

```jsonc
// 401
{
  "error": "AUTH_REFRESH_INVALID",
  "message": "Refresh session is invalid",
  "retryable": false,
  "statusCode": 401,
  "timestamp": "2026-08-11T10:00:00.000Z"
}
```

**Phase 4 renames the field to `"code"`** (drops `"error"` entirely). The client
reads `code` directly; the `_looksLikeStableErrorCode` regex and the dead `error`
fallback are deleted. One field, one meaning, both sides in the same commit.

```jsonc
// after Phase 4
{ "code": "AUTH_REFRESH_INVALID", "message": "Refresh session is invalid",
  "retryable": false, "statusCode": 401, "timestamp": "..." }
```

### 2.5 Refresh rotation state machine — with the Phase 2 grace window

Current behavior on the left, the change on the right. **Everything except the
boxed branch is unchanged.**

```
presented refresh token
        │
        ▼
  verify HS256 · typ=refresh · claim shape ──► fail ──► 401 AUTH_REFRESH_INVALID
        │
        ▼
  find record by jti · digest must match · sid/sub must match ──► fail ──► 401
        │
        ▼
  ┌─────────────────── record.usedAt != null ? ───────────────────┐
  │                                                               │
  │  ┌─────────────────── NEW in Phase 2 ─────────────────────┐   │
  │  │  within REFRESH_REUSE_GRACE_SECONDS                    │   │
  │  │        AND successor (replacedByJti) exists            │   │
  │  │        AND successor is unused + unrevoked + unexpired │   │
  │  │                        │                               │   │
  │  │            yes ────────┴──── no                        │   │
  │  │             │                 │                        │   │
  │  │             ▼                 ▼                        │   │
  │  │   LOST-RESPONSE RETRY    TRUE REUSE (unchanged)        │   │
  │  │   revoke successor only  revoke ENTIRE session         │   │
  │  │   mint a fresh pair      401 AUTH_REFRESH_INVALID      │   │
  │  │   link successor→new                                   │   │
  │  └────────────────────────────────────────────────────────┘   │
  └───────────────────────────────────────────────────────────────┘
        │ (usedAt == null — the normal path, unchanged)
        ▼
  reject if revoked / expired / session not ACTIVE
        ▼
  touch session.lastUsedAt · consume (usedAt = now) · mint pair · link old→new
```

**Why this is safe.** The successor is revoked in the same transaction, so exactly
one live refresh token per session is preserved. If the successor was *already
used*, the legitimate client received and spent it — a re-presentation of the
older token is then genuine reuse and still kills the family. Setting
`REFRESH_REUSE_GRACE_SECONDS=0` disables the branch entirely, which is how the
theft path gets tested.

**Backward compatible.** Backend-only; the released app benefits with no change.

---

## 3 · Implementation Runbook

Seven phases. **Each ends at a stop point with a commit message.** Phases 0–2 and
5 are backend-only and independently deployable; 3–4 and 6 are client work that
rides the next Play release.

---

### Phase 0 — Configuration spine `[backend + client]`

**Goal:** every timing constant becomes tunable. Zero behavior change at defaults.

**Backend files**
- `src/config/env.ts` — add `parseIntEnv`, `AuthTimingEnvironment`, `parseAuthTiming`, export from `loadAndValidateEnvironment`
- `src/config/container.ts` — register `'AuthTiming'`
- `src/server.ts` — pass timing into `configureContainer`; use `RETRY_SWEEP_INTERVAL_SECONDS`
- `src/services/auth-session.service.ts` — inject timing, replace the three consts at their use sites
- `src/services/user.service.ts` — inject timing, replace the four TTL/cooldown consts
- `.env.example` — document all nine with defaults and bounds

**Client files**
- `lib/core/services/auth_persistence_service.dart` — `offlineWindow`, `clockSkewTolerance`, `needsBackendSync` default
- `lib/core/config/app_config.dart` — `REQUEST_TIMEOUT_MS` override
- `CONFIGURATION.md` — new "Auth timing overrides" section

**Steps**
0. Lock the true test baseline first (`npm test`, `flutter test --no-pub`) — record the real pass/skip/total so a later regression is unambiguous.
1. Backend: add `parseIntEnv`, `AuthTimingEnvironment`, `parseAuthTiming`, and `DEFAULT_AUTH_TIMING` (today's values) in `env.ts`.
2. Backend: `RETRY_SWEEP_INTERVAL_SECONDS` is parsed in `server.ts` bootstrap, not the injected type.
3. Backend: inject `'AuthTiming'` as a **required, non-null** param into both services; update the ~20 `new …Service(...)` test call sites to pass `DEFAULT_AUTH_TIMING`. No optional params, no `?? CONST` fallbacks.
4. Backend: add `env.test.ts` cases — default, valid override, out-of-bounds rejection.
5. Client: convert the four constants to `fromEnvironment` with today's values as defaults.
6. Docs: `.env.example` + `CONFIGURATION.md`.

**Verification**
```bash
cd RythmRun_backend_nodejs && npx prisma generate && npm run typecheck && npm test && npm run build && npm run smoke:runtime
```
```bash
cd rythmrun_frontend_flutter && flutter test --no-pub && flutter analyze --no-pub --no-fatal-infos
```
Manual proof the knob works:
```bash
ACCESS_TOKEN_TTL_SECONDS=30 npm run dev
```
Sign in, wait 30s, make a request → expect exactly one refresh and a successful retry.

**⛔ STOP — review + commit**

---

### Phase 1 — Backend containment `[backend only]`

**Fixes M5, M3.** Both tiny, both high value, neither touches the client.

**M5 — schedule the object-cleanup runner**
- `src/config/container.ts` — register `ObjectCleanupRunner`
- `src/server.ts` — add a fifth `runRetry('Object cleanup', …)` to the sweep interval
- `src/services/user.service.ts` — resolve the runner from DI instead of `new`

**M3 — rate-limit `DELETE /me`**
- `src/config/rate-limits.ts` — add `accountDeletion: { limit: 5, windowMs: HOUR_MS }`, rule keyed by `authenticatedAccount`, `count: 'all'`
- `src/routes/user.routes.ts:190` — mount it before `controller.deleteAccount`

**Verification**
```bash
cd RythmRun_backend_nodejs && npm run typecheck && npm test && npm run build && npm run smoke:runtime
```
New tests: a stranded `PENDING` job is picked up by the sweep; the 6th failed deletion re-auth in an hour returns `429 AUTH_RATE_LIMITED`.

**⛔ STOP — review + commit**

---

### Phase 2 — Refresh rotation grace window `[backend only]`

**Fixes M1.** Uses Phase 0's knobs to test.

- `src/services/auth-session.service.ts` — insert the grace branch at the `usedAt != null` check (§2.5)
- Revoke the successor, mint a fresh pair, link `successor.replacedByJti → new`

**Verification**
```bash
cd RythmRun_backend_nodejs && npm run typecheck && npm test && npm run build
```
New tests: (a) re-presenting a token whose successor is unused, inside the window → new pair, session stays `ACTIVE`; (b) successor already used → whole session revoked; (c) outside the window → revoked; (d) `REFRESH_REUSE_GRACE_SECONDS=0` → always revoked.

Real-device proof: `ACCESS_TOKEN_TTL_SECONDS=30`, airplane-mode the device mid-refresh, restore connectivity → session survives.

**⛔ STOP — review + commit**

---

### Phase 3 — Client credential simplification `[client]`

Two stop points. Step 3a deletes the compat cruft; step 3b fixes the seams in the
now-simpler code. Doing them in this order means the M2 fix lands on code that no
longer has a verification-stamp branch to tiptoe around.

#### Step 3a — Delete legacy migration + `requiresServerVerification`

**Removes 43 references of backward-compat machinery.**

- `auth_token_store.dart` — drop `requiresServerVerification` from the envelope; delete `markServerVerified`
- `auth_persistence_service.dart` — delete the legacy plaintext migration (read/validate/decode), `legacyAccessTokenKey`/`legacyRefreshTokenKey`, and the `requiresServerVerification` branches; `canStayLoggedInOffline` keeps only the JWT-expiry + `lastVerifiedAtMs` window check; `validateSession` server-checks on `needsBackendSync()` alone
- `authenticated_request_coordinator.dart` — delete the verification-stamp branch in `_completeSuccessfulRequest` and `markCurrentCredentialsServerVerified`
- `auth_local_datasource.dart` / `auth_repository_impl.dart` — drop the pass-throughs

**Verification** — full client suite; delete the now-dead legacy-migration tests. Expect the test count to *drop* and the diff to be mostly red.

**⛔ STOP — review + commit**

#### Step 3b — Refresh seams `[client]`

**Fixes M2, A3, A4** — now on the simplified coordinator.

- `authenticated_request_coordinator.dart` — `_completeSuccessfulRequest` accepts a same-session rotation (compare `sid`/`sub` claims); throws only for a cleared vault or a different user. With 3a done, there is no verification-stamp special case left
- `authenticated_request_coordinator.dart:186` — evict a refresh flight as soon as it completes with an error
- `avatar_remote_datasource.dart:86` — add `replayPolicy: AuthenticatedReplayPolicy.idempotent`

**Verification**
```bash
cd rythmrun_frontend_flutter && flutter test --no-pub && flutter analyze --no-pub --no-fatal-infos && dart format --set-exit-if-changed <changed files>
```
New tests: a request completing across a rotation returns its result; a failed flight is not replayed to a later 401; the avatar path replays once.

**⛔ STOP — review + commit**

---

### Phase 4 — Error contract `[backend + client, one atomic change]`

**Fixes M4, C2, C3, C4, P1.**

- `user.controller.ts` — `sendError` emits `code` and **drops** `error`; add `retryable` to the deletion envelope
- `http_client.dart` — read `decodedBody['code']` directly; **delete** `_looksLikeStableErrorCode` and the `error` fallback
- `change_password_provider.dart:26` — route through `ErrorHandler.getErrorMessage`; typed `on AuthSessionFailure`
- `error_handler.dart` — add `AuthSessionFailure` branch; add arms for `AUTH_PASSWORD_INVALID`, `AUTH_PASSWORD_UNAVAILABLE`, `AUTH_USERNAME_TAKEN`; delete the dead string-branch block and the unreachable validation parser
- Backend boundary test asserting every auth error response carries a well-formed `code`

**Verification** — both suites, plus a manual wrong-current-password check showing curated text with no class name.

**⛔ STOP — review + commit**

---

### Phase 5 — Auth core hardening `[backend only]`

**Fixes B2, B3, B4, C5.**

- `user.service.ts` `changePassword` + Google auto-link — delete unconsumed `PASSWORD_RESET` tokens in the same transaction
- `user.service.ts` `verifyEmail` — reject a non-`EMAIL_VERIFICATION` purpose; add `purpose` to the guarded `updateMany`
- `user.service.ts` `login` — dummy-hash `bcrypt.compare` on the null-user branch to flatten timing
- `user.service.ts` `deleteAccount` — rethrow the Google 503 instead of collapsing it to 401

**Verification** — both suites, plus new tests for each of the four.

**⛔ STOP — review + commit**

---

### Phase 6 — Privacy follow-ups `[client + docs]`

**Fixes D3, D2.**

- `session_provider.dart:648` — move the best-effort Google sign-out into `_exitSession` so it runs on forced loss too
- `IP-2-auth-account-privacy.md` — add presigned-URL-at-rest to the IP-2.7 threat model (doc only; encryption stays with the spike)
- `STATUS.md` — evidence rows for every phase; delete this master plan

**⛔ STOP — final review + commit**

---

## 4 · Status Tracker

Legend: `[ ]` pending · `[~]` in progress · `[x]` done

### Phase 0 — Configuration spine
- [x] `parseIntEnv` helper + `AuthTimingEnvironment` in `env.ts`
- [x] Nine env vars parsed with defaults + bounds
- [x] DI registration + injection into `AuthSessionService` / `UserService`
- [x] `RETRY_SWEEP_INTERVAL_SECONDS` in `server.ts`
- [x] `.env.example` documented
- [x] Client: `offlineWindow`, `clockSkewTolerance`, `needsBackendSync`, `REQUEST_TIMEOUT_MS`
- [x] `CONFIGURATION.md` auth-timing section
- [~] Both suites green (automated ✅) · manual 30s-TTL proof is a maintainer deploy check

### Phase 1 — Backend containment
- [x] **M5** cleanup runner scheduled on the sweep (DI-resolved in `server.ts`); inline post-deletion kick removed so the sweep is the single drain path (also drops a raw-error log on a storage path)
- [x] **M3** `DELETE /me` rate limit — `accountDeletion` 5/hour, keyed by authenticated account, `count: 'all'`
- [x] Tests: sweep drains the outbox (server-bootstrap); 6th deletion re-auth in an hour → `429` (api-abuse-controls)

### Phase 2 — Refresh grace window
- [x] **M1** grace branch in `rotateRefreshToken` (revoke successor only + mint fresh pair on a lost-response retry; else kill the family)
- [x] Four rotation tests (grace / used successor / expired window / strict mode) — unit, all passing
- [~] Real-device airplane-mode proof is a maintainer deploy check (use `ACCESS_TOKEN_TTL_SECONDS=30`)

### Phase 3 — Client credential simplification
- [x] **3a** legacy migration + `requiresServerVerification` / `markServerVerified` deleted across 5 lib files (net −854 lines). Kept a simplified gate-protected `markCurrentCredentialsServerVerified` — its only surviving job is the sync-timer reset, not a verification stamp.
- [x] **3a** dead legacy-migration + verification-stamp tests removed (15 tests); suite green at 344, analyzer 9
- [x] **M2** same-session rotation accepted in `_completeSuccessfulRequest` — a request that succeeds while a concurrent refresh rotates the pair is no longer failed; only a cleared vault or a different `sid`/`sub` throws. Undecodable tokens fail closed.
- [x] **A3** failed refresh flights evicted the moment they error (a failing refresh never advances the revision, so the cached failure would otherwise be replayed to every overlapping request); a success stays cached until the last operation ends
- [x] **A4** `getUploadUrl` now sends `replayPolicy: idempotent` — a lost-response retry re-mints a presigned PUT + single-use intent instead of failing the upload
- [x] **3b** new tests: same-session rotation returns its result; different-session rotation rejected; failed flight evicted → later request retries fresh; avatar upload-url opts into idempotent replay. Suite 344 → 348, analyzer 9

### Phase 4 — Error contract
- [ ] **M4** change-password via `ErrorHandler`
- [ ] **C2** `AuthSessionFailure` branch
- [ ] **C3** `AUTH_USERNAME_TAKEN` arm + dead fallbacks deleted
- [ ] **C4** dead validation parser removed
- [ ] **P1** `error` field renamed to `code`; regex heuristic deleted; boundary test

### Phase 5 — Auth core hardening
- [ ] **B2** reset tokens killed on password change
- [ ] **B3** `verifyEmail` purpose check
- [ ] **B4** login timing flattened
- [ ] **C5** Google 503 passes through deletion

### Phase 6 — Privacy follow-ups
- [ ] **D3** Google sign-out on forced loss
- [ ] **D2** IP-2.7 threat-model note
- [ ] `STATUS.md` evidence rows · this file deleted

### Carried forward, not in scope
- [ ] IP-2.7 local-DB encryption (owner design spike)
- [ ] MC-2.1 — prove the 7 PostgreSQL tests execute rather than skip
- [ ] MC-2.6 — confirm the single-replica topology the rate limiter assumes

---

## 5 · Verification gates

The standing repository gates. A phase is not done until these pass.

```bash
cd RythmRun_backend_nodejs
npm ci --no-audit
npx --no-install prisma validate
npx --no-install prisma generate
npm run typecheck
npm test
npm run build
npm run smoke:runtime
```

```bash
cd rythmrun_frontend_flutter
flutter pub get --enforce-lockfile
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos
dart format --set-exit-if-changed <changed files only>
```

**Baseline to hold or beat:** backend 473 passed / 7 skipped / 480 total ·
Flutter 359 passed · analyzer 9 issues, 0 warnings, 0 errors. (The prior
`464 / 7 / 471` figure was stale — the Phase 0 lock-baseline step measured the
true starting point. Phase 0 adds config-spine tests, taking the backend to
507 passed / 7 skipped / 514 total with Flutter unchanged at 359. Phase 1 adds
the M5 sweep and M3 rate-limit tests → 508 passed / 7 skipped / 515 total.
Phase 2 adds four grace-window rotation tests → 512 passed / 7 skipped / 519
total. Phase 3a is client-only and **deliberately drops** the Flutter count from
359 to 344 by deleting 15 dead legacy-migration / verification-stamp tests.
Phase 3b adds four refresh-seam tests (M2 same-session accept/reject, A3
failed-flight eviction, A4 avatar replay policy) → Flutter 348.)

**Four known traps** (from `CLAUDE.md`, repeated because they cost real time):
1. Use `npm test`, never `npx jest` — the suite is native ESM.
2. `npm run typecheck` does not regenerate the Prisma client; run `prisma generate` first.
3. The Flutter analyzer baseline is toolchain-pinned — a version mismatch locally is by design.
4. Seven backend tests skip locally; they need real PostgreSQL and run in hosted CI.

---

## 6 · Doc lifecycle

- This file is **working state**, not a permanent record. It dies at the end of Phase 6.
- Evidence rows land in `docs/_engineering/improvement-plan/STATUS.md`.
- Durable facts (the config contract, the grace-window rationale) fold into
  `IP-2-auth-account-privacy.md` and `CONFIGURATION.md`.
- **Nothing here may mark an `ACTION-REQUIRED.md` item verified** — those close
  only by maintainer action on hosted infrastructure.
- When the plan and the code disagree, **the code is current behavior** — fix the
  doc in the same commit.
