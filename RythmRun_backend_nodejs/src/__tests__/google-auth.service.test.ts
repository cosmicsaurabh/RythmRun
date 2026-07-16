import { jest } from '@jest/globals';
import { gaxios } from 'google-auth-library';

import { GoogleAuthService } from '../services/google-auth.service.js';

const CLIENT_ID = 'backend-client.apps.googleusercontent.com';

function serviceWithPayload(payload: object | undefined) {
  const verifyIdToken = jest.fn().mockResolvedValue({
    getPayload: () => payload,
  });
  return {
    verifyIdToken,
    service: new GoogleAuthService(
      CLIENT_ID,
      { verifyIdToken } as never,
    ),
  };
}

describe('GoogleAuthService', () => {
  it('verifies audience and returns only normalized verified claims', async () => {
    const { service, verifyIdToken } = serviceWithPayload({
      sub: 'google-subject-123',
      email: ' Runner@Example.COM ',
      email_verified: true,
      given_name: '  Ada  ',
      family_name: 'R'.repeat(75),
    });

    await expect(service.verifyIdToken('provider-id-token')).resolves.toEqual({
      subject: 'google-subject-123',
      email: 'runner@example.com',
      firstname: 'Ada',
      lastname: 'R'.repeat(50),
    });
    expect(verifyIdToken).toHaveBeenCalledWith({
      idToken: 'provider-id-token',
      audience: CLIENT_ID,
    });
  });

  it.each([
    ['missing payload', undefined],
    [
      'unverified email',
      {
        sub: 'google-subject-123',
        email: 'runner@example.com',
        email_verified: false,
      },
    ],
    [
      'missing subject',
      { email: 'runner@example.com', email_verified: true },
    ],
    [
      'missing email',
      { sub: 'google-subject-123', email_verified: true },
    ],
    [
      'oversized subject',
      {
        sub: 's'.repeat(256),
        email: 'runner@example.com',
        email_verified: true,
      },
    ],
  ])('rejects a ticket with %s', async (_case, payload) => {
    const { service } = serviceWithPayload(payload);

    await expect(service.verifyIdToken('provider-id-token')).rejects.toMatchObject({
      code: 'AUTH_GOOGLE_INVALID',
      statusCode: 401,
      message: 'Google identity token is invalid',
    });
  });

  it('maps invalid-token verifier failures to one safe authentication error', async () => {
    const sensitiveMessage = 'signature failure containing token internals';
    const verifyIdToken = jest.fn().mockRejectedValue(new Error(sensitiveMessage));
    const service = new GoogleAuthService(
      CLIENT_ID,
      { verifyIdToken } as never,
    );

    try {
      await service.verifyIdToken('provider-id-token');
      throw new Error('Expected verification to fail');
    } catch (error: unknown) {
      expect(error).toMatchObject({
        code: 'AUTH_GOOGLE_INVALID',
        statusCode: 401,
      });
      expect((error as Error).message).not.toContain(sensitiveMessage);
    }
  });

  it.each([
    new Error(
      'Failed to retrieve verification certificates: provider-id-token network details',
    ),
    new gaxios.GaxiosError(
      'provider-id-token certificate endpoint failure',
      {} as never,
    ),
  ])('maps an identifiable Google verification outage to a safe 503', async (failure) => {
    const verifyIdToken = jest.fn().mockRejectedValue(failure);
    const service = new GoogleAuthService(
      CLIENT_ID,
      { verifyIdToken } as never,
    );

    await expect(
      service.verifyIdToken('provider-id-token'),
    ).rejects.toMatchObject({
      code: 'AUTH_GOOGLE_UNAVAILABLE',
      statusCode: 503,
      message: 'Google authentication is temporarily unavailable',
      retryable: true,
    });

    try {
      await service.verifyIdToken('provider-id-token');
    } catch (error: unknown) {
      expect((error as Error).message).not.toContain('provider-id-token');
      expect((error as Error).message).not.toContain(failure.message);
    }
  });
});
