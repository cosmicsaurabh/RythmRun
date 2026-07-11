import 'reflect-metadata';

import { AvatarController } from '../controllers/avatar.controller';
import { validateDto } from '../middleware/validation.middleware';
import {
  ConfirmAvatarUploadDto,
  RequestAvatarUploadDto,
} from '../models/dto/avatar.dto';
import {
  AVATAR_UPLOAD_INTENT_TTL_MS,
  AvatarService,
  AvatarServiceError,
  MAX_AVATAR_UPLOAD_REQUESTS_PER_WINDOW,
  MAX_PENDING_AVATAR_UPLOADS,
} from '../services/avatar.service';

const NOW = new Date('2026-07-10T10:00:00.000Z');
const USER_ID = 1;
const AVATAR_KEY =
  'avatars/1/123e4567-e89b-42d3-a456-426614174000.jpg';
const PREVIOUS_AVATAR_KEY =
  'avatars/1/123e4567-e89b-42d3-a456-426614174001.png';

function createMockPrisma() {
  const avatarUploadIntent = {
    count: jest.fn(),
    create: jest.fn(),
    delete: jest.fn(),
    findMany: jest.fn().mockResolvedValue([]),
    findUnique: jest.fn(),
    updateMany: jest.fn(),
  };
  const user = {
    findUnique: jest.fn(),
    update: jest.fn(),
  };
  const transaction = { avatarUploadIntent, user };
  const prisma = {
    avatarUploadIntent,
    user,
    $transaction: jest.fn(
      async (operation: (client: typeof transaction) => Promise<unknown>) =>
        operation(transaction),
    ),
  };

  return { prisma, transaction };
}

function createMockS3() {
  return {
    getPresignedPost: jest.fn(
      async ({ key }: { key: string }) => ({
        uploadUrl: 'https://uploads.example.com',
        fields: {
          key,
          Policy: 'signed-policy',
          'X-Amz-Signature': 'signature',
        },
        key,
      }),
    ),
    headObject: jest.fn(),
    deleteObject: jest.fn(),
  };
}

function buildIntent(overrides: Record<string, unknown> = {}) {
  return {
    id: 'intent-1',
    userId: USER_ID,
    key: AVATAR_KEY,
    contentType: 'image/jpeg',
    sizeBytes: 1024,
    expiresAt: new Date(NOW.getTime() + AVATAR_UPLOAD_INTENT_TTL_MS),
    consumedAt: null,
    cleanupKey: null,
    cleanupCompletedAt: null,
    createdAt: NOW,
    ...overrides,
  };
}

describe('AvatarService upload authorization', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(NOW);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('creates a user-bound intent and returns the multipart POST contract', async () => {
    const { prisma } = createMockPrisma();
    const s3 = createMockS3();
    prisma.avatarUploadIntent.count
      .mockResolvedValueOnce(0)
      .mockResolvedValueOnce(0);
    prisma.avatarUploadIntent.create.mockImplementation(
      async ({ data }: { data: Record<string, unknown> }) =>
        buildIntent({ ...data, id: 'intent-created' }),
    );
    const service = new AvatarService(prisma as any, s3 as any);

    const result = await service.requestUpload(USER_ID, {
      ext: 'jpeg',
      contentType: 'image/jpeg',
      sizeBytes: 1024,
    });

    const createdData = prisma.avatarUploadIntent.create.mock.calls[0][0].data;
    expect(createdData).toMatchObject({
      userId: USER_ID,
      contentType: 'image/jpeg',
      sizeBytes: 1024,
      expiresAt: new Date(NOW.getTime() + AVATAR_UPLOAD_INTENT_TTL_MS),
    });
    expect(createdData.key).toMatch(
      /^avatars\/1\/[0-9a-f-]{36}\.jpg$/,
    );
    expect(s3.getPresignedPost).toHaveBeenCalledWith({
      key: createdData.key,
      contentType: 'image/jpeg',
      sizeBytes: 1024,
      expiresSeconds: 300,
    });
    expect(result).toEqual({
      uploadUrl: 'https://uploads.example.com',
      uploadMethod: 'POST',
      fields: {
        key: createdData.key,
        Policy: 'signed-policy',
        'X-Amz-Signature': 'signature',
      },
      key: createdData.key,
      expiresAt: '2026-07-10T10:05:00.000Z',
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(
      expect.any(Function),
      { isolationLevel: 'Serializable' },
    );
  });

  it.each([
    ['image/gif', 'gif'],
    ['text/plain', 'txt'],
  ])('rejects unsupported content type %s', async (contentType, ext) => {
    const { prisma } = createMockPrisma();
    const s3 = createMockS3();
    const service = new AvatarService(prisma as any, s3 as any);

    await expect(
      service.requestUpload(USER_ID, { contentType, ext, sizeBytes: 1024 }),
    ).rejects.toMatchObject({ statusCode: 400 });
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(s3.getPresignedPost).not.toHaveBeenCalled();
  });

  it('requires a compatibility extension to match the MIME type', async () => {
    const { prisma } = createMockPrisma();
    const s3 = createMockS3();
    const service = new AvatarService(prisma as any, s3 as any);

    await expect(
      service.requestUpload(USER_ID, {
        ext: 'png',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
      }),
    ).rejects.toThrow('Avatar extension does not match content type');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it.each([0, 10 * 1024 * 1024 + 1, 1.5])(
    'rejects invalid declared size %p',
    async sizeBytes => {
      const { prisma } = createMockPrisma();
      const s3 = createMockS3();
      const service = new AvatarService(prisma as any, s3 as any);

      await expect(
        service.requestUpload(USER_ID, {
          contentType: 'image/png',
          sizeBytes,
        }),
      ).rejects.toThrow('Invalid avatar size');
      expect(prisma.$transaction).not.toHaveBeenCalled();
    },
  );

  it('enforces the hourly request limit before creating an intent', async () => {
    const { prisma } = createMockPrisma();
    const s3 = createMockS3();
    prisma.avatarUploadIntent.count.mockResolvedValueOnce(
      MAX_AVATAR_UPLOAD_REQUESTS_PER_WINDOW,
    );
    const service = new AvatarService(prisma as any, s3 as any);

    await expect(
      service.requestUpload(USER_ID, {
        contentType: 'image/png',
        sizeBytes: 1024,
      }),
    ).rejects.toMatchObject({
      message: 'Avatar upload rate limit exceeded',
      statusCode: 429,
    });
    expect(prisma.avatarUploadIntent.create).not.toHaveBeenCalled();
    expect(s3.getPresignedPost).not.toHaveBeenCalled();
  });

  it('enforces the active pending-intent limit', async () => {
    const { prisma } = createMockPrisma();
    const s3 = createMockS3();
    prisma.avatarUploadIntent.count
      .mockResolvedValueOnce(0)
      .mockResolvedValueOnce(MAX_PENDING_AVATAR_UPLOADS);
    const service = new AvatarService(prisma as any, s3 as any);

    await expect(
      service.requestUpload(USER_ID, {
        contentType: 'image/png',
        sizeBytes: 1024,
      }),
    ).rejects.toMatchObject({
      message: 'Too many pending avatar uploads',
      statusCode: 429,
    });
    expect(prisma.avatarUploadIntent.create).not.toHaveBeenCalled();
  });

  it('removes the pending intent if POST signing fails', async () => {
    const { prisma } = createMockPrisma();
    const s3 = createMockS3();
    const intent = buildIntent();
    prisma.avatarUploadIntent.count
      .mockResolvedValueOnce(0)
      .mockResolvedValueOnce(0);
    prisma.avatarUploadIntent.create.mockResolvedValue(intent);
    prisma.avatarUploadIntent.delete.mockResolvedValue(intent);
    s3.getPresignedPost.mockRejectedValueOnce(new Error('signing failed'));
    const service = new AvatarService(prisma as any, s3 as any);

    await expect(
      service.requestUpload(USER_ID, {
        contentType: 'image/jpeg',
        sizeBytes: 1024,
      }),
    ).rejects.toThrow('signing failed');
    expect(prisma.avatarUploadIntent.delete).toHaveBeenCalledWith({
      where: { id: intent.id },
    });
  });

  it('retries a serialization conflict so quota checks stay race-safe', async () => {
    const { prisma, transaction } = createMockPrisma();
    const s3 = createMockS3();
    const serializationFailure = { code: 'P2034' };
    prisma.$transaction
      .mockRejectedValueOnce(serializationFailure)
      .mockImplementationOnce(
        async (operation: (client: typeof transaction) => Promise<unknown>) =>
          operation(transaction),
      );
    prisma.avatarUploadIntent.count
      .mockResolvedValueOnce(0)
      .mockResolvedValueOnce(0);
    prisma.avatarUploadIntent.create.mockResolvedValue(buildIntent());
    const service = new AvatarService(prisma as any, s3 as any);

    await service.requestUpload(USER_ID, {
      contentType: 'image/jpeg',
      sizeBytes: 1024,
    });

    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });

  it('rejects undeclared request fields before reaching the service', async () => {
    await expect(
      validateDto(RequestAvatarUploadDto, {
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        key: AVATAR_KEY,
      }),
    ).rejects.toThrow('Validation failed');
  });
});

describe('AvatarService confirmation', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(NOW);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  function createConfirmationHarness() {
    const { prisma } = createMockPrisma();
    const s3 = createMockS3();
    const intent = buildIntent();
    prisma.avatarUploadIntent.findUnique.mockResolvedValue(intent);
    prisma.avatarUploadIntent.updateMany.mockResolvedValue({ count: 1 });
    prisma.user.findUnique.mockResolvedValue({
      profilePicturePath: null,
      profilePictureType: null,
    });
    prisma.user.update.mockResolvedValue({});
    s3.headObject.mockResolvedValue({
      ContentType: intent.contentType,
      ContentLength: intent.sizeBytes,
    });
    s3.deleteObject.mockResolvedValue(undefined);
    const service = new AvatarService(prisma as any, s3 as any);

    return { prisma, s3, intent, service };
  }

  const confirmation: ConfirmAvatarUploadDto = {
    key: AVATAR_KEY,
    contentType: 'image/jpeg',
  };

  it('atomically consumes the intent and selects the verified avatar', async () => {
    const { prisma, s3, intent, service } = createConfirmationHarness();
    prisma.user.findUnique.mockResolvedValue({
      profilePicturePath: PREVIOUS_AVATAR_KEY,
      profilePictureType: 'image/png',
    });
    prisma.user.findUnique
      .mockResolvedValueOnce({ profilePicturePath: PREVIOUS_AVATAR_KEY })
      .mockResolvedValueOnce({ profilePicturePath: intent.key });

    const result = await service.confirmUpload(USER_ID, confirmation);

    expect(s3.headObject).toHaveBeenCalledWith(intent.key);
    expect(prisma.avatarUploadIntent.updateMany).toHaveBeenCalledWith({
      where: {
        id: intent.id,
        userId: USER_ID,
        key: intent.key,
        contentType: intent.contentType,
        sizeBytes: intent.sizeBytes,
        consumedAt: null,
        expiresAt: { gt: NOW },
      },
      data: {
        consumedAt: NOW,
        cleanupKey: PREVIOUS_AVATAR_KEY,
      },
    });
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: USER_ID },
      data: {
        profilePicturePath: intent.key,
        profilePictureType: intent.contentType,
      },
    });
    expect(s3.deleteObject).toHaveBeenCalledWith(PREVIOUS_AVATAR_KEY);
    expect(prisma.avatarUploadIntent.updateMany).toHaveBeenCalledWith({
      where: {
        id: intent.id,
        userId: USER_ID,
        cleanupKey: PREVIOUS_AVATAR_KEY,
        cleanupCompletedAt: null,
      },
      data: { cleanupCompletedAt: NOW },
    });
    expect(result).toEqual({
      key: intent.key,
      contentType: intent.contentType,
      alreadyConfirmed: false,
    });
  });

  it('never reads S3 for a key outside the authenticated user prefix', async () => {
    const { prisma, s3, service } = createConfirmationHarness();

    await expect(
      service.confirmUpload(USER_ID, {
        ...confirmation,
        key: 'avatars/2/123e4567-e89b-42d3-a456-426614174000.jpg',
      }),
    ).rejects.toThrow('Invalid avatar key');
    expect(prisma.avatarUploadIntent.findUnique).not.toHaveBeenCalled();
    expect(s3.headObject).not.toHaveBeenCalled();
  });

  it.each([
    'avatars/1/../123e4567-e89b-42d3-a456-426614174000.jpg',
    'avatars/1/%2e%2e%2f123e4567-e89b-42d3-a456-426614174000.jpg',
    'avatars/1/123e4567-e89b-42d3-a456-426614174000.jpg/extra',
  ])('rejects malformed key %s before reading S3', async key => {
    const { prisma, s3, service } = createConfirmationHarness();

    await expect(
      service.confirmUpload(USER_ID, { ...confirmation, key }),
    ).rejects.toThrow('Invalid avatar key');
    expect(prisma.avatarUploadIntent.findUnique).not.toHaveBeenCalled();
    expect(s3.headObject).not.toHaveBeenCalled();
  });

  it('rejects an unissued but well-formed key before reading S3', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    prisma.avatarUploadIntent.findUnique.mockResolvedValue(null);

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).rejects.toThrow('Invalid avatar upload intent');
    expect(s3.headObject).not.toHaveBeenCalled();
  });

  it.each([
    { code: 'NotFound', statusCode: 404 },
    { name: 'NotFound', $metadata: { httpStatusCode: 404 } },
    { name: 'NoSuchKey', $metadata: { httpStatusCode: 404 } },
  ])('maps a missing S3 object error %# to a safe client error', async error => {
    const { prisma, s3, service } = createConfirmationHarness();
    s3.headObject.mockRejectedValue(error);

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).rejects.toMatchObject({
      message: 'Uploaded avatar was not found',
      statusCode: 400,
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('maps an S3 verification outage to a safe retryable error', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    s3.headObject.mockRejectedValue(new Error('raw AWS detail'));

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).rejects.toMatchObject({
      message: 'Avatar storage verification is temporarily unavailable',
      statusCode: 503,
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects and removes an expired owned upload', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    prisma.avatarUploadIntent.findUnique.mockResolvedValue(
      buildIntent({ expiresAt: new Date(NOW.getTime() - 1) }),
    );

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).rejects.toMatchObject({
      message: 'Avatar upload intent has expired',
      statusCode: 410,
    });
    expect(s3.deleteObject).toHaveBeenCalledWith(AVATAR_KEY);
    expect(s3.headObject).not.toHaveBeenCalled();
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it.each([
    [{ ContentType: 'image/png', ContentLength: 1024 }],
    [{ ContentType: 'image/jpeg', ContentLength: 1023 }],
    [{ ContentType: 'image/jpeg', ContentLength: 0 }],
    [{ ContentType: undefined, ContentLength: 1024 }],
    [{ ContentType: 'image/jpeg', ContentLength: undefined }],
  ])('rejects mismatched S3 metadata %#', async metadata => {
    const { prisma, s3, service } = createConfirmationHarness();
    s3.headObject.mockResolvedValue(metadata);

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).rejects.toThrow('Uploaded avatar metadata does not match');
    expect(s3.deleteObject).toHaveBeenCalledWith(AVATAR_KEY);
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('rechecks expiry after S3 verification before consuming the intent', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    s3.headObject.mockImplementation(async () => {
      jest.setSystemTime(new Date(NOW.getTime() + AVATAR_UPLOAD_INTENT_TTL_MS));
      return { ContentType: 'image/jpeg', ContentLength: 1024 };
    });

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).rejects.toThrow('Avatar upload intent has expired');
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('treats a repeated confirmation as idempotent only while selected', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    prisma.avatarUploadIntent.findUnique.mockResolvedValue(
      buildIntent({ consumedAt: new Date(NOW.getTime() - 1000) }),
    );
    prisma.user.findUnique.mockResolvedValue({
      profilePicturePath: AVATAR_KEY,
      profilePictureType: 'image/jpeg',
    });

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).resolves.toEqual({
      key: AVATAR_KEY,
      contentType: 'image/jpeg',
      alreadyConfirmed: true,
    });
    expect(s3.headObject).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('does not let a consumed older intent roll the profile back', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    prisma.avatarUploadIntent.findUnique.mockResolvedValue(
      buildIntent({ consumedAt: new Date(NOW.getTime() - 1000) }),
    );
    prisma.user.findUnique.mockResolvedValue({
      profilePicturePath: PREVIOUS_AVATAR_KEY,
      profilePictureType: 'image/png',
    });

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).rejects.toMatchObject({ statusCode: 409 });
    expect(s3.headObject).not.toHaveBeenCalled();
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('does not delete an unsafe legacy previous path', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    prisma.user.findUnique.mockResolvedValue({
      profilePicturePath: '../../private/key',
      profilePictureType: 'image/jpeg',
    });

    await service.confirmUpload(USER_ID, confirmation);

    expect(s3.deleteObject).not.toHaveBeenCalled();
  });

  it('does not fail a committed confirmation when cleanup preflight fails', async () => {
    const { prisma, intent, service } = createConfirmationHarness();
    const logSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
    prisma.user.findUnique
      .mockResolvedValueOnce({ profilePicturePath: PREVIOUS_AVATAR_KEY })
      .mockRejectedValueOnce(new Error('temporary database detail'));

    await expect(
      service.confirmUpload(USER_ID, confirmation),
    ).resolves.toEqual({
      key: intent.key,
      contentType: intent.contentType,
      alreadyConfirmed: false,
    });
    expect(logSpy).toHaveBeenCalledWith(
      'Owned avatar cleanup failed',
      'Error',
    );
    expect(JSON.stringify(logSpy.mock.calls)).not.toContain(
      'temporary database detail',
    );
    logSpy.mockRestore();
  });

  it('persists failed replacement cleanup and retries it safely', async () => {
    const { prisma, s3, intent, service } = createConfirmationHarness();
    const logSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
    prisma.user.findUnique
      .mockResolvedValueOnce({ profilePicturePath: PREVIOUS_AVATAR_KEY })
      .mockResolvedValue({ profilePicturePath: intent.key });
    s3.deleteObject.mockRejectedValueOnce(new Error('temporary delete error'));

    await service.confirmUpload(USER_ID, confirmation);

    expect(s3.deleteObject).toHaveBeenCalledTimes(1);
    expect(prisma.avatarUploadIntent.updateMany).not.toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ cleanupCompletedAt: expect.any(Date) }),
      }),
    );

    prisma.avatarUploadIntent.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        buildIntent({
          consumedAt: NOW,
          cleanupKey: PREVIOUS_AVATAR_KEY,
        }),
      ]);
    s3.deleteObject.mockResolvedValue(undefined);

    await service.retryPendingCleanup(USER_ID);

    expect(s3.deleteObject).toHaveBeenCalledTimes(2);
    expect(s3.deleteObject).toHaveBeenLastCalledWith(PREVIOUS_AVATAR_KEY);
    expect(prisma.avatarUploadIntent.updateMany).toHaveBeenCalledWith({
      where: {
        id: intent.id,
        userId: USER_ID,
        cleanupKey: PREVIOUS_AVATAR_KEY,
        cleanupCompletedAt: null,
      },
      data: { cleanupCompletedAt: NOW },
    });
    expect(logSpy).toHaveBeenCalledWith(
      'Owned avatar cleanup failed',
      'Error',
    );
    logSpy.mockRestore();
  });

  it('bounds and queues abandoned expired intents for durable cleanup', async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    const expiredIntent = buildIntent({
      expiresAt: new Date(NOW.getTime() - 1000),
    });
    prisma.avatarUploadIntent.findMany.mockResolvedValueOnce([expiredIntent]);
    prisma.user.findUnique.mockResolvedValue({ profilePicturePath: null });

    await service.retryPendingCleanup(undefined, 1);

    expect(prisma.avatarUploadIntent.findMany).toHaveBeenCalledWith({
      where: {
        consumedAt: null,
        expiresAt: { lte: NOW },
      },
      orderBy: { expiresAt: 'asc' },
      take: 1,
    });
    expect(prisma.avatarUploadIntent.updateMany).toHaveBeenCalledWith({
      where: {
        id: expiredIntent.id,
        userId: USER_ID,
        key: expiredIntent.key,
        consumedAt: null,
        cleanupCompletedAt: null,
      },
      data: {
        consumedAt: NOW,
        cleanupKey: expiredIntent.key,
      },
    });
    expect(s3.deleteObject).toHaveBeenCalledWith(expiredIntent.key);
    expect(prisma.avatarUploadIntent.findMany).toHaveBeenCalledTimes(1);
  });

  it("does not delete another user's previous avatar key", async () => {
    const { prisma, s3, service } = createConfirmationHarness();
    prisma.user.findUnique.mockResolvedValue({
      profilePicturePath:
        'avatars/2/123e4567-e89b-42d3-a456-426614174001.png',
      profilePictureType: 'image/png',
    });

    await service.confirmUpload(USER_ID, confirmation);

    expect(s3.deleteObject).not.toHaveBeenCalled();
  });
});

describe('AvatarController contract', () => {
  function createResponse() {
    const response = {
      status: jest.fn(),
      json: jest.fn(),
    };
    response.status.mockReturnValue(response);
    response.json.mockReturnValue(response);
    return response;
  }

  it('returns the top-level multipart POST authorization expected by clients', async () => {
    const authorization = {
      uploadUrl: 'https://uploads.example.com',
      uploadMethod: 'POST',
      fields: { key: AVATAR_KEY, Policy: 'signed-policy' },
      key: AVATAR_KEY,
      expiresAt: '2026-07-10T10:05:00.000Z',
    };
    const avatarService = {
      requestUpload: jest.fn().mockResolvedValue(authorization),
    };
    const controller = new AvatarController(avatarService as any);
    const response = createResponse();

    await controller.getUploadUrl(
      {
        user: { id: USER_ID },
        body: {
          ext: 'jpg',
          contentType: 'image/jpeg',
          sizeBytes: 1024,
        },
      } as any,
      response as any,
    );

    expect(avatarService.requestUpload).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({
        ext: 'jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
      }),
    );
    expect(response.status).toHaveBeenCalledWith(200);
    expect(response.json).toHaveBeenCalledWith(authorization);
  });

  it('returns 400 without invoking the service for undeclared fields', async () => {
    const avatarService = { requestUpload: jest.fn() };
    const controller = new AvatarController(avatarService as any);
    const response = createResponse();

    await controller.getUploadUrl(
      {
        user: { id: USER_ID },
        body: {
          contentType: 'image/jpeg',
          sizeBytes: 1024,
          key: AVATAR_KEY,
        },
      } as any,
      response as any,
    );

    expect(response.status).toHaveBeenCalledWith(400);
    expect(response.json).toHaveBeenCalledWith({ message: 'Validation failed' });
    expect(avatarService.requestUpload).not.toHaveBeenCalled();
  });

  it('preserves typed service status codes without exposing storage errors', async () => {
    const avatarService = {
      confirmUpload: jest.fn().mockRejectedValue(
        new AvatarServiceError(
          'Avatar storage verification is temporarily unavailable',
          503,
        ),
      ),
    };
    const controller = new AvatarController(avatarService as any);
    const response = createResponse();

    await controller.confirmUpload(
      {
        user: { id: USER_ID },
        body: confirmationForController(),
      } as any,
      response as any,
    );

    expect(response.status).toHaveBeenCalledWith(503);
    expect(response.json).toHaveBeenCalledWith({
      message: 'Avatar storage verification is temporarily unavailable',
    });
  });
});

function confirmationForController() {
  return {
    key: AVATAR_KEY,
    contentType: 'image/jpeg',
  };
}
