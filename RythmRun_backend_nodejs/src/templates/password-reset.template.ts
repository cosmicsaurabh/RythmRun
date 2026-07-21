export interface PasswordResetEmailContent {
  firstname?: string | null;
  resetUrl: string;
}

export const PASSWORD_RESET_EMAIL_SUBJECT = 'Reset your RythmRun password';

const BRAND = 'RythmRun';
const ACCENT = '#0e9c74';

/**
 * firstname is user-supplied and resetUrl is embedded in HTML, so both are
 * escaped before interpolation to prevent HTML/attribute injection.
 */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function greetingName(firstname?: string | null): string {
  const trimmed = firstname?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : 'there';
}

export function renderPasswordResetEmailText(
  content: PasswordResetEmailContent,
): string {
  const name = greetingName(content.firstname);
  return [
    `Hi ${name},`,
    '',
    `We received a request to reset your ${BRAND} password.`,
    '',
    'Open this link to choose a new password:',
    content.resetUrl,
    '',
    'This link expires in 30 minutes and can be used once. If you did not',
    'request a password reset, you can safely ignore this email — your',
    'password will not change.',
  ].join('\n');
}

export function renderPasswordResetEmailHtml(
  content: PasswordResetEmailContent,
): string {
  const name = escapeHtml(greetingName(content.firstname));
  const url = escapeHtml(content.resetUrl);
  return `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:0;background:#f5f6f8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#14181d;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f6f8;padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:12px;padding:32px;">
            <tr>
              <td style="font-size:20px;font-weight:700;letter-spacing:-0.01em;padding-bottom:8px;">${BRAND}</td>
            </tr>
            <tr>
              <td style="font-size:16px;line-height:1.6;color:#3d454e;padding-bottom:20px;">
                Hi ${name},<br /><br />
                We received a request to reset your ${BRAND} password.
              </td>
            </tr>
            <tr>
              <td style="padding-bottom:24px;">
                <a href="${url}" style="display:inline-block;background:${ACCENT};color:#ffffff;text-decoration:none;font-weight:600;font-size:15px;padding:12px 24px;border-radius:8px;">Reset password</a>
              </td>
            </tr>
            <tr>
              <td style="font-size:13px;line-height:1.6;color:#667079;">
                Or paste this link into your browser:<br />
                <a href="${url}" style="color:${ACCENT};word-break:break-all;">${url}</a>
              </td>
            </tr>
            <tr>
              <td style="font-size:12px;line-height:1.6;color:#98a0a8;padding-top:24px;border-top:1px solid #e8ecf1;">
                This link expires in 30 minutes and can be used once. If you did not request a password reset, you can safely ignore this email — your password will not change.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}
