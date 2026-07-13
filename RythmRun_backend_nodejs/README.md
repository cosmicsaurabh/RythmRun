# RythmRun Backend

RythmRun's backend is a Node.js 22, Express, and strict-TypeScript modular monolith. It runs as native ESM and uses PostgreSQL through Prisma 7's `PrismaPg` driver adapter.

## Runtime architecture

- `package.json` declares `"type": "module"`; TypeScript uses `NodeNext` resolution and explicit `.js` relative imports so emitted JavaScript follows Node's ESM resolver.
- `prisma.config.ts` supplies the datasource URL and migration/seed locations to the Prisma CLI.
- `prisma/schema.prisma` uses the Prisma 7 `prisma-client` generator and emits ESM TypeScript into `src/generated/prisma`.
- `src/config/database.ts` owns `PrismaPg` and `PrismaClient` construction. The application container injects one client into its services and server shutdown disconnects it.
- The PostgreSQL adapter uses a maximum pool size of 10, a five-second connection timeout, and a five-minute idle timeout. Provider-specific TLS remains part of deployment configuration and staging proof.
- `src/main.ts` is the production entry point; `npm run build` emits it as `dist/main.js` and `npm start` runs that built file.
- Cloudflare R2 stores media through its S3-compatible API. The backend issues user-scoped signed upload operations and signed delivery URLs; media bytes do not pass through PostgreSQL.

Generated Prisma source and `dist/` are build outputs and are not hand-edited or committed.

## Main API routes

All application routes except registration and login require authentication; the liveness endpoint is public.

- Users: `POST /api/users/register`, `POST /api/users/login`, `POST /api/users/logout`, `POST /api/users/refresh-token`, `PUT /api/users/profile`, and `PUT /api/users/change-password`.
- Avatars: `POST /api/avatar/upload-url` and `POST /api/avatar/confirm`.
- Activities: `GET/POST /api/activities` and `GET/PATCH/DELETE /api/activities/:activityId`.
- Activity images: list, request upload, confirm, and delete below `/api/activities/:activityId/images`.
- Friends, comments, and likes are exposed below `/api/friends`, `/api/activities/:activityId/comments`, and `/api/activities/:activityId/likes`.
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
npm run typecheck
npm test -- --ci --runInBand
npm run build
npm run smoke:runtime
```

`npm test` invokes Jest through Node's ESM VM support. `npm run build` cleans `dist`, regenerates the Prisma client, and compiles the production TypeScript project. The final smoke imports the emitted `dist/server.js`, starts a loopback listener, checks `/health` and unauthenticated rejection on a protected route, and closes the server.

These checks deliberately use a syntactically valid but unreachable PostgreSQL URL. They prove schema/configuration parsing, generation, production type safety, ESM tests, emitted module resolution, basic listener startup, and shutdown. They do **not** prove a real database connection, migration execution, TLS, schema selection, pooling under load, authenticated queries, or transaction behavior.

## Build and deployment order

Build and migration stages require development dependencies because the Prisma CLI and TypeScript compiler are development tools. A deployment pipeline should use one reviewed Node.js 22 toolchain and this order:

```bash
npm ci --no-audit
npx --no-install prisma validate
npm run build
npm run migrate:deploy
npm prune --omit=dev
npm start
```

`migrate:deploy` must have a real target `DATABASE_URL`, a verified backup/rollback procedure, and exactly one migration owner. Run it against an isolated staging database and a representative upgrade copy before production. Start or promote the already-built artifact only after the migration step succeeds; do not rebuild different source for production.

Before declaring a release database-compatible, staging must also prove provider-required TLS, the intended PostgreSQL schema, an authenticated query, bounded connection usage, disconnect on shutdown, and the serializable rollback/concurrency paths used by activity writes. The no-database CI smoke does not close those operational gates.
