# Email Verification, Password Recovery & Safe Google Account Linking

Operational guide for the shared email-token delivery feature, including email
verification, password recovery, and the safe automatic account linking that
verification enables.

## What these features do

A Google sign-in whose email matches an existing local account is **merged
automatically only if that account has already proven control of the email**
(`emailVerified = true`). Any other collision is refused with
`AUTH_EMAIL_UNVERIFIED_CONFLICT` (409).

A password-capable account can also request a single-use, 30-minute password
reset link. The request response is identical whether the account exists, is
Google-only, is cooling down, or receives an email. Consuming a valid link
changes the existing password and revokes every active session in the same
transaction; it never adds a password to a Google-only account.

### Why the gate exists

A merge attaches a second credential to one account, so it is safe only when
**both** sides independently prove the same mailbox:

- **Google's side is already proven.** `google-auth.service.ts` rejects any ID
  token unless Google asserts `email_verified === true`.
- **The local side is the missing proof.** `register()` performs no email
  verification, so `username` is only a string someone typed.

Without the gate, an attacker could pre-register a password account for
`victim@gmail.com` (an inbox they do not own) with a password they know. When
the real owner later signs in with Google, an unconditional email-match merge
would attach the victim's Google identity to the attacker's row — leaving one
account reachable by *both* parties. Requiring `emailVerified = true` defeats
this, because the attacker can never read the victim's inbox to flip the flag.

**Never** backfill or bulk-set `emailVerified = true` on password accounts to
"reduce friction". That re-opens exactly this hole.

## Scope (deliberate non-goals)

Verification gates **only** the automatic merge. Password recovery rotates an
existing password but does not itself set `emailVerified`.

- Login and registration **succeed normally for unverified users**, who keep
  full access to the app behind a non-blocking banner.
- Wiring `emailVerified` into the login path would lock out every pre-existing
  account, since the migration backfills password accounts to `false`.

## Configuration

All email variables are an **optional group** shared by verification and
password recovery (see `.env.example`). Leave them unset and the app boots with
delivery disabled; set any and all required ones must be present.

| Variable | Required when enabled | Notes |
| --- | --- | --- |
| `SMTP_HOST` | yes | e.g. `smtp-relay.brevo.com` |
| `SMTP_USER` | yes | provider login |
| `SMTP_PASS` | yes | provider **SMTP key**, not the account password |
| `MAIL_FROM` | yes | must be a verified sender/domain |
| `PUBLIC_APP_URL` | yes | absolute origin used to build the emailed link |
| `SMTP_PORT` | no | defaults to `587` |
| `SMTP_SECURE` | no | defaults to `false` (STARTTLS on 587); `true` for 465 |

### Provider: Brevo (free tier)

Chosen because it is free-forever (300 emails/day), needs no credit card, and
is a standard SMTP relay.

1. Create a Brevo account and open **SMTP & API → SMTP**.
2. Generate an SMTP key. Use it as `SMTP_PASS`.
3. Authorize your sender, either:
   - **Preferred — authenticate your domain.** Add Brevo's DKIM record, add
     Brevo to your SPF record (`v=spf1 include:spf.brevo.com ~all`), and
     publish a DMARC record. This gives aligned SPF/DKIM and the best inbox
     placement, and lets you send from `noreply@your-domain.com`.
   - **Fallback — single-sender verification.** Verify one mailbox you own by
     clicking Brevo's confirmation link. Mail is then signed with Brevo's own
     DKIM domain, which still authenticates but may display "via brevo".

The sending domain does **not** need to match the API host. A Render
`*.onrender.com` host cannot carry DNS records, so authenticate your own
domain and keep `PUBLIC_APP_URL` pointed at the API.

### Local development

Point the same variables at a capture-only inbox so no real mail is delivered:

```
SMTP_HOST="sandbox.smtp.mailtrap.io"
PUBLIC_APP_URL="http://localhost:8080"
```

## Deploying (order matters)

Neither `npm start` nor `npm run build` applies migrations, and this repo has
no `render.yaml`. **Migrations must run as a release step**, or new code will
query an `emailVerified` column or token purpose that does not exist and fail
the verification/recovery paths.

1. **Set Render's Pre-Deploy Command to `npm run migrate:deploy`.** Confirm it
   runs before the new image serves traffic.
2. Add the email variables to Render's environment.
3. Deploy the API.
4. Release the mobile client last.

Both migrations are additive. The email column has a DB-level default, and
older code ignores the new column and token-purpose value.

### What the migrations do

- Adds `User.emailVerified` (`NOT NULL DEFAULT false`).
- Backfills `emailVerified = true` **only** where `googleSubject IS NOT NULL`
  — those accounts were created from a Google identity that Google had already
  verified. Password accounts stay `false` and re-verify through the normal
  flow.
- Creates `VerificationToken`, which stores only a SHA-256 digest, with one
  outstanding token per user per purpose.
- Adds the `PASSWORD_RESET` token purpose without creating a second token
  table; the unique `(userId, purpose)` key keeps verification and recovery
  tokens independent.

## Endpoints

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `GET /api/users/verify-email?token=…` | public | Consumes a token and renders an HTML result page |
| `POST /api/users/verify-email/resend` | required | Re-sends the link to the signed-in owner |
| `POST /api/users/password-reset/request` | public | Accepts an email and always returns the same generic acknowledgement |
| `GET /api/users/password-reset?token=…` | public | Renders the same-origin password-reset form |
| `POST /api/users/password-reset` | public | Consumes the token, changes the existing password, and revokes all sessions |

`GET /verify-email` is **idempotent**: re-presenting a consumed token for an
already-verified user renders success, not an error. This matters because
mail scanners and browsers routinely prefetch links, which would otherwise
burn a single-use token before the human clicks it. The page is served with a
tightened CSP and `Referrer-Policy: no-referrer` so the token in the URL
cannot leak.

Verification resend is owner-only (the user id comes from the access token,
never the request body) and has both a database cooldown and an in-process
per-account request budget. Password-reset requests have the same database
cooldown plus an account+client-address budget; reset submissions have a
client-address budget. The in-process layer is defence in depth only: it clears
on restart and is not shared between Render instances, so MC-2.6 requires a
single replica until the counters move to shared storage or the edge.

## Operating notes

- **Never log** the raw token, its digest, or recipient addresses. Send
  failures log only the error category. Keep the SMTP transport's debug mode
  off — it prints recipients.
- **Send failures are non-fatal.** Verification email delivery happens *after*
  the registration transaction commits, so a failed or slow SMTP call never
  rolls back a registered user or fails their request. Users recover with
  the resend button.
- **Quota exhaustion** (300/day on Brevo's free tier) degrades the same way:
  registration still succeeds, the email just is not delivered.
- Expired verification tokens are purged on the existing 15-minute sweep timer.

## Known gaps

- **The merge is inert for legacy accounts** until they verify. Pre-existing
  password users still receive a 409 on Google sign-in; the intended recovery
  journey is *sign in with password → verify via the banner → retry Google*.
- **Recovery does not silently verify an email.** A mailbox owner who cannot
  sign in can use *forgot password → reset → sign in → verify via the banner →
  retry Google*. Keeping reset and verification as separate token purposes
  preserves the explicit linking gate.
- **Production delivery remains unverified.** MC-2.5 still requires the real
  SMTP/provider, sender-domain authentication, staging verification/reset
  delivery, one-use behavior, session revocation, and on-device flows.
- **English only.** The verification email and result page have no i18n.
