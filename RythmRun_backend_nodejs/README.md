# RythmRun Backend

RythmRun's backend is a Node.js 22, Express, and strict-TypeScript modular monolith. It runs as native ESM and uses PostgreSQL through Prisma 7's `PrismaPg` driver adapter.

## Runtime architecture

- `package.json` declares `"type": "module"`; TypeScript uses `NodeNext` resolution and explicit `.js` relative imports so emitted JavaScript follows Node's ESM resolver.
- `prisma.config.ts` supplies the datasource URL and migration/seed locations to the Prisma CLI.
- `prisma/schema.prisma` uses the Prisma 7 `prisma-client` generator and emits ESM TypeScript into `src/generated/prisma`.
- `src/config/database.ts` owns `PrismaPg` and `PrismaClient` construction. The application container injects one client into its services and server shutdown disconnects it.
- Access JWTs are short-lived session credentials. Every protected request validates standard token claims and confirms the referenced PostgreSQL `AuthSession` is still active; middleware never constructs its own database client.
- Refresh JWTs rotate through digest-only `RefreshTokenRecord` rows. The server retains used records through the absolute session lifetime so exact replay can revoke the family without storing a raw refresh token.
- Google sign-in accepts a Google ID token only at the public exchange endpoint. The backend verifies its signature, issuer, expiry, verified-email claim, and `GOOGLE_SERVER_CLIENT_ID` audience with `google-auth-library`, then keys the account by Google's stable `sub` claim and issues the same RythmRun access/refresh session used by password login. A matching password account is linked only after that account has independently verified the same email; an unverified collision returns `AUTH_EMAIL_UNVERIFIED_CONFLICT`.
- The PostgreSQL adapter uses a maximum pool size of 10, a five-second connection timeout, and a five-minute idle timeout. Provider-specific TLS remains part of deployment configuration and staging proof.
- `src/main.ts` is the production entry point; `npm run build` emits it as `dist/main.js` and `npm start` runs that built file.
- Cloudflare R2 stores media through its S3-compatible API. The backend issues user-scoped signed upload operations and signed delivery URLs; media bytes do not pass through PostgreSQL.

Generated Prisma source and `dist/` are build outputs and are not hand-edited or committed.

## Main API routes

Registration, login, refresh, and liveness are public HTTP routes. Refresh authenticates the presented refresh JWT itself; all other application routes require an active access-token session.

The authentication and recovery routes additionally carry per-endpoint request budgets (IP-2.6). Exceeding one returns `429` with `AUTH_RATE_LIMITED`, a `Retry-After` header, and a message identical across endpoints so the response never reveals which dimension tripped or whether an account exists. The shipped budgets live in `src/config/rate-limits.ts`: 5 failed logins per account+address / 15 min, 5 registrations per address / hour, 10 Google exchanges per address / 15 min, 3 recovery requests per account+address / hour, 10 reset submissions per address / hour, and 5 password changes and 5 verification resends per account / hour. Login carries a second, broader ceiling of 20 failed attempts per address / 15 min: the account+address key bounds guessing one account's password, but on its own it would never trip against credential spraying, where each attempt names a different account and mints a fresh key.

Budgets are charged when the request is admitted, not when it responds, and a `client_failures` rule refunds the charge unless the response was a 4xx other than `429`. Deciding at response time instead would let a burst of overlapping requests all read an uncharged bucket — 40 concurrent password guesses against a limit of 5. A `429` is excluded because the application never saw the request, so a broad limiter that trips first cannot quietly drain the narrower per-account budget of everyone sharing an address.

Counters are held in this process's heap. They are therefore **lost on restart and not shared between replicas**, so the limits are a defence-in-depth layer, not the primary control — authentication, anti-enumeration, and single-use tokens remain mandatory. Losing them on restart admits traffic rather than denying it, which is the right failure mode for a login endpoint but means N replicas would multiply every limit by N. Before a second replica or an autoscaler is introduced these budgets must move to a shared store or to the edge.

- Users: `POST /api/users/register`, `POST /api/users/login`, `POST /api/users/auth/google`, `POST /api/users/refresh-token`, `POST /api/users/logout`, `GET /api/users/me`, `PUT /api/users/profile`, `PUT /api/users/change-password`, `GET /api/users/verify-email`, `POST /api/users/verify-email/resend`, `POST /api/users/password-reset/request`, and `GET/POST /api/users/password-reset`.
- Avatars: `POST /api/avatar/upload-url` and `POST /api/avatar/confirm`.
- Activities: `GET/POST /api/activities` and `GET/PATCH/DELETE /api/activities/:activityId`.
- Activity images: list, request upload, confirm, and delete below `/api/activities/:activityId/images`.
- Social (friends, comments, likes) is **not exposed**: the routers exist under `src/routes` but are intentionally unmounted (IP-2.5 / D-007) and return `404` until the privacy, visibility, and moderation model is complete.
- Liveness: `GET /health`.

The route source under `src/routes` is authoritative. In particular, activity updates use `PATCH`; the retired local profile-picture upload route is not part of this API.

## Repository layout

```text
prisma/
├── migrations/              # Ordered PostgreSQL migrations
└── schema.prisma            # Models and Prisma 7 generator
src/
├── config/                  # Environment, container, and database ownership
├── controllers/             # HTTP request/response boundary
├── generated/prisma/        # Generated ESM client; ignored build output
├── middleware/              # Authentication and validation
├── models/                  # DTOs and domain validation
├── routes/                  # Express route definitions
├── services/                # Business logic and transactions
├── app.ts                   # Express application factory
├── server.ts                # Listener and resource lifecycle
└── main.ts                  # Production process entry point
```

## Local development

Use Node.js 22.x. Start from a clean, lockfile-enforced dependency install:

```bash
npm ci --no-audit
cp .env.example .env
```

Replace every placeholder in `.env`; startup validates the database, JWT, and R2 values before constructing infrastructure clients. `DATABASE_URL` is shared by `prisma.config.ts` and the runtime adapter.

Two edge variables gate the browser surface (IP-2.6). `CORS_ALLOWED_ORIGINS` is a comma-separated list of exact origins and is **required when `NODE_ENV=production`** — a production process without it exits before listening, and every production entry must use https. Outside production it may be omitted, which leaves the allowlist empty and grants no browser origin; the mobile app sends no `Origin` header and is unaffected. `TRUST_PROXY_HOPS` is the number of reverse proxies in front of the process and defaults to `0`. It must match the real deployment: set higher than the true proxy depth, a client can forge `X-Forwarded-For` to choose its own rate-limit key and escape every address-keyed limit.

The current Render service uses
`CORS_ALLOWED_ORIGINS=https://rythmrun.onrender.com`. Render supplies
`NODE_ENV=production` automatically at runtime; do not persist
`NODE_ENV=development` on the live service. If a deployment exposes
`NODE_ENV=production` during dependency installation, use
`npm ci --include=dev --no-audit` so the TypeScript compiler and Prisma CLI
remain available to the build and migration stages.

Set `GOOGLE_SERVER_CLIENT_ID` to the OAuth 2.0 web/server client ID from Google Cloud. The Flutter app must receive that exact same value as its `GOOGLE_SERVER_CLIENT_ID` build define so Google puts the expected audience in the ID token. The exchange contract is:

```http
POST /api/users/auth/google
Content-Type: application/json

{"idToken":"<google-id-token>"}
```

A successful exchange returns the existing flat auth response (`id`, `username`, optional profile fields, `hasPassword`, `accessToken`, and `refreshToken`). `hasPassword` is a non-sensitive capability flag included consistently in auth, refresh, `/me`, and profile-update responses; clients can use it to hide password change for Google-only accounts. Google-only accounts have no password and cannot use password login or password change. The API never accepts a client-supplied Google subject, email, or profile as proof of identity.

Usernames are stored as trimmed lowercase email addresses for both password and Google authentication. Invalid Google tokens return `AUTH_GOOGLE_INVALID` with HTTP 401; an identifiable Google certificate/network outage returns `AUTH_GOOGLE_UNAVAILABLE` with HTTP 503 and `retryable: true`.

For a disposable local PostgreSQL database only:

```bash
npx --no-install prisma validate
npm run prisma:generate
npm run prisma:migrate
npm run dev
```

`prisma:migrate` runs `prisma migrate dev` and may create migrations, so it is not a production deployment command. The API listens on `http://localhost:8080` unless `PORT` is changed.

## Verification

The backend CI uses the following order:

```bash
npm ci --no-audit
npx --no-install prisma validate
npx --no-install prisma generate
npm run migrate:deploy
npm run typecheck
npm test -- --ci --runInBand
npm run build
npm run smoke:runtime
```

`npm test` invokes Jest through Node's ESM VM support. The hosted backend workflow provisions a disposable PostgreSQL database, applies the complete migration chain, sets `RUN_DATABASE_INTEGRATION=1`, and runs the serial refresh/session tests in the same Jest process. Without that explicit flag, the destructive database suite is skipped; its database-name guard also refuses any URL that is not clearly test/CI-scoped. `npm run build` cleans `dist`, regenerates the Prisma client, and compiles the production TypeScript project. The final smoke imports the emitted `dist/server.js`, starts a loopback listener, checks `/health` and unauthenticated rejection on a protected route, and closes the server.

The PostgreSQL integration suite proves migration application, adapter-backed auth queries, digest-only storage, serializable refresh concurrency/replay behavior, session caps, and logout/password revocation against synthetic rows. It does **not** prove provider TLS, a deployed custom schema, pooling under production load, or production rollout. It also does not prove the deployed proxy behavior: the rate-limit tests exercise `trust proxy` against a synthetic `X-Forwarded-For`, which shows the code honours the configured hop count, not that `TRUST_PROXY_HOPS` matches the hosting proxy in front of the real deployment. That remains MC-2.6. The built smoke deliberately remains database-free.

## Build and deployment order

Build and migration stages require development dependencies because the Prisma CLI and TypeScript compiler are development tools. A deployment pipeline should use one reviewed Node.js 22 toolchain and this order:

```bash
npm ci --include=dev --no-audit
npx --no-install prisma validate
npm run build
npm run migrate:deploy
npm prune --omit=dev
npm start
```

`migrate:deploy` must have a real target `DATABASE_URL`, a verified backup/rollback procedure, and exactly one migration owner. Run it against an isolated staging database and a representative upgrade copy before production. Start or promote the already-built artifact only after the migration step succeeds; do not rebuild different source for production.

The Google-auth migration is intentionally **not rolling-compatible** with older backend instances. It canonicalizes every existing username, aborting before writes if canonicalization would merge case/whitespace variants, and then permits `User.password` to be null for Google-only accounts. Old code assumes every password is non-null and can fail if it observes a newly created Google account. Drain and stop all old instances before applying this migration, keep traffic drained while it runs, and atomically promote only the matching Google-aware artifact after migration success. Do not run old and new versions concurrently across this schema boundary.

The auth-session migration intentionally drops the legacy plaintext refresh table because old JWTs have no `sid`/`jti` and cannot be backfilled safely. It therefore forces a one-time sign-in. Drain old backend instances before applying this cutover, promote only the matching session-aware artifact, and never roll back by recreating plaintext token rows or resurrecting revoked sessions.

Before declaring a release database-compatible, staging must also prove provider-required TLS, the intended PostgreSQL schema, an authenticated query, bounded connection usage, disconnect on shutdown, and the serializable rollback/concurrency paths used by activity writes. The no-database CI smoke does not close those operational gates.
