import { jest } from '@jest/globals';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { S3Service } from '../services/s3.service.js';

const AVATAR_KEY =
  'avatars/1/123e4567-e89b-42d3-a456-426614174000.jpg';
const ACTIVITY_IMAGE_KEY = 'activity-images/1/2/img_client_123456.jpg';
const REQUIRED_ENVIRONMENT = [
  'R2_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET_AVATARS',
  'R2_BUCKET_ACTIVITY_IMAGES',
] as const;
const originalEnvironment = Object.fromEntries(
  REQUIRED_ENVIRONMENT.map(name => [name, process.env[name]]),
) as Record<(typeof REQUIRED_ENVIRONMENT)[number], string | undefined>;

describe('S3Service AWS SDK v3 adapter', () => {
  const send = jest.fn();
  const presignS3Request = jest.fn();
  const s3Client = { send } as unknown as S3Client;

  function createService() {
    return new S3Service({
      s3Client,
      presignS3Request,
    });
  }

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.R2_ACCOUNT_ID = 'test-account-id';
    process.env.R2_ACCESS_KEY_ID = 'test-access-key';
    process.env.R2_SECRET_ACCESS_KEY = 'test-secret-key';
    process.env.R2_BUCKET_AVATARS = 'test-avatars-bucket';
    process.env.R2_BUCKET_ACTIVITY_IMAGES = 'test-activity-images-bucket';
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  afterAll(() => {
    for (const name of REQUIRED_ENVIRONMENT) {
      const originalValue = originalEnvironment[name];
      if (originalValue === undefined) {
        delete process.env[name];
      } else {
        process.env[name] = originalValue;
      }
    }
  });

  it('presigns a PutObjectCommand with the requested content type and expiry', async () => {
    presignS3Request.mockResolvedValue(
      'https://storage-test-bucket.s3.example.com/upload',
    );
    const service = createService();

    const result = await service.getPresignedPutUrl({
      key: ACTIVITY_IMAGE_KEY,
      contentType: 'image/jpeg',
      expiresSeconds: 120,
    });

    expect(presignS3Request).toHaveBeenCalledTimes(1);
    const [client, command, options] = presignS3Request.mock.calls[0];
    expect(client).toBe(s3Client);
    expect(command).toBeInstanceOf(PutObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'test-activity-images-bucket',
      Key: ACTIVITY_IMAGE_KEY,
      ContentType: 'image/jpeg',
      ContentLength: undefined,
    });
    expect(options).toEqual({
      expiresIn: 120,
      signableHeaders: new Set(['content-type']),
    });
    expect(result).toEqual({
      uploadUrl: 'https://storage-test-bucket.s3.example.com/upload',
      key: ACTIVITY_IMAGE_KEY,
    });
  });

  it('presigns avatar PUTs against the avatar bucket', async () => {
    presignS3Request.mockResolvedValue(
      'https://test-avatars-bucket.test-account-id.r2.cloudflarestorage.com/upload',
    );
    const service = createService();

    const result = await service.getPresignedAvatarPutUrl({
      key: AVATAR_KEY,
      contentType: 'image/jpeg',
      sizeBytes: 1024,
      expiresSeconds: 300,
    });

    expect(presignS3Request).toHaveBeenCalledTimes(1);
    const [client, command, options] = presignS3Request.mock.calls[0];
    expect(client).toBe(s3Client);
    expect(command).toBeInstanceOf(PutObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'test-avatars-bucket',
      Key: AVATAR_KEY,
      ContentType: 'image/jpeg',
      ContentLength: 1024,
    });
    expect(options).toEqual({
      expiresIn: 300,
      signableHeaders: new Set(['content-type', 'content-length']),
    });
    expect(result).toEqual({
      uploadUrl:
        'https://test-avatars-bucket.test-account-id.r2.cloudflarestorage.com/upload',
      key: AVATAR_KEY,
    });
  });

  it('does not bind an empty-body checksum to a real presigned PUT URL', async () => {
    const service = new S3Service();

    const result = await service.getPresignedPutUrl({
      key: ACTIVITY_IMAGE_KEY,
      contentType: 'image/jpeg',
      expiresSeconds: 120,
    });

    const query = new URL(result.uploadUrl).searchParams;
    expect(query.has('x-amz-checksum-crc32')).toBe(false);
    expect(query.has('x-amz-sdk-checksum-algorithm')).toBe(false);
    expect(query.get('X-Amz-SignedHeaders')?.split(';')).toContain(
      'content-type',
    );
  });

  it('binds avatar content type and exact length in a real presigned PUT URL', async () => {
    const service = new S3Service();

    const result = await service.getPresignedAvatarPutUrl({
      key: AVATAR_KEY,
      contentType: 'image/jpeg',
      sizeBytes: 1024,
      expiresSeconds: 300,
    });

    const query = new URL(result.uploadUrl).searchParams;
    expect(query.get('X-Amz-SignedHeaders')?.split(';')).toEqual(
      expect.arrayContaining(['content-length', 'content-type']),
    );
    expect(query.has('x-amz-checksum-crc32')).toBe(false);
    expect(query.has('x-amz-sdk-checksum-algorithm')).toBe(false);
  });

  it('dispatches HeadObjectCommand and returns its metadata', async () => {
    const metadata = {
      ContentType: 'image/jpeg',
      ContentLength: 1024,
      $metadata: { httpStatusCode: 200 },
    };
    send.mockResolvedValue(metadata);
    const service = createService();

    await expect(
      service.headObject(AVATAR_KEY, 'R2_BUCKET_AVATARS'),
    ).resolves.toBe(metadata);

    expect(send).toHaveBeenCalledTimes(1);
    const command = send.mock.calls[0][0];
    expect(command).toBeInstanceOf(HeadObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'test-avatars-bucket',
      Key: AVATAR_KEY,
    });
  });

  it('dispatches DeleteObjectCommand and keeps the void result contract', async () => {
    send.mockResolvedValue({ $metadata: { httpStatusCode: 204 } });
    const service = createService();

    await expect(
      service.deleteObject(AVATAR_KEY, 'R2_BUCKET_AVATARS'),
    ).resolves.toBeUndefined();

    expect(send).toHaveBeenCalledTimes(1);
    const command = send.mock.calls[0][0];
    expect(command).toBeInstanceOf(DeleteObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'test-avatars-bucket',
      Key: AVATAR_KEY,
    });
  });

  it('generates R2 presigned GET URLs with expiry for activity images', async () => {
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-07-10T10:00:00.123Z').getTime());
    presignS3Request.mockResolvedValue(
      `https://test-account-id.r2.cloudflarestorage.com/${ACTIVITY_IMAGE_KEY}?X-Amz-Signature=signed`,
    );
    const service = createService();

    const result = await service.getActivityImageReadUrl(ACTIVITY_IMAGE_KEY, 900);

    expect(presignS3Request).toHaveBeenCalledTimes(1);
    const [client, command, options] = presignS3Request.mock.calls[0];
    expect(client).toBe(s3Client);
    expect(command).toBeInstanceOf(GetObjectCommand);
    expect(command.input.Bucket).toBe('test-activity-images-bucket');
    expect(command.input.Key).toBe(ACTIVITY_IMAGE_KEY);
    expect(options).toEqual({ expiresIn: 900 });
    expect(result).toEqual({
      url: `https://test-account-id.r2.cloudflarestorage.com/${ACTIVITY_IMAGE_KEY}?X-Amz-Signature=signed`,
      urlExpiresAt: '2026-07-10T10:15:00.123Z',
    });
  });

  it('generates avatar read URLs from the avatar bucket', async () => {
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-07-10T10:00:00.123Z').getTime());
    presignS3Request.mockResolvedValue(
      `https://test-avatars-bucket.test-account-id.r2.cloudflarestorage.com/${AVATAR_KEY}?X-Amz-Signature=signed`,
    );
    const service = createService();

    const result = await service.getAvatarReadUrl(AVATAR_KEY, 900);

    expect(presignS3Request).toHaveBeenCalledTimes(1);
    const [client, command, options] = presignS3Request.mock.calls[0];
    expect(client).toBe(s3Client);
    expect(command).toBeInstanceOf(GetObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'test-avatars-bucket',
      Key: AVATAR_KEY,
    });
    expect(options).toEqual({ expiresIn: 900 });
    expect(result).toEqual({
      url: `https://test-avatars-bucket.test-account-id.r2.cloudflarestorage.com/${AVATAR_KEY}?X-Amz-Signature=signed`,
      urlExpiresAt: '2026-07-10T10:15:00.123Z',
    });
  });
});
