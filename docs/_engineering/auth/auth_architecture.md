# RythmRun Authentication & Session Architecture

This document provides a high-level overview of the authentication, session state management, and token refresh lifecycle in RythmRun.

---

## Session States

The application's active session is represented by `SessionState` and managed inside [session_provider.dart](file:///Users/saurabhreshape/per-repo/RythmRun/rythmrun_frontend_flutter/lib/presentation/common/providers/session_provider.dart):

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
- **`authenticated`**: Full access. The user has valid, fresh credentials and is fully synced with the backend.
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
            Provider->>API: POST /auth/refresh (unawaited)
            alt Refresh Success
                API-->>Provider: Return new token pair
                Provider-->>App: Transition to authenticated (Synced)
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
            Provider->>API: GET /auth/validate-session (unawaited)
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
