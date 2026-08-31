# RythmRun Authentication & Session Architecture

This document provides a high-level overview of the authentication, session state management, and token refresh lifecycle in RythmRun.

---

## Session States

The application's active session is represented by `SessionState` and managed
inside
[`session_provider.dart`](../../../rythmrun_frontend_flutter/lib/presentation/common/providers/session_provider.dart):

```mermaid
stateDiagram-v2
    [*] --> initial
    initial --> checking : App Startup
    checking --> authenticated : Fresh credentials found
    checking --> authenticatedOffline : Expired credentials (offline allowed)
    checking --> unauthenticated : No credentials / Revoked

    state authenticated {
        [*] --> online
    }

    state authenticatedOffline {
        [*] --> offlineMode
    }

    authenticated --> refreshing : Explicit refresh / request failure
    authenticatedOffline --> refreshing : Explicit refresh
    refreshing --> authenticated : Refresh success
    refreshing --> authenticatedOffline : Refresh network failure
    refreshing --> unauthenticated : Refresh rejected (invalid token)
```

- **`initial`**: The default state before any initialization checks have run.
- **`checking`**: The state when the app is executing startup database reads or active online/offline validation checks.
- **`authenticated`**: The user has valid, fresh credentials and can use online
  operations. Workout/image sync may still be queued, restoring, blocked, or
  failed; this state does not mean that data is fully synchronized.
- **`authenticatedOffline`**: Bounded offline access. The user is logged in locally, but the app operates in offline-first mode. Direct API mutations and sync are disabled via the `OnlineOperationGuard`.
- **`unauthenticated`**: Guest state. The user must sign in or register to access the app.
- **`refreshing`**: A manual token refresh is in progress.

---

## App Launch Flow (Optimistic Launch)

To achieve a near-instant perceived startup, RythmRun implements an **Optimistic Launch** sequence during initialization:

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant Provider as SessionProvider
    participant DB as Platform Secure Storage
    participant API as Backend (onrender.com)

    App->>Provider: Initialize Session (Boot)
    Provider->>DB: Read user credentials & offline policy (Parallelized)
    DB-->>Provider: Returns (user, expired?, 7-day-ok?)

    alt User exists & within 7-day window
        alt Token is expired
            Provider-->>App: Emit authenticatedOffline (Instantly opens Home Screen)
            Note over Provider, API: Silent Background Refresh
            Provider->>API: POST /api/users/refresh-token (unawaited)
            alt Refresh Success
                API-->>Provider: Return new token pair
                Provider-->>App: Transition to authenticated (Online)
            else Refresh Rejected (401 Revoked)
                API-->>Provider: Return 401
                Provider->>DB: Clear local session
                Provider-->>App: Transition to unauthenticated (Forced Logout)
            else Refresh Unavailable (503/Timeout)
                Provider-->>App: Remain authenticatedOffline quietly
            end
        else Token is fresh
            Provider-->>App: Emit authenticated (Instantly opens Home Screen)
            Note over Provider, API: Silent Background Validation
            Provider->>API: GET /api/users/me (unawaited)
            alt Validation Invalid (401)
                API-->>Provider: Return 401
                Provider->>DB: Clear local session
                Provider-->>App: Transition to unauthenticated (Forced Logout)
            end
        end
    else Credentials missing or 7-day window exceeded
        Provider->>API: Validate session online (Blocking)
        alt Success
            Provider-->>App: Emit authenticated
        else Failed/Offline
            Provider-->>App: Emit unauthenticated
        end
    end
```

---

## Session exit and retained owner data

Normal logout, account switch, and forced authentication loss quiesce tracking
and drain admitted user work. W1 makes user-state invalidation awaitable:
the workout repository receives the explicit old-owner ID, teardown awaits that
owner's `history_restored=false` write, invalidates the user-scoped providers,
and only then allows credential cleanup to complete. The persistence service
requires `setBool` success and a matching readback; reset failure leaves provider
state and credentials available for recovery. A pending forced-loss marker
reruns the old owner's teardown after restart before credentials are removed. It
does not call `clearLocalWorkouts`, so every owner workout, queued deletion,
point, status, and activity-image row survives normal session exit.

Provider state and local reads/mutations remain user-scoped. Account B cannot
read account A's retained rows, and signing back in as A makes A's rows available
again. The owner-scoped local purge primitive remains intact and reserved for a
future explicit account-deletion path; the current app has no wired in-app
deletion flow. These changes correct the repository portions of D-004,
`SYNC-01`, and `SYNC-09`, while MC-1.6, MC-2.3, and account-deletion E2E still
require external evidence. W1 changes an internal Flutter repository API, not
the backend or server HTTP API.

Retained SQLite data and activity-photo files are still plaintext at rest. The
IP-2.7 encrypted database/file migration, wrapped-key and backup rules,
performance and key-loss behavior, account-deletion E2E, and device proof remain
open.

---

## Bootstrapping History on Login

When a user authenticates and the per-user `history_restored` flag is false, the
`SyncCoordinator` starts a one-shot background bootstrap:

1. It fetches `GET /api/activities?page=N&limit=50` pages. These are full
   activity payloads, including routes; pagination limits row count but does not
   guarantee a small response or prevent a timeout.
2. It inserts only activities not already identified locally by
   `clientSyncId`/remote ID. If the process stops before completion, the flag
   stays false and the next run restarts at page 1; deduplication makes the
   replay idempotent.
3. It sets the flag true only after all pages complete. Normal session exit now
   awaits the old user's reset to false while retaining the owner's local rows,
   so that owner can recheck remote history without losing local-first data.
   The persistence service verifies each boolean write and readback. A failed
   `history_restored=true` completion write can still abort that sync pass before
   push while the durable work remains queued; runbook Step 3 owns isolation.

This is transitional restore behavior, not full bidirectional sync. It has no
cursor/revision, ongoing pull, remote tombstones, remote-image restore, or
per-item failure isolation, and a restore failure currently prevents push in
the same coordinator pass. IP-4 owns those corrections.

---

## Token Rotation and Security Seams

1. **Atomic Envelope:** The access token and refresh token are written atomically to secure storage as a single versioned envelope. The envelope's version represents the credential generation.
2. **Single-Flight Refresh:** Token refresh calls are protected by a single-flight mutex (`AuthenticationAttemptGate`). If three requests hit expired tokens at once, only one refresh call is made; the other two wait and replay using the successor token.
3. **Strict Reuse Detection:** Refresh tokens are single-use. If a refresh token is used a second time (e.g., due to replay attacks), the server immediately invalidates the entire session family, logging out all active clients.
4. **Eviction of Failed Flights:** If a token refresh fails, the coordinator evicts the failed flight immediately so that subsequent requests retry cleanly.

---

## Connectivity Classification

When network requests fail, the app differentiates between **device offline** states and **backend service downtime** to avoid misleading user feedback:

- **True Device Offline:** The device is disconnected from Wi-Fi and Cellular networks (or the DNS check to `8.8.8.8` fails).
  - Exception: `AuthSessionUnavailableReason.network`
  - User Messaging: *"The session could not be refreshed while offline."*
- **Backend Service Unavailable:** The device is connected to the internet, but the request to `rythmrun.onrender.com` fails (timeouts, 502 Bad Gateway, or connection refused).
  - Exception: `AuthSessionUnavailableReason.serviceUnavailable`
  - User Messaging: *"The authentication service is temporarily unavailable."*
