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
| Last updated | 2026-07-17 |
| Entry condition | None; containment begins immediately |
| Exit condition | All criteria in [Exit gate](#exit-gate) have evidence |

## Outcome

After this phase, an HTTP client cannot write a local filesystem path or arbitrary S3 key into a user record, no request can cause the backend to read or delete a file outside an approved avatar object, missing secrets stop startup, and the possible production exposure has a documented incident disposition.

This file is a plan, not proof that production is safe.

Every hosted and human-operated gate lives in [ACTION-REQUIRED.md](./ACTION-REQUIRED.md). Keep them open until they carry dated, independently reviewed evidence.

## Merged implementation checkpoint

Commit `e33f314`, merged into `origin/main` by merge commit `54a5b26`, contains the reviewable application slice for IP-0.2 through IP-0.5:

- strict DTO allowlists plus explicit Prisma write mappings;
- removal of the local filesystem avatar routes, handlers, middleware, and Multer dependency;
- an authenticated, expiring, single-use avatar intent with ownership, type, and size verification, quotas, atomic confirmation, and durable bounded cleanup retries;
- a coordinated Flutter upload client with size/type checks and redacted avatar logging; and
- environment validation before infrastructure imports, with no executable JWT fallback secrets.

> The upload mechanism in `e33f314` was a multipart POST policy. **Cloudflare R2
> does not support presigned POST**, so its `content-length-range` never bound.
> `76fa16f` replaced it with a presigned PUT carrying a signed `content-length`
> — see [the IP-0.4 correction](#the-ip-04-upload-grant-correction-2026-07-28-76fa16f)
> below. Any client or evidence written against the POST mechanism is obsolete.

This merged checkpoint is repository evidence, not deploy authorization or production verification. The additive database migration must precede the backend, older clients require a coordinated or forced update, the independent bucket lifecycle rule still needs infrastructure evidence, and IP-0.1/IP-0.6 plus staging and production checks remain open.

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

## Ordered work packages — what remains

All four are operational. Delivered packages are summarized further down.

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

#### IP-0.7 dependency-surface reduction — repository-delivered package

**Status**

- Repository implementation is committed in `fc33dca`; it is no longer the current package.
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

## Delivered packages — IP-0.2, 0.3, 0.4, 0.5, 0.7-dep, 0.7a

Merged and locally tested. Their step-by-step implementation text was removed on
2026-08-11 as finished work; git history holds it. None of them is deployed or
production-verified.

| Pkg | What it established | Still gated on |
| --- | --- | --- |
| IP-0.2 Writable-field allowlists | Unknown and server-managed fields are rejected at the DTO boundary, and the service constructs Prisma data explicitly as a second boundary — so a bypassed DTO cannot set `profilePicturePath`. Merged `e33f314` | Deployment; re-run under the 0.7 controlled reopen |
| IP-0.3 Retire filesystem avatars | The local profile-picture routes and every filesystem sink are gone, and Multer is absent from the installed tree. One storage pipeline, not two | Production route-containment proof (MC-0.1); quarantine of suspicious legacy avatar rows (MC-0.4) |
| IP-0.4 Harden the avatar pipeline | Server-derived keys under `avatars/{userId}/{serverId}.{ext}`, a single-use pending upload intent that confirmation atomically consumes, a content-type allowlist, `HeadObject` verification, and same-prefix-only deletion on replace. See the correction below | MC-0.11 against real R2 — **its earlier evidence is void**; plus per-account quota and a bucket-lifecycle rule |
| IP-0.5 Fail closed on config and secrets | One configuration module loading before the container, Prisma, or the storage client is constructed; required `JWT_SECRET`/`REFRESH_TOKEN_SECRET` with placeholder, length, and reuse rejection; no executable fallbacks; application construction split from `listen` | A hosted deployment smoke proving a production process with a missing, placeholder, short, or reused secret exits non-zero *before* listening |
| IP-0.7-dep Dependency-surface reduction | AWS SDK v2 replaced by modular v3; `joi`, `pg`, and `winston` removed. Committed `fc33dca` | MC-0.10 (blocked pending approval); hosted Node 22 confirmation |
| IP-0.7a HTTP security regressions + minimum CI | Express-boundary regression suite and the `Backend security` workflow definition. Committed `c52fb87` | MC-0.7 run URL, MC-0.8 failure probe, MC-0.9 branch protection |

### The IP-0.4 upload-grant correction (2026-07-28, `76fa16f`)

Worth keeping in the working tree because it corrects something this phase
recorded as delivered.

IP-0.4 required a grant enforcing the byte range **at the storage boundary**,
and named an S3 POST policy with `content-length-range` as the mechanism. The
first implementation used exactly that. **Cloudflare R2 does not support
presigned POST**, so on this deployment the grant enforced nothing and the byte
bound existed only on paper.

What ships now:

- A presigned **PUT** whose signed header set contains both `content-type` and
  `content-length`. The uploader must present exactly the signed values or
  storage rejects the request. The `HeadObject` confirmation check remains as
  defense in depth, not as the primary control.
- **No public delivery origin.** `R2_PUBLIC_URL` is no longer a required
  variable, and an authenticated `GET /avatar/read-url` returns a short-lived
  presigned GET for the caller's own key — refusing any key outside that user's
  prefix and answering `404` when nothing is stored. Both buckets stay private.
- **Explicit buckets everywhere.** `headObject` and `deleteObject` previously
  fell back to a default bucket, which was the *activity-image* bucket, so
  avatar confirmation and cleanup were addressing the wrong one. Both now pass
  `R2_BUCKET_AVATARS`.
- The legacy `JWT_REFRESH_SECRET` name is retired in favor of
  `REFRESH_TOKEN_SECRET` only, and documented-placeholder rejection now also
  matches `your-*` values.

None of this is proven against real R2. MC-0.11 must be re-run — the client
mechanism changed from multipart POST to signed PUT — and MC-0.5 must confirm
public delivery is *retired*, not merely unused.

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
| 2026-07-28 | IP-0.4 avatar re-hardening | `76fa16f`, merged to main through PR #170 (`bec25c0`); `avatar.service.test.ts` and `s3.service.test.ts` reworked; `env.test.ts` and `http-security-boundary.test.ts` extended; Flutter avatar repository/profile suites updated | Pass locally; real-R2 proof still open | Corrects a control this log previously recorded as delivered. The IP-0.4 grant was a presigned POST policy, which Cloudflare R2 does not support, so its `content-length-range` never bound; the grant is now a presigned PUT with `content-type` and `content-length` in the signed header set, which storage does enforce. Public avatar delivery is removed — `R2_PUBLIC_URL` is no longer a required variable and an authenticated `GET /avatar/read-url` issues a short-lived presigned GET for the caller's own key — so both buckets stay private. `headObject`/`deleteObject` now take an explicit bucket; avatar confirm and cleanup had been inheriting the activity-image bucket default. The legacy `JWT_REFRESH_SECRET` name is retired in favor of `REFRESH_TOKEN_SECRET` only, and documented-placeholder rejection now also matches `your-*` values. **No real-R2 evidence is claimed:** that a signed `content-length` is rejected by R2 when violated, the abandoned-object lifecycle rule, and the per-account quota all remain MC-level work, and MC-0.11 must be re-run because the client upload mechanism changed from multipart POST to signed PUT. |
| 2026-08-11 | IP-0 plan reconciliation | Current `main` (`de93182`): backend `npm test` 464 passed / 7 skipped / 471 total across 26 suites, `npm run typecheck` clean; Flutter `flutter test` 359 passed; `flutter analyze --no-pub --no-fatal-infos` 9 issues, zero warnings, zero errors | Pass locally; counted-baseline comparison not reproducible locally | Records the state of `main` at the 2026-08-11 reconciliation. The counted analyzer baseline is stamped Flutter 3.44.1 / Dart 3.12.1 to match the CI pin; this machine now runs Flutter 3.44.9 / Dart 3.12.2, so `analyzer_baseline.dart check` exits with a toolchain-mismatch error by design. The raw analyzer numbers above are reproducible; the baseline comparison is currently evidencable only on the pinned CI toolchain. No new operational, staging, or deployment claim is made. |
