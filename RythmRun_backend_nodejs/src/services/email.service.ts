import nodemailer, { type Transporter } from 'nodemailer';

import type { EmailEnvironment } from '../config/env.js';
import {
  VERIFICATION_EMAIL_SUBJECT,
  renderVerificationEmailHtml,
  renderVerificationEmailText,
} from '../templates/email-verification.template.js';

export interface SendEmailVerificationInput {
  to: string;
  firstname?: string | null;
  rawToken: string;
}

/**
 * Transport-agnostic email boundary. UserService depends only on this
 * interface, so delivery can be swapped (SMTP provider, HTTP API, no-op)
 * without touching auth logic, and unit tests inject a fake.
 */
export interface EmailSender {
  readonly enabled: boolean;
  sendEmailVerification(input: SendEmailVerificationInput): Promise<void>;
}

// The path of the public, unauthenticated verification GET route. Kept here
// because building the emailed link is an email concern.
const VERIFY_EMAIL_PATH = '/api/users/verify-email';

export function buildVerificationUrl(
  publicAppUrl: string,
  rawToken: string,
): string {
  return `${publicAppUrl}${VERIFY_EMAIL_PATH}?token=${encodeURIComponent(rawToken)}`;
}

/**
 * Used when email is not configured. Verification links are simply not sent;
 * the rest of the app (registration, login, banner) still works.
 */
export class NoopEmailSender implements EmailSender {
  readonly enabled = false;

  async sendEmailVerification(): Promise<void> {
    // Intentionally does nothing; email delivery is disabled.
  }
}

export class NodemailerEmailSender implements EmailSender {
  readonly enabled = true;
  private readonly transporter: Transporter;

  constructor(
    private readonly config: EmailEnvironment,
    transporter?: Transporter,
  ) {
    this.transporter =
      transporter ??
      nodemailer.createTransport({
        host: config.host,
        port: config.port,
        secure: config.secure,
        // Force STARTTLS on non-implicit-TLS ports (e.g. 587) so credentials
        // and links are never transmitted in cleartext.
        requireTLS: !config.secure,
        auth: { user: config.user, pass: config.pass },
      });
  }

  async sendEmailVerification(input: SendEmailVerificationInput): Promise<void> {
    const verificationUrl = buildVerificationUrl(
      this.config.publicAppUrl,
      input.rawToken,
    );
    await this.transporter.sendMail({
      from: this.config.from,
      to: input.to,
      subject: VERIFICATION_EMAIL_SUBJECT,
      text: renderVerificationEmailText({
        firstname: input.firstname,
        verificationUrl,
      }),
      html: renderVerificationEmailHtml({
        firstname: input.firstname,
        verificationUrl,
      }),
    });
  }
}

/**
 * Resolves the concrete sender from optional config: a real SMTP sender when
 * configured, otherwise a no-op. Always returns an EmailSender so the DI token
 * can be registered unconditionally.
 */
export function createEmailSender(
  config: EmailEnvironment | null,
  transporter?: Transporter,
): EmailSender {
  if (config === null) {
    return new NoopEmailSender();
  }
  return new NodemailerEmailSender(config, transporter);
}
