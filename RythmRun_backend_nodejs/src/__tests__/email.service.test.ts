import { jest } from '@jest/globals';
import type { Transporter } from 'nodemailer';

import type { EmailEnvironment } from '../config/env.js';
import {
  NoopEmailSender,
  NodemailerEmailSender,
  buildVerificationUrl,
  createEmailSender,
} from '../services/email.service.js';

const config: EmailEnvironment = {
  host: 'smtp-relay.brevo.com',
  port: 587,
  secure: false,
  user: 'mailer@reshapeapp.ai',
  pass: 'brevo-smtp-key',
  from: 'RythmRun <noreply@reshapeapp.ai>',
  publicAppUrl: 'https://rythmrun.onrender.com',
};

function fakeTransport(): {
  transporter: Transporter;
  sendMail: jest.Mock;
} {
  const sendMail = jest.fn<() => Promise<unknown>>().mockResolvedValue({});
  return {
    transporter: { sendMail } as unknown as Transporter,
    sendMail,
  };
}

describe('buildVerificationUrl', () => {
  it('joins the base URL, route, and url-encoded token', () => {
    expect(buildVerificationUrl('https://rythmrun.onrender.com', 'a b/c')).toBe(
      'https://rythmrun.onrender.com/api/users/verify-email?token=a%20b%2Fc',
    );
  });
});

describe('createEmailSender', () => {
  it('returns a disabled no-op sender when config is null', async () => {
    const sender = createEmailSender(null);
    expect(sender).toBeInstanceOf(NoopEmailSender);
    expect(sender.enabled).toBe(false);
    await expect(
      sender.sendEmailVerification({ to: 'x@y.com', rawToken: 'tok' }),
    ).resolves.toBeUndefined();
  });

  it('returns an enabled SMTP sender when config is present', () => {
    const { transporter } = fakeTransport();
    const sender = createEmailSender(config, transporter);
    expect(sender).toBeInstanceOf(NodemailerEmailSender);
    expect(sender.enabled).toBe(true);
  });
});

describe('NodemailerEmailSender', () => {
  it('sends a verification email with both text and html parts', async () => {
    const { transporter, sendMail } = fakeTransport();
    const sender = new NodemailerEmailSender(config, transporter);

    await sender.sendEmailVerification({
      to: 'runner@example.com',
      firstname: 'Ada',
      rawToken: 'secret-token',
    });

    expect(sendMail).toHaveBeenCalledTimes(1);
    const message = sendMail.mock.calls[0][0] as {
      from: string;
      to: string;
      subject: string;
      text: string;
      html: string;
    };
    expect(message.from).toBe(config.from);
    expect(message.to).toBe('runner@example.com');
    const expectedUrl = buildVerificationUrl(config.publicAppUrl, 'secret-token');
    expect(message.text).toContain(expectedUrl);
    expect(message.html).toContain(expectedUrl);
    expect(message.html).toContain('Ada');
  });

  it('propagates transport failures to the caller', async () => {
    const { transporter, sendMail } = fakeTransport();
    sendMail.mockRejectedValueOnce(new Error('SMTP 535 auth failed'));
    const sender = new NodemailerEmailSender(config, transporter);

    await expect(
      sender.sendEmailVerification({ to: 'x@y.com', rawToken: 'tok' }),
    ).rejects.toThrow('SMTP 535 auth failed');
  });

  it('escapes a user-controlled firstname in the HTML body', async () => {
    const { transporter, sendMail } = fakeTransport();
    const sender = new NodemailerEmailSender(config, transporter);

    await sender.sendEmailVerification({
      to: 'x@y.com',
      firstname: '<script>alert(1)</script>',
      rawToken: 'tok',
    });

    const message = sendMail.mock.calls[0][0] as { html: string };
    expect(message.html).not.toContain('<script>alert(1)</script>');
    expect(message.html).toContain('&lt;script&gt;');
  });
});
