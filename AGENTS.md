# RythmRun Agent Checklist

Claude-specific guidance lives in `CLAUDE.md`. Keep guidance in sync between
this file and `CLAUDE.md`.

## Start Here

Any non-trivial change starts at `docs/_engineering/improvement-plan/`. Three
files, three jobs:

- **`README.md`** — how the program works: rules, definition of done,
  verification commands, and decisions `D-001`…`D-018`. Read the decision table
  before proposing anything that contradicts it.
- **`STATUS.md`** — where the program stands: phase status, what is left per
  package, audit-finding traceability.
- **`ACTION-REQUIRED.md`** — the 32 manual and hosted checks that only the
  maintainer can close. **Nothing in this repository can mark one verified.**

The single most important standing fact: **IP-0 is a P0 release blocker and its
blocking work is operational, not code.** Production containment, exposure
investigation, and credential rotation cannot be closed from the repository. Do
not describe IP-0 work as done because code merged.

## What RythmRun Is

A privacy-first, offline-reliable GPS workout and photo journal for **Android**.
Not a social app, not a coaching app. It optimizes for user trust in this order:

1. The service cannot expose files, secrets, or exact routes unexpectedly.
2. Recorded metrics are correct.
3. One account cannot see or mutate another account's local state.
4. A workout survives pause, screen-off operation, process death, and poor
   connectivity.
5. Completed workouts visibly sync, restore on a new device, and delete
   consistently.
6. Releases are measurable and repeatable before retention features expand.

**Android is the only promised platform** (D-008). An iOS folder that compiles is
not release scope. **Activities are private by default** (D-006) and the friend,
comment, and like routers are deliberately unmounted and return `404` (D-007,
IP-2.5) — they are broken and have no frontend journey. Do not "fix" them into
service.

**Local-first is the product, not an optimization.** Completed workouts live in
SQLite and are retained per account across logout, but every read and mutation
must be user-scoped. Never break `(userId, clientSyncId)` idempotency, queued
remote deletion, or the activity-image upload/retry/replace/delete state
machine.

## Repository Shape

| Path | What |
| --- | --- |
| `RythmRun_backend_nodejs/` | Node 22, Express 5, strict TypeScript, **native ESM** (`"type": "module"`, NodeNext). Prisma 7.8 with the `PrismaPg` adapter over PostgreSQL. Cloudflare R2 for media through the S3-compatible API. |
| `rythmrun_frontend_flutter/` | Flutter + Riverpod. `lib/presentation/features/<feature>/` for UI, `lib/data/` and `lib/domain/` for the repository layer, `lib/core/` for network, tracking, storage, DI, config. |
| `docs/` | **Also the GitHub Pages policy site.** `index.md`, `privacy-policy.md`, `terms.md`, `delete-account.md` are public and live. |
| `docs/_engineering/` | The improvement program. `published: false` keeps it out of Pages — it does **not** make the files private. |
| `for me/`, `INTERVIEW_PREP.md` | Untracked and gitignored (`.gitignore` ignores `*` and allowlists). No git history — deleting anything there is unrecoverable. Do not touch without an explicit instruction. |

Two structural inconsistencies exist and are known: `lib/features/ads/` sits
outside `lib/presentation/features/`, and 61 semantic icon aliases in
`lib/theme/app_theme.dart` coexist with ~99 raw `Icons.*` uses. Follow the
majority convention in the file you are editing; do not launch a migration.

## Code Simplicity and Readability

Prefer the smallest direct implementation that fully satisfies the current
requirement.

- Keep one-use logic at its call site when it remains readable. Do not add
  pass-through helpers, wrapper widgets/classes, adapters, services, extensions,
  or separate files merely to rename an operation, shorten a file, or reduce
  line length.
- A new abstraction with only one caller must earn its existence by isolating a
  real domain or side-effect boundary, satisfying a framework constraint, or
  making genuinely complex logic easier to understand or test. Otherwise, keep
  the logic inline.
- Do not add speculative generalization, configuration, defensive branches, or
  future-proofing without a current requirement or demonstrated failure mode.
  Preserve compatibility where repository rules require it.
- Prefer clear names and visible, straightforward control flow over clever or
  deeply nested expressions. Reuse an established project abstraction before
  creating a parallel one.
- Keep short calls, declarations, conditions, signatures, and expressions on one
  line when they fit the formatter width. Let `dart format` and the TypeScript
  style decide unavoidable breaks; do not hand-force one-item-per-line layouts.
- Match nearby code and keep the diff scoped. Format only the exact changed
  files. Do not refactor or reformat unrelated code — the plan says so
  explicitly, and a `dart format` sweep across untouched files buries the real
  change.
- Before finishing, make a simplification pass and remove indirection with no
  clear present benefit.

**When asked to refactor, optimize for the reader.** RythmRun is a learning and
portfolio project — the code is meant to be understood, not admired. A refactor
succeeds when someone reading the file six months from now follows it faster
than before. It fails when it is shorter but needs a second pass to decode.

- Prefer an obvious loop, an early return, and a named intermediate variable
  over a chained one-liner, a nested ternary, a clever reduce, or a dense
  comprehension that packs three ideas into one expression.
- Prefer explaining *why* in a short comment over encoding the reason in a
  pattern the reader has to reverse-engineer.
- Do not introduce a design pattern, generic type parameter, metaprogramming
  trick, or layer of indirection because it is more "correct" in the abstract.
  If the concrete problem does not demand it, it is a cost with no payer.
- Line count is not the score. Fewer lines that take longer to read is a
  regression; do not compress genuinely complex code to make it look tidy.
- If a refactor changes behavior at all, say so explicitly — a refactor is
  supposed to be behavior-preserving, and a silent change hidden inside a
  cleanup diff is the hardest kind of bug to find later.

## Verification

Run from the repository root. These are the gates; a change is not done until
they pass.

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

Current `main` baseline: backend **464 passed / 7 skipped / 471 total**; Flutter
**359 passed**; analyzer **9 issues, 0 warnings, 0 errors**.

Four traps that cost real time:

1. **Use `npm test`, never `npx jest`.** The suite is native ESM and needs
   `node --experimental-vm-modules`, which the npm script supplies. Running
   `npx jest` fails all 26 suites with `SyntaxError: Unexpected token 'export'`
   and looks like a broken repository.
2. **`npm run typecheck` does not regenerate the Prisma client.** A stale client
   produces a wall of errors about fields that plainly exist in
   `schema.prisma`. Run `npx prisma generate` first before believing any Prisma
   type error.
3. **The Flutter analyzer baseline is toolchain-pinned.** `tool/ci/analyzer_baseline.json`
   is stamped with the Flutter/Dart pair in `rythmrun_frontend_flutter/.flutter-version`
   (currently 3.44.1 / 3.12.1, matching CI). On a newer local SDK
   `analyzer_baseline.dart check` exits with a version-mismatch error **by
   design** — that is not a failure to fix. `flutter analyze` itself still works;
   only the counted comparison is CI-only.
4. **Seven backend tests skip locally** (`auth-session.postgres.test.ts`). They
   need a real PostgreSQL and run in hosted CI. A green local run does not cover
   them, and MC-2.1 exists precisely to prove they *execute* rather than skip.

## Backend Test Conventions

Tests are native-ESM Jest via `ts-jest`'s ESM preset. That constrains how you
write them:

- Mock with `jest.unstable_mockModule('../path/module.js', () => ({...}))`
  **before** importing the module under test, then import with top-level-await
  `const { thing } = await import('../path/module.js')`. Plain `jest.mock` does
  not work here.
- **There is no supertest.** HTTP-level tests hand-roll a `node:http` server and
  request helper — see `api-abuse-controls.test.ts` and
  `http-security-boundary.test.ts`. Follow that pattern rather than adding a
  dependency; the dependency surface is deliberately minimized (IP-0.7-dep).
- You cannot destructure a type from a dynamic import
  (`const { X, type Y } = await import(...)` is TS1005). Use a separate
  `import type { Y } from '../path.js';` at the top.
- Import specifiers keep the `.js` extension in TypeScript source. That is
  NodeNext, not a mistake.

## Typed Errors, Not Message Strings

Backend errors carry a stable code and status. Mobile branches on the **code or
status, never on exact English text** — that rule is in the IP-2 auth contract
and it has already been violated twice.

- Backend: raise a typed error (`AuthApplicationError`, `ActivityImageServiceError`) with
  its own code and status. Do not pick an HTTP status by comparing
  `error.message` to a sentence.
- Flutter: add a `case '<CODE>':` arm in `ErrorHandler.getErrorMessage`
  (`lib/core/utils/error_handler.dart`) for every new backend code that users
  can hit.
- **Never derive user-facing text from `exception.toString()`.** Our exception
  types render as `'UnauthorizedException: <msg>'`, and the old
  `replaceAll('Exception: ', '')` cut the literal out of the *middle*, so a
  failed login reached users as `UnauthorizedInvalid username or password`. Read
  `exception.message`. The switch deliberately has **no `default:` arm** — a
  default would short-circuit the type-based branches below it and lose the
  per-status generic messages.
- Never log a raw error object on a storage path; it can carry a presigned URL.

## Storage Boundary

- **Cloudflare R2 does not support presigned POST.** An S3 POST policy with
  `content-length-range` silently enforces nothing here. That is exactly how the
  avatar byte bound sat inert while the plan recorded it as delivered.
- The working pattern is a presigned **PUT** with both `content-type` and
  `content-length` in the *signed* header set, so storage rejects a mismatched
  body. `getPresignedPutUrl` already signs `content-length` when given a
  `sizeBytes`. Avatars pass it; activity images do not yet (IP-2.6 item 6).
- **Neither bucket has a public delivery origin.** Media reads are short-lived
  presigned GETs behind authentication. Do not reintroduce `R2_PUBLIC_URL` or a
  public/CDN read path.
- Always name the bucket explicitly on `headObject`/`deleteObject`. A default
  fallback previously sent avatar confirm and cleanup to the activity-image
  bucket.
- Keys are server-generated (`avatars/{userId}/{serverId}.{ext}`) and
  confirmation must consume a server-issued single-use intent. Prefix grammar
  alone never proves a key was issued.

## Abuse Controls Are In-Process

The rate limiter is a sliding window in application memory
(`src/middleware/rate-limit.middleware.ts`, budgets in
`src/config/rate-limits.ts`).

- **A restart clears every counter and a second replica multiplies every limit.**
  Any change to deployment topology invalidates the limits. MC-2.6 verifies the
  replica count for this reason.
- Budgets are charged **on admission** and refunded when a failure-counting
  response turns out not to be a 4xx. Do not "improve" this to charge on
  response — an adversarial probe showed response-time charging admitted 40
  concurrent guesses against a limit of 5.
- A `429` is never charged, so a limited key recovers on schedule instead of
  being pushed forward by continued abuse.
- Login carries two ceilings: per account+address, and a second per address
  alone. The composite key bounds guessing one password but never trips against
  credential spraying, where every attempt names a different account.
- `TRUST_PROXY_HOPS` defaults to `0`. Raising it without matching the real proxy
  depth lets a forged `X-Forwarded-For` choose the limiter key.
- CORS is a browser-only control and never an auth substitute. The API is
  bearer-authenticated, so `Access-Control-Allow-Credentials` is never sent.

## Backend Schema Changes

Prisma migrations under `RythmRun_backend_nodejs/prisma/migrations/` are the
deploy-time source of truth. Runtime bootstrap code is not a rollout mechanism.

1. Add the migration; run `npx prisma migrate dev` locally and
   `npx prisma validate`.
2. Update the models, DTOs, and services that read or write the field.
3. If the field crosses to the mobile client, update the SQLite migration in
   `lib/core/services/local_db_service.dart` and its version guard. Local
   deletes that sync are **tombstones, not hard deletes** — check that queries
   filter them.
4. Add tests for the payload shape and the migration path.
5. Write down the deployment order and the rollback trigger. Two existing
   migrations are deliberately **not rolling-compatible** — the Google-auth
   migration (`User.password` becomes nullable) and the auth-session rebuild
   (drops the legacy plaintext refresh table and forces one sign-in). Both
   require draining old instances first. Details in
   `RythmRun_backend_nodejs/README.md` under "Build and deployment order".

## Deployment Compatibility

**Merging to `main` deploys the backend.** Render auto-deploys from `main`, so
a backend change is live in production the moment the PR merges — there is no
separate deploy gate to catch a mistake. Flutter changes reach users only
through a Play Store release, which takes time and which users may not install.

The asymmetry is the hazard: **the backend always runs newer than the installed
app.** Unless a change is explicitly planned as a forced-upgrade release where
the merge waits until the new app version is live, keep backend APIs backward
compatible with the currently released app — make new fields and parameters
optional, preserve existing response shapes, and do not require client behavior
that may not be live yet.

This has already bitten once. `76fa16f` changed the avatar upload contract from
a multipart POST to a presigned PUT on both sides at once; the backend half went
live on merge while the client half waits on a store release, so an app older
than `1.2.0+21` cannot upload an avatar until it updates.

Two migrations are deliberately **not** rolling-compatible and must not simply
be merged — the Google-auth migration and the auth-session rebuild both require
draining old instances first. See "Backend Schema Changes" below.

Where compatibility is intentionally broken, say so in the handoff and name the
drain/promote order.

## Ads Fail Closed

Advertising is off by default and the contract is compile-time
(`rythmrun_frontend_flutter/CONFIGURATION.md`).

- `ADS_ENV` takes `development`/`staging`/`production` — **not** `dev`/`prod`.
  It is separate from `APP_ENV`, which selects the API base URL and timeout
  only.
- Non-production and ads-disabled builds use the no-op provider and the official
  Google *sample* application ID so the manifest stays valid.
- Never pass production AdMob IDs to a development, test, staging, or
  verification command, and never commit them to a file, script, manifest, or
  test output.
- The only configurable placement sits **after** durable workout completion. A
  save-pending, failed, or cleanup-pending outcome shows recovery UI and cannot
  request an ad. Live serving, consent, and placement approval remain blocked on
  IP-5.5.

## Frontend Conventions

- **Riverpod** for state. Follow the provider/notifier shape already used in the
  feature you are editing.
- **Spacing and colors come from constants**, not magic numbers: `spacingXs`…
  `spacing2xl` in `lib/theme/app_theme.dart`, `CustomAppColors` in
  `lib/const/custom_app_colors.dart`.
- **Icons**: use the `hugeicons` package for new or modified UI — `HugeIcon`
  with a `HugeIcons.strokeRounded...` glyph. Do not reach for Flutter's Material
  `Icon` widget or `Icons.*` when a suitable HugeIcons glyph exists. Reuse the
  glyph already assigned to the same domain or feature. Use a Material icon only
  when HugeIcons has no suitable glyph or a framework API strictly requires
  `IconData`, and keep that exception local.

  The existing code predates this: `lib/theme/app_theme.dart` defines 61
  semantic Material aliases (`const trackChangesIcon = Icons.track_changes;`)
  and ~99 raw `Icons.*` uses remain across older screens. **Do not bulk-migrate
  them** — that is an unrelated diff. Convert an icon when you are already
  editing that widget, and give new domain glyphs a named alias in
  `app_theme.dart` the same way, so the semantic-name convention survives the
  package change.
- Injectable seams over hard-wired globals for anything a test must observe: the
  settings screen takes an `externalUrlLauncher`, the attribution widget takes a
  `urlLauncher`. Follow that when adding a side effect.

## Privacy and Evidence Rules

These are absolute and they apply to code, tests, logs, docs, and commit
messages alike.

- Never commit secrets, tokens, signed URLs, raw logs, database snapshots,
  customer identifiers, exact routes, GPS coordinates, acquisition timestamps,
  or incident detail.
- Observability records stable codes, request IDs, sizes, and aggregate counts.
  `X-Request-Id` is **server-minted and ignores any inbound header** so a client
  cannot forge a log trail. Security events are built from a fixed allowlisted
  field set — never a spread of caller input — with identifying values reduced
  to a truncated SHA-256 digest.
- **"Repository-delivered" is not "done."** Nothing in this program is
  `Complete`; every delivered package still owes at least one item in
  `ACTION-REQUIRED.md`. Do not write that a package is finished, deployed,
  verified, or safe because code merged and local tests passed.
- When the plan and the code disagree, **the code is current behavior**. Update
  the plan in the same change. Never leave a document claiming behavior that was
  not verified.

## Documentation Placement

- Engineering docs go under `docs/_engineering/<area>/`. Phase specifics go in
  the phase file that owns them.
- Frontend-only docs live beside the Flutter app
  (`rythmrun_frontend_flutter/CONFIGURATION.md` is the model).
- Backend runbooks live in `RythmRun_backend_nodejs/` next to what they
  configure (`EMAIL_VERIFICATION_SETUP.md`, `MIGRATION_AWS_TO_R2.md`).
- **Do not add root-level plans or orphan planning docs.** Delete an implemented
  plan; if part of it still matters, fold that part into the owning doc.
- **Anything under `docs/` that is not `_engineering/` is a public web page.**
  Treat `privacy-policy.md`, `terms.md`, and `delete-account.md` as legal text:
  engineering supplies verified facts, the maintainer decides the wording. Do
  not edit them to match new behavior on your own initiative — record the fact
  in the plan and flag it.
- When a delivered package's step-by-step is no longer useful, delete it and
  keep the evidence log. Git history holds the rest.

## Commits

- Feature branch, then PR to `main`. Commit or push only when asked.
- **Never add an AI attribution or `Co-Authored-By` line** to a commit
  message or PR body.
- Say what changed and why it was wrong before, not just what was touched.
  Record what was deliberately *not* claimed — the evidence discipline in this
  repository depends on it.
