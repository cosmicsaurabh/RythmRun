const BRAND = 'RythmRun';
const ACCENT = '#0e9c74';
const ERROR = '#d1435b';

const PAGE_HEAD = (title: string): string => `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex" />
    <title>${title} · ${BRAND}</title>
    <style>
      body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
        background: #f5f6f8; color: #14181d;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
      .card { background: #ffffff; max-width: 420px; margin: 16px; padding: 40px 32px; border-radius: 16px;
        box-shadow: 0 8px 30px rgba(20,24,29,0.08); text-align: center; width: 100%; box-sizing: border-box; }
      .brand { font-size: 14px; font-weight: 700; letter-spacing: 0.02em; color: #667079; margin-bottom: 20px; }
      h1 { font-size: 22px; margin: 0 0 12px; letter-spacing: -0.01em; }
      p { font-size: 15px; line-height: 1.6; color: #3d454e; margin: 0 0 8px; }
      form { margin-top: 20px; text-align: left; }
      label { display: block; font-size: 13px; font-weight: 600; color: #3d454e; margin-bottom: 6px; }
      input[type=password] { width: 100%; box-sizing: border-box; padding: 11px 12px; font-size: 15px;
        border: 1px solid #dde2e9; border-radius: 8px; margin-bottom: 16px; }
      button { width: 100%; background: ${ACCENT}; color: #ffffff; border: 0; border-radius: 8px;
        padding: 12px; font-size: 15px; font-weight: 600; cursor: pointer; }
      .err { color: ${ERROR}; font-size: 13px; margin: 0 0 12px; }
      .mark { width: 56px; height: 56px; border-radius: 50%; margin: 0 auto 20px;
        display: flex; align-items: center; justify-content: center; font-size: 28px; color: #ffffff; }
    </style>
  </head>
  <body>
    <main class="card">
      <div class="brand">${BRAND}</div>`;

const PAGE_FOOT = `
    </main>
  </body>
</html>`;

function escapeAttr(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * The password-reset form. The single-use token travels in a hidden field and
 * the form POSTs (url-encoded, same-origin) back to this route — no inline
 * script, so it works under the tightened `form-action 'self'` CSP without a
 * nonce. `errorMessage` re-renders the form after a failed submit.
 */
export function renderResetForm(token: string, errorMessage?: string): string {
  const safeToken = escapeAttr(token);
  const error = errorMessage
    ? `<p class="err">${escapeAttr(errorMessage)}</p>`
    : '';
  return `${PAGE_HEAD('Reset password')}
      <h1>Choose a new password</h1>
      <p>Enter a new password for your ${BRAND} account.</p>
      ${error}
      <form method="post" action="/api/users/password-reset">
        <input type="hidden" name="token" value="${safeToken}" />
        <label for="newPassword">New password</label>
        <input id="newPassword" name="newPassword" type="password" autocomplete="new-password"
          minlength="8" maxlength="50" required />
        <button type="submit">Reset password</button>
      </form>${PAGE_FOOT}`;
}

export function renderResetSuccess(): string {
  return `${PAGE_HEAD('Password reset')}
      <div class="mark" style="background:${ACCENT};">✓</div>
      <h1>Password updated</h1>
      <p>Your password has been changed and all sessions were signed out. Open the ${BRAND} app and sign in with your new password.</p>${PAGE_FOOT}`;
}

export function renderResetError(): string {
  return `${PAGE_HEAD('Link invalid or expired')}
      <div class="mark" style="background:${ERROR};">!</div>
      <h1>This link didn’t work</h1>
      <p>The reset link is invalid or has expired. Open the ${BRAND} app and request a new password-reset email.</p>${PAGE_FOOT}`;
}
