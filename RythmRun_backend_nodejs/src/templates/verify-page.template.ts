export type VerifyPageState = 'success' | 'already' | 'error';

interface VerifyPageCopy {
  title: string;
  heading: string;
  body: string;
  accent: string;
}

const COPY: Record<VerifyPageState, VerifyPageCopy> = {
  success: {
    title: 'Email verified',
    heading: 'Email verified',
    body: 'Your email address is confirmed. You can return to the RythmRun app and continue.',
    accent: '#0e9c74',
  },
  already: {
    title: 'Already verified',
    heading: 'Already verified',
    body: 'This email address is already confirmed. You can return to the RythmRun app.',
    accent: '#0e9c74',
  },
  error: {
    title: 'Link invalid or expired',
    heading: 'This link didn’t work',
    body: 'The verification link is invalid or has expired. Open the RythmRun app and request a new verification email.',
    accent: '#d1435b',
  },
};

/**
 * Renders a static, self-contained verification result page. No user input is
 * interpolated, so inline styles are safe. This route is served with a tight
 * per-response CSP (default-src 'none'; style-src 'unsafe-inline') and
 * Referrer-Policy: no-referrer so the token in the URL cannot leak.
 */
export function renderVerifyPage(state: VerifyPageState): string {
  const copy = COPY[state];
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex" />
    <title>${copy.title} · RythmRun</title>
    <style>
      body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
        background: #f5f6f8; color: #14181d;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
      .card { background: #ffffff; max-width: 420px; margin: 16px; padding: 40px 32px; border-radius: 16px;
        box-shadow: 0 8px 30px rgba(20,24,29,0.08); text-align: center; }
      .brand { font-size: 14px; font-weight: 700; letter-spacing: 0.02em; color: #667079; margin-bottom: 20px; }
      .mark { width: 56px; height: 56px; border-radius: 50%; margin: 0 auto 20px;
        display: flex; align-items: center; justify-content: center; font-size: 28px; color: #ffffff;
        background: ${copy.accent}; }
      h1 { font-size: 22px; margin: 0 0 12px; letter-spacing: -0.01em; }
      p { font-size: 15px; line-height: 1.6; color: #3d454e; margin: 0; }
    </style>
  </head>
  <body>
    <main class="card">
      <div class="brand">RythmRun</div>
      <div class="mark">${state === 'error' ? '!' : '✓'}</div>
      <h1>${copy.heading}</h1>
      <p>${copy.body}</p>
    </main>
  </body>
</html>`;
}
