export interface VerificationEmailContent {
  firstname?: string | null;
  verificationUrl: string;
}

export const VERIFICATION_EMAIL_SUBJECT = 'Verify your RythmRun email';

const BRAND = 'RythmRun';
const ACCENT = '#0e9c74';

/**
 * firstname is user-supplied and verificationUrl is embedded in HTML, so both
 * are escaped before interpolation to prevent HTML/attribute injection in the
 * rendered email.
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

export function renderVerificationEmailText(
  content: VerificationEmailContent,
): string {
  const name = greetingName(content.firstname);
  return [
    `Hi ${name},`,
    '',
    `Confirm your email address to finish setting up your ${BRAND} account.`,
    '',
    'Open this link to verify:',
    content.verificationUrl,
    '',
    'This link expires in 24 hours. If you did not create a RythmRun account,',
    'you can safely ignore this email.',
  ].join('\n');
}

export function renderVerificationEmailHtml(
  content: VerificationEmailContent,
): string {
  const name = escapeHtml(greetingName(content.firstname));
  const url = escapeHtml(content.verificationUrl);
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
                Confirm your email address to finish setting up your ${BRAND} account.
              </td>
            </tr>
            <tr>
              <td style="padding-bottom:24px;">
                <a href="${url}" style="display:inline-block;background:${ACCENT};color:#ffffff;text-decoration:none;font-weight:600;font-size:15px;padding:12px 24px;border-radius:8px;">Verify email</a>
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
                This link expires in 24 hours. If you did not create a ${BRAND} account, you can safely ignore this email.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}
