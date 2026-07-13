---
published: false
---

# IP-0: Production security containment and exposure response

| Field | Value |
| --- | --- |
| Status | **In progress** |
| Priority | P0 / release blocker |
| Target | 1–2 days after the required operational access is available |
| Owner | Unassigned |
| Last updated | 2026-07-11 |
| Entry condition | None; containment begins immediately |
| Exit condition | All criteria in [Exit gate](#exit-gate) have evidence |

## Outcome

After this phase, an HTTP client cannot write a local filesystem path or arbitrary S3 key into a user record, no request can cause the backend to read or delete a file outside an approved avatar object, missing secrets stop startup, and the possible production exposure has a documented incident disposition.

This file is a plan, not proof that production is safe.

All hosted and human-operated gates are mirrored in the [manual verification register](./MANUAL-CHECKS.md). Keep them open until that register contains dated, independently reviewed evidence.

## Merged implementation checkpoint

Commit `e33f314`, merged into `origin/main` by merge commit `54a5b26`, contains the reviewable application slice for IP-0.2 through IP-0.5:

- strict DTO allowlists plus explicit Prisma write mappings;
- removal of the local filesystem avatar routes, handlers, middleware, and Multer dependency;
- an authenticated, expiring, single-use avatar intent with a storage-enforced multipart POST policy, ownership/type/size verification, quotas, atomic confirmation, and durable bounded cleanup retries;
- a coordinated Flutter multipart client with size/type checks and redacted avatar logging; and
- environment validation before infrastructure imports, with no executable JWT fallback secrets.

This merged checkpoint is repository evidence, not deploy authorization or production verification. The additive database migration must precede the backend, older PUT-based clients require a coordinated/forced update, the independent S3 lifecycle rule still needs infrastructure evidence, and IP-0.1/IP-0.6 plus staging/production checks remain open.

## Audit evidence at discovery time

- `RythmRun_backend_nodejs/src/middleware/validation.middleware.ts` transforms and validates without stripping or rejecting undeclared fields.
- `RythmRun_backend_nodejs/src/services/user.service.ts` spreads the validated registration object into Prisma and passes profile updates directly into Prisma.
- `RythmRun_backend_nodejs/src/controllers/user.controller.ts` joins the stored `profilePicturePath` to the upload directory for unauthenticated reads and later deletion.
- `RythmRun_backend_nodejs/src/controllers/avatar.controller.ts` accepts an arbitrary `key` and writes it to `profilePicturePath` without proving user ownership, prefix, type, or size.
- `RythmRun_backend_nodejs/src/middleware/auth.middleware.ts` and `RythmRun_backend_nodejs/src/services/user.service.ts` fall back to public placeholder JWT secrets.
- `RythmRun_backend_nodejs/src/app.ts` calls `dotenv.config()` only after imports that instantiate the container and S3 service.
- `RythmRun_backend_nodejs/src/routes/user.routes.ts` exposes `GET /api/users/profile-picture/:id` without authentication and keeps a second, local avatar pipeline beside `/api/avatar`.
- The 2026-07-10 production dependency scan reported 11 advisories, including the installed Multer 2.0.1 denial-of-service concerns.

## Scope

- Emergency endpoint containment.
- Preservation and review of relevant production evidence.
- Explicit request-field allowlists at the controller/service trust boundary.
- Retirement of the local filesystem avatar pipeline.
- Hardening the S3 avatar upload/confirmation path.
- Fail-closed environment validation and initialization ordering.
- Credential rotation/session invalidation when exposure cannot be excluded.
- Negative security tests, staging smoke tests, and a controlled reopen.

## Non-goals

- A complete refresh-token redesign; that belongs to IP-2.
- General error-contract or dependency-injection cleanup beyond the touched security path.
- Social, profile-sharing, or public-route features.
- Broad infrastructure redesign.
- Attempting path traversal or secret retrieval against production.

## Required access and roles

| Role/access | Needed for |
| --- | --- |
| Deployment owner | Route restriction, emergency deploy, rollback, and reopen |
| Application/edge log access | Preserve and review requests without copying personal data into this repository |
| PostgreSQL owner | Inspect/quarantine suspicious avatar values and revoke refresh sessions |
| Secret-store owner | Rotate JWT and database credentials |
| AWS IAM/S3 owner | Rotate keys, inspect object access where available, and reduce IAM permissions |
| CloudFront owner | Rotate signing material and verify cache/read behavior |
| Security/maintainer owner | Decide incident severity and record the final disposition outside the public repo |

If any required access is unavailable, keep affected endpoints restricted and mark the phase `Blocked`; do not reopen based only on a code review.

## Target security design

1. Request DTOs contain only client-writable fields. Controllers reject unknown fields, and services explicitly construct Prisma `data` objects. No DTO is spread into persistence.
2. `profilePicturePath` is server-managed. The target value is an S3 object key generated by the server under `avatars/{userId}/...`, never a client path.
3. One avatar pipeline remains: authenticated direct upload to S3, followed by server verification. Local upload/read routes are removed or return a temporary non-success response during migration.
4. Confirmation is tied to the authenticated user and a server-issued object key. S3 metadata is checked before the user record changes.
5. Startup configuration is validated once before Prisma/S3/JWT consumers are constructed. There are no development fallback secrets in executable code.
6. Rollback never restores the vulnerable routes. When a deployment fails, containment stays in place while the application rolls back.

## Ordered work packages

### IP-0.1 — Contain production and preserve evidence

**Implementation**

1. At the hosting/edge layer, block or require maintainer-only access for:
   - `POST /api/users/register`
   - `PUT /api/users/profile`
   - `POST /api/users/profile-picture`
   - `GET /api/users/profile-picture/*`
   - `POST /api/avatar/upload-url`
   - `POST /api/avatar/confirm`
2. If route-level restriction is unavailable, restrict the complete backend until an emergency build can return `503` or `410` for these paths.
3. Record the containment start time, rule/config identifier, owner, and a probe result in the private incident record.
4. Preserve relevant edge/application logs before normal retention removes them. Limit access and do not paste raw request values into Git.
5. Capture a database backup or provider snapshot before cleaning suspicious rows.

**How to verify**

- Anonymous and ordinary authenticated probes to every contained path return no success response.
- `/health` can remain available only if it exposes no secret or dependency detail.
- Existing unrelated app endpoints still behave as expected, or the operational owner has explicitly chosen full-backend restriction.
- The incident record contains timestamps and references to preserved evidence.

**Acceptance**

- Containment is externally observable and does not depend on a developer's local machine.
- No exploit payload is sent to production as part of verification.

### IP-0.1A — Bootstrap isolated security staging in parallel

Later phases require staging, so a minimal isolated environment is a program prerequisite rather than an IP-5 deliverable.

**Implementation**

1. Create a non-production backend deployment with its own PostgreSQL database/schema, S3 bucket or strictly isolated prefix, CloudFront/test read configuration, JWT secrets, and synthetic accounts.
2. Use least-privilege non-production credentials; never copy production users, routes, photos, tokens, or logs.
3. Run the same migration artifact and backend build intended for production. Environment values remain in the approved secret store.
4. Keep all risky negative tests confined to local/test/staging and use synthetic canary files/objects—not real secrets.
5. IP-5 later adds formal promotion, observability, disaster, and release discipline; this task provides the safe verification target needed now.

**Acceptance**

- A clean staging deploy can run migrations, security tests, and the valid avatar lifecycle without any production credential/data access.

### IP-0.2 — Enforce explicit writable-field allowlists

**Primary files**

- `RythmRun_backend_nodejs/src/middleware/validation.middleware.ts`
- `RythmRun_backend_nodejs/src/models/dto/user.dto.ts`
- `RythmRun_backend_nodejs/src/controllers/user.controller.ts`
- `RythmRun_backend_nodejs/src/services/user.service.ts`
- New focused tests under `RythmRun_backend_nodejs/src/__tests__/`

**Implementation**

1. Make the shared DTO helper validate with `whitelist: true`, `forbidNonWhitelisted: true`, and `forbidUnknownValues: true`. Use the current `class-transformer` API and return a typed validation error without echoing sensitive input.
2. Keep client-writable user fields intentionally small:
   - registration: `username`, `password`, optional `firstname`, optional `lastname`;
   - profile update: optional `firstname`, optional `lastname`;
   - never accept `id`, `password` on profile update, `profilePicturePath`, `profilePictureType`, timestamps, roles, token fields, or relations.
3. In `UserService.register`, remove `...registerDto`; construct the Prisma object field by field and set only the server-created password hash.
4. In `UserService.updateProfile`, construct the update object field by field. Treat an empty update as a validation error rather than a successful no-op if that is the agreed API behavior.
5. Keep avatar persistence behind a dedicated server method that accepts a verified server-owned avatar object, not `UpdateProfileDto`.

**How to verify**

- Registration/profile requests containing each forbidden field return `400` and do not call Prisma create/update.
- Nested unexpected objects and prototype-like field names are rejected safely.
- Valid registration and first/last-name updates still work.
- Unit tests inspect the exact Prisma `data` object and prove forbidden keys are absent.

**Acceptance**

- A future field added to the Prisma `User` model does not automatically become client-writable.

### IP-0.3 — Retire unsafe local filesystem avatars

**Primary files**

- `RythmRun_backend_nodejs/src/routes/user.routes.ts`
- `RythmRun_backend_nodejs/src/controllers/user.controller.ts`
- `RythmRun_backend_nodejs/src/middleware/file-upload.middleware.ts`
- `RythmRun_backend_nodejs/src/config/upload.config.ts`
- `RythmRun_backend_nodejs/package.json`
- `rythmrun_frontend_flutter/lib/data/datasources/avatar_remote_datasource.dart`
- `rythmrun_frontend_flutter/lib/data/repositories/avatar_repository_impl.dart`

**Implementation**

1. Confirm the current supported mobile build uses `/api/avatar`; the Flutter avatar data source is the compatibility reference.
2. Remove or permanently disable the local `POST /profile-picture` and `GET /profile-picture/:id` routes. Do not leave an unauthenticated legacy read path.
3. Stop calling `path.join`, `sendFile`, or `unlink` with a database-derived avatar string.
4. After the supported-client check, remove the local upload middleware/configuration and Multer if no other route uses it. This also removes the known exposed Multer path instead of merely increasing a limit.
5. Inventory existing user rows:
   - recognize server-generated local basenames separately from S3 keys;
   - quarantine absolute paths, traversal segments, encoded traversal, separators where a basename is expected, control characters, and keys outside the approved avatar prefix;
   - set unsafe values to `NULL` only after the backup and incident query are recorded;
   - migrate legitimate local avatars to S3 only through a one-off controlled script that is reviewed separately and never accepts client input.
6. If a short compatibility window absolutely requires local reads, use an authenticated endpoint and a single helper that accepts only a generated basename, resolves under a fixed upload root, rejects separators/absolute paths, checks real-path containment including symlinks, and never deletes on lookup. This is a temporary exception and does not change Decision D-005.

**How to verify**

- Route enumeration shows no public local-avatar read or local upload handler.
- Repository search shows no `sendFile`/`unlink` target built from `profilePicturePath`.
- A seeded legacy malicious row cannot cause a filesystem read or delete.
- A supported mobile client can still display/upload an S3 avatar after IP-0.4.
- The dependency scan confirms Multer is removed or upgraded and unreachable if temporary compatibility keeps it.

**Acceptance**

- The database contains an object key/asset reference, not a local path used in filesystem APIs.

### IP-0.4 — Harden the S3 avatar pipeline

**Primary files**

- `RythmRun_backend_nodejs/src/controllers/avatar.controller.ts`
- `RythmRun_backend_nodejs/src/routes/avatar.routes.ts`
- `RythmRun_backend_nodejs/src/services/s3.service.ts`
- `RythmRun_backend_nodejs/src/config/container.ts`
- `RythmRun_backend_nodejs/src/models/dto/` (new avatar DTOs)
- `RythmRun_backend_nodejs/src/services/` (new injected avatar service)
- New `RythmRun_backend_nodejs/src/__tests__/avatar.service.test.ts`

**Implementation**

1. Replace controller-owned Prisma with an injected `AvatarService` using the shared Prisma client.
2. Define request DTOs and reject unknown fields.
3. Accept a content type from an allowlist such as JPEG/PNG/WebP. Derive the extension server-side; do not concatenate a raw `ext` supplied by the client. During the current-client compatibility window, accept `ext` only as a deprecated field, require it to match the canonical MIME mapping, and ignore it for key generation; remove it after a coordinated mobile rollout.
4. Generate keys only as `avatars/{authenticatedUserId}/{serverGeneratedId}.{derivedExtension}`.
5. Persist a short-lived, single-use pending upload intent containing the authenticated user, exact generated key, canonical content type, maximum bytes, expiry, and consumed state. Confirmation must reference and atomically consume this intent; prefix grammar alone does not prove the key was issued.
6. Issue an upload grant that enforces exact key/type and a storage-boundary byte range (for example an S3 POST policy with `content-length-range`). A post-upload `HeadObject` check alone does not prevent storage-cost abuse.
7. Confirmation must:
   - match the exact user-owned key grammar;
   - reject another user's prefix and all traversal/separator variants outside the grammar;
   - match an unexpired, unconsumed server-issued intent;
   - call `HeadObject`;
   - verify `ContentType`, a deliberate maximum `ContentLength`, and expected key;
   - update only the authenticated user's record and consume the intent atomically.
8. Initial reopen limits: 10 MiB maximum object, at most 2 unconsumed intents per account, 10 intent requests per account per hour, and a five-minute intent expiry. Expired intents and rejected/abandoned/oversized objects enter cleanup immediately; an independent bucket lifecycle removes never-confirmed objects within 24 hours. Changing these values requires a recorded abuse/cost review.
9. When replacing an avatar, delete the previous S3 object only if it matches that same user's approved prefix. Make DB update authoritative and object cleanup retryable so a transient S3 error cannot corrupt the profile.
10. Update the Flutter avatar client for the enforced upload mechanism and redact current logs that expose local image paths, S3 response bodies, keys, or signed URLs. Return/log only safe status/error codes.
11. Return an opaque avatar response. Do not expose bucket credentials or internal filesystem paths.

**How to verify**

- Another user's key, an unissued/expired/consumed intent, a valid-looking key with the wrong user ID, unsupported type, mismatched S3 metadata, zero/oversized object, encoded separator, and unknown field all fail before Prisma update.
- Storage rejects an oversized upload before accepting the object; abandoned/rejected objects are removed by the tested cleanup/lifecycle path.
- A generated key passes request → upload → confirm → read/display.
- Current `ext`/`contentType` and `key`/`contentType` mobile payloads have explicit compatibility tests during the transition.
- Repeating confirm is idempotent.
- Replacing an avatar cannot delete another user's object.
- Tests mock S3 and assert both positive behavior and absence of unsafe calls.

**Acceptance**

- Clients can select content but cannot select storage ownership or arbitrary key paths.

### IP-0.5 — Fail closed on configuration and secret use

**Primary files**

- `RythmRun_backend_nodejs/src/app.ts`
- `RythmRun_backend_nodejs/src/middleware/auth.middleware.ts`
- `RythmRun_backend_nodejs/src/services/user.service.ts`
- `RythmRun_backend_nodejs/src/services/s3.service.ts`
- `RythmRun_backend_nodejs/.env.example`
- New `RythmRun_backend_nodejs/src/config/env.ts` and its tests

**Implementation**

1. Add one configuration module that loads environment variables before the container, Prisma, or S3 client is imported/constructed.
2. Require `JWT_SECRET` and `REFRESH_TOKEN_SECRET`; reject missing values, documented placeholders, values below the chosen entropy/length floor, and identical access/refresh secrets.
3. Remove every `|| 'your-secret-key'` and equivalent executable fallback.
4. Standardize the refresh secret name. The current code mixes `REFRESH_TOKEN_SECRET` and `JWT_REFRESH_SECRET`; this phase adopts the name documented in `.env.example`, while IP-2 redesigns refresh behavior.
5. A full server environment currently mounts avatar/activity-image routes, so require the AWS region, bucket, CloudFront domain/key pair/private key, and database URL. If an emergency feature flag disables those routes, validate the flag explicitly, leave routes fail-closed, and do not construct their clients. Error messages name the missing variable but never print its value.
6. Split application construction from `listen` and allow integration tests to inject fake dependencies/config explicitly; tests do not become ambiguous by inheriting developer AWS variables. Keep the full server lifecycle work for IP-5.

**How to verify**

- A production-mode process with a missing, placeholder, short, or reused JWT secret exits non-zero before listening.
- Valid configuration starts and signs/verifies tokens with only the configured values.
- S3 is not constructed before environment loading.
- `.env.example` lists every required name with non-secret examples and no real credentials.

**Acceptance**

- A misconfigured deploy fails visibly; it never becomes a service accepting forgeable tokens.

### IP-0.6 — Investigate exposure and rotate credentials

This is operational work. Store sensitive evidence in the approved incident system, not Git.

**Implementation**

1. Query user avatar fields for suspicious absolute paths, traversal, separators inconsistent with valid generated local names, unexpected extensions/types, and S3 prefixes owned by a different user. Record counts and row IDs only in the restricted incident record.
2. Review edge/application logs for:
   - registration/profile bodies containing undeclared avatar/path fields, where body logging exists;
   - unusual `GET /api/users/profile-picture/*` volume or identifiers;
   - repeated avatar confirmation keys or cross-user prefixes;
   - correlated authentication or S3 access anomalies.
3. Determine the earliest possible exposure from deployment/version history. Document log coverage gaps; absence of retained logs is not proof of no exposure.
4. If exposure cannot be confidently excluded, rotate in a no-downtime order:
   - create replacement database and AWS credentials with least privilege;
   - deploy the service using replacements while routes remain contained;
   - rotate CloudFront signing material;
   - rotate JWT access and refresh secrets and revoke stored refresh sessions, accepting a forced login;
   - revoke old database/AWS/CDN credentials and prove they no longer work.
5. Inspect the runtime identity/IAM policy and reduce it to the required bucket prefixes/actions. Verify the Node process cannot read unnecessary mounted secrets or write source/config directories.
6. Verify infrastructure posture that source review could not prove: S3 public-access block, object ownership, encryption at rest, abandoned-object lifecycle, access evidence, CloudFront origin access (bucket not bypassable), database TLS enforcement, backup retention, and a successful isolated restore. Record gaps as actions, not assumptions.
7. Record whether user notification or formal incident reporting is required under the applicable policy/law; obtain qualified legal/security review rather than guessing.

**How to verify**

- Old credentials fail authentication after the cutover.
- The service works with only replacement credentials.
- Refresh-token rows/sessions issued under the old secrets cannot be used.
- Direct bucket access is blocked as designed, CDN origin controls work, database TLS is required, and a backup restore succeeds in isolation.
- The incident record states one of: confirmed exposure, exposure not found with adequate evidence, or exposure cannot be excluded and rotation/notification actions completed.

**Acceptance**

- "No suspicious logs found" is accepted only when log scope and retention cover the exposure window; otherwise rotate.

### IP-0.7 — Regression suite, staging rollout, and controlled reopen

**Automated test cases**

- Undeclared user fields on registration and profile update.
- A standard local-only traversal/absolute-path/encoding/control-character corpus and nested unexpected objects; do not publish exploit payloads before containment.
- A pre-seeded unsafe legacy `profilePicturePath` cannot read or delete.
- Foreign-user and malformed avatar keys.
- S3 type/length mismatch and missing object.
- Missing/placeholder JWT and S3 configuration.
- Valid registration, login, avatar request/confirm/display, replacement, and logout smoke paths.

**Staging sequence**

1. Deploy with avatar/profile routes still restricted.
2. Apply safe data cleanup/migration against a sanitized snapshot or representative fixtures.
3. Run backend tests, typecheck, the approved MC-0.10 dependency scan, and the negative HTTP suite.
4. Triage all production advisories from the dated scan—not only Multer. Upgrade/remove affected packages or record a time-bounded owner-approved exception with reachability evidence; no exposed critical/high advisory is accepted for reopen.
5. Run a supported Flutter build through avatar upload/display/replacement.
6. Verify logs contain request IDs and safe error categories but no secrets, raw keys beyond what is necessary, response bodies, signed URLs, or filesystem paths.
7. Add the minimum backend security CI job defined in IP-0.7a immediately after the merged emergency application slice, so subsequent security changes are protected by clean install, Prisma generation/validation, typecheck, and backend tests. IP-1 expands this to Flutter and analyzer ratchets. A committed workflow is not operational CI evidence until a successful GitHub Actions run URL is recorded.
8. Open routes in stages: registration/profile text fields first, S3 avatar request/confirm next. Never reopen local filesystem routes. Keep avatar routes contained if storage-boundary limits, intent checks, quota, or cleanup are incomplete.
9. Monitor `4xx`, `5xx`, registration, avatar-confirm, storage rejection, and S3 error rates continuously, with an explicit 24-hour heightened observation window after reopen and an owner/on-call rollback trigger.

#### IP-0.7 dependency-surface reduction — current repository package

**Status**

- In progress on `ip0-dependency-advisories`.
- This package reduces known dependency risk but does not satisfy the dated advisory gate. MC-0.10 remains blocked until an owner explicitly approves the outbound npm scan and every result is triaged.

**Implementation**

1. Replace end-of-support `aws-sdk` v2 with the minimum modular v3 packages required for S3 commands, S3 PUT/POST signing, and CloudFront read signing.
2. Preserve the existing storage contract: explicit credentials/region, exact key/type/length POST policy, bounded expiry, object metadata verification, deletes, and signed CloudFront reads.
3. Standardize backend development, CI, and deployment on Node.js 22.x because current AWS SDK v3 releases require Node 20+ and the CI package already uses Node 22. Do not deploy until MC-0.6 confirms the hosted runtime.
4. Remove direct production dependencies only when repository-wide import/config and dependency-path checks prove they are unused. At this 2026-07-11 package boundary those candidates were `joi`, direct `pg`, and `winston`. IP-1.6 later supersedes only the `pg` decision: Prisma 7.8 intentionally requires the PostgreSQL driver through `@prisma/adapter-pg`, so its reviewed return is adapter infrastructure rather than restoration of an unused application dependency.
5. Add a dependency-surface regression that prevents reintroducing the monolithic SDK or proven-unused packages while explicitly allowing the exact Prisma adapter/driver relationship introduced by IP-1.6.
6. Build-tool placement was deliberately unchanged in this historical slice. IP-1.6 later moves Prisma/TypeScript build tooling under a native-ESM build contract; MC-1.13 must prove the host installs those tools before generate/build/migrate and prunes only afterward.

**How to verify**

- Run a clean `npm ci --no-audit`, Prisma validation/generation, `npx tsc --noEmit`, `npm run build`, and the full backend suite on Node.js 22.x. Keep the separately approved, dated audit in MC-0.10 rather than relying on npm's implicit install-time submission.
- Prove tests cover v3 PUT/POST signing inputs, S3 `HeadObject`/`DeleteObject` command dispatch, CloudFront expiry/signing inputs, and the existing avatar lifecycle behavior.
- Confirm `npm ls aws-sdk joi winston` has no installed production path and source contains no `aws-sdk` v2 import. Separately confirm `npm ls @prisma/adapter-pg pg` resolves only the reviewed Prisma 7.8 adapter/driver surface and that application source does not create independent pools outside the database factory.
- Run MC-0.10 only after explicit outbound-scan approval; retain the full dated report and one decision per result.

**Acceptance**

- Repository checks pass with equivalent storage behavior and without AWS SDK v2, `joi`, or `winston`. The dated removal of unused direct `pg` remains valid historical evidence; its later adapter-backed reintroduction has the superseding IP-1.6 rationale and MC-1.12 pool proof.
- Node.js 22.x is explicit in package metadata, CI, and developer documentation.
- Advisory closure, staging compatibility, deployed runtime, and production safety remain manual gates and are not inferred from this change.

### IP-0.7a — Repository-delivered; hosted verification pending: Express HTTP security regressions and minimum backend CI

**Status**

- Repository implementation committed in `c52fb87`. Hosted success, intentional-failure, and branch-protection evidence remain open as MC-0.7 through MC-0.9. The merged IP-0.2 through IP-0.5 application slice remains undeployed and production-unverified.
- No CI success is claimed until a GitHub Actions run URL demonstrates the committed workflow on the repository host.

**Implementation**

1. Add Express-level regression tests that exercise the mounted routes, authentication boundary, DTO validation, controller mapping, and HTTP response instead of proving only service behavior.
2. Cover registration and profile updates with undeclared/server-managed fields and assert a `400` response with no persistence mutation.
3. Prove the retired local profile-picture read/write routes are not mounted and cannot reach filesystem behavior.
4. Cover avatar request/confirm rejection at the HTTP boundary for invalid payloads and unauthenticated requests without exposing keys, signed URLs, paths, or secrets in test output.
5. Keep S3, Prisma, and other external infrastructure deterministic through explicit test doubles; these tests are local regressions, not staging evidence.
6. Add a minimum backend GitHub Actions workflow that performs a clean dependency install, Prisma validation/generation, TypeScript typecheck, and the backend test suite using non-secret test configuration.
7. Keep dependency-advisory review explicit. A green test workflow does not satisfy the dated production-advisory gate unless the dependency scan is separately run, triaged, and recorded.

**How to verify**

- Run the Express regression suite locally and record its exact test count together with the full backend-suite total.
- Open a pull request or push the workflow through the normal protected path, then record the successful GitHub Actions run URL. File presence or local workflow inspection alone is not proof that CI is operational.
- Deliberately break a security assertion on a temporary/non-merge revision and confirm the workflow fails, or record an equivalent intentional-failure probe.
- Confirm no staging, production, advisory, incident-containment, credential-rotation, migration, mobile-rollout, or lifecycle-rule checkbox is closed by this package.

**Acceptance**

- The relevant security boundaries have Express-level regression coverage and a successful hosted backend CI run is linked.
- Completion of IP-0.7a does not authorize route reopen or mark IP-0 complete.

## Rollback plan

- Keep edge containment rules ready and independently deployable.
- If the patched release fails, re-enable containment before rolling application code back.
- Never roll back to a build that exposes local file reads/deletes or fallback JWT secrets.
- Database cleanup must have a backup and a reversible mapping for legitimate avatar values. Unsafe values remain quarantined even during application rollback.
- Credential rotation is not rolled back to exposed credentials; issue new replacements if the cutover itself is compromised.

## Verification matrix

| Scenario | Layer | Expected result | Evidence |
| --- | --- | --- | --- |
| Register with a forbidden server-managed path field from the local security corpus | HTTP + persistence | `400`; no forbidden field reaches Prisma | Automated integration test |
| Update profile with absolute/local path | HTTP + persistence | `400`; user row unchanged | Automated integration test |
| Seed unsafe legacy row and request picture | HTTP + filesystem | No file read; local route absent/non-success | Integration test with filesystem spy |
| Confirm another user's S3 key | Service + S3 | Rejected before `HeadObject`/Prisma update as applicable | Unit test |
| Confirm mismatched type/size | Service + S3 | Rejected; user row unchanged | Unit test |
| Start with placeholder JWT secret | Process startup | Non-zero exit before listen | Configuration test |
| Valid avatar lifecycle | Staging/mobile | Upload, confirm, display, replace succeeds | Staging run record |
| Use old credentials after rotation | Infrastructure | Authentication/signature fails | Restricted incident evidence |
| Probe contained/reopened routes | Production | Only hardened routes succeed | Dated smoke record |

## Exit gate

- [ ] Production containment was applied and independently verified.
- [ ] Relevant logs and a database snapshot were preserved before cleanup.
- [x] Registration/profile fields are allowlisted and unknown fields are rejected locally.
- [x] No client-controlled value reaches the touched user/avatar Prisma writes through object spread/pass-through.
- [x] Local filesystem avatar routes are removed from the application.
- [x] The S3 avatar service proves authenticated user ownership, key shape, issued intent, object existence, type, and bounded size in automated tests.
- [ ] Avatar upload uses a single-use server intent, storage-enforced size/type/key policy, minimal rate/quota, and abandoned-object cleanup.
- [x] The avatar controller/service uses the shared Prisma lifetime.
- [x] Missing or documented placeholder configuration prevents local startup; executable JWT fallbacks are gone.
- [ ] Existing suspicious avatar values were inventoried and quarantined/migrated safely.
- [ ] Exposure has a documented disposition; required credential rotation and revocation are complete.
- [ ] Negative security tests and the valid avatar lifecycle pass.
- [ ] All dated production advisories are remediated or have explicit reachability/expiry decisions; no exposed critical/high advisory remains.
- [ ] Minimal isolated staging and backend security CI are operational.
- [ ] Staging and production smoke checks pass after a controlled reopen.
- [ ] Rollback keeps the vulnerable paths contained.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Older mobile clients depend on local avatar routes | Measure supported-version usage, keep routes contained, and require a client update rather than restoring unsafe behavior. |
| Cleanup deletes legitimate avatar references | Snapshot first; classify, migrate, and update in batches with a reversible mapping. |
| Credential rotation causes widespread logout/downtime | Stage replacement credentials, deploy first, revoke old second, and communicate forced login. |
| Tests prove string filtering but miss path canonicalization/symlinks | Remove filesystem behavior; if temporarily retained, test real-path containment and symlinks explicitly. |
| A quick DTO fix is bypassed elsewhere | Explicitly construct Prisma data in the service as a second boundary. |
| S3 prefix validation alone accepts an unexpected object | Tie confirmation to a server-issued key and verify `HeadObject` metadata. |

## Evidence log

| Date | Work package | Evidence | Result | Notes |
| --- | --- | --- | --- | --- |
| 2026-07-10 | IP-0.2 | `user-input-hardening.test.ts`; full backend suite | Pass | Unknown/server-managed fields rejected; explicit user Prisma mappings tested. |
| 2026-07-10 | IP-0.3 | `user-routes.test.ts`; source/dependency scan | Pass locally | Local profile-picture routes and filesystem sinks removed; Multer absent from the installed tree. Production route containment remains unverified. |
| 2026-07-10 | IP-0.4 | `avatar.service.test.ts` (38 tests); Flutter avatar tests; full suites | Pass locally | Backend 113/113 and Flutter 21/21 passed. Migration, real S3 lifecycle, multipart upload/display/replacement, and controlled rollout still require staging evidence. |
| 2026-07-10 | IP-0.5 | `env.test.ts`, `server-bootstrap.test.ts`, TypeScript/build/Prisma validation | Pass locally | Configuration is validated before consumer imports; missing/documented placeholders fail closed. Deployment smoke test remains open. |
| 2026-07-10 | IP-0.7 | `flutter analyze` baseline comparison | Partial | Analyzer remains at the audited baseline of 159 findings (6 warnings, 153 info); no increase. Current production advisory scan could not run in the restricted environment and remains an explicit gate. |
| 2026-07-10 | IP-0.2–IP-0.5 | `e33f314`, merged through `54a5b26` into `origin/main` | Merged; not deployed | Repository delivery is confirmed. Migration, staging, production, incident-response, credential-rotation, mobile-rollout, and infrastructure evidence remain open. |
| 2026-07-10 | IP-0.7a | `http-security-boundary.test.ts` (16 tests); full backend suite (129 tests); `backend-security.yml` local structure review | Pass locally; hosted CI pending | Express-boundary regressions, typecheck, and local suite pass. No operational CI pass is claimed until a successful GitHub Actions run URL and intentional-failure probe are added. |
| 2026-07-11 | IP-0.7 dependency surface | Node.js 22.22.3 clean install; Prisma validate/generate; TypeScript/build; focused dependency/storage suites (50 tests); full backend suite (141 tests); package/source scans | Pass locally; advisory/staging pending | Replaced AWS SDK v2 with modular v3, retained storage-contract coverage including real PUT presigning without an empty-body checksum and with signed content type, removed `joi`/`pg`/`winston`, and found no remaining v2 source/import or installed direct path. MC-0.6 and MC-0.10 remain open; no hosted, staging, deployment, or current-advisory claim is made. |
| 2026-07-13 | IP-1.6 superseding dependency decision | Prisma 7.8 config/generator/adapter, centralized database lifecycle, clean install, schema/type/build/test/smoke gates | Pass locally; hosted/staging pending | Preserves the 2026-07-11 fact that unused direct `pg` was removed, but deliberately restores the PostgreSQL driver as the exact runtime behind `@prisma/adapter-pg`. Node 22.22.3 restored the reviewed graph; Prisma validation/generation, production typecheck/build, 15 suites/244 tests, and the built no-database smoke passed. One database factory owns the client/pool; MC-1.12 must still prove real TLS, migration, transaction, pool, and disconnect behavior. |
