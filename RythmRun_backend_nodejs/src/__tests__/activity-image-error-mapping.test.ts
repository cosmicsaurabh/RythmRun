import 'reflect-metadata';
import { jest } from '@jest/globals';
import type { Request, Response } from 'express';

// activity-image.service.ts instantiates the shared S3 client at module scope;
// replace it so this controller test constructs no AWS client.
jest.unstable_mockModule('../services/s3.service.js', () => ({
  S3Service: class S3Service {},
  default: {},
}));

const { ActivityImageController } = await import(
  '../controllers/activity-image.controller.js'
);
const {
  ActivityImageServiceError,
  activityNotFoundError,
  imageTooLargeError,
  invalidChecksumError,
  invalidClientImageIdError,
  invalidImageKeyError,
  unsupportedContentTypeError,
  uploadedSizeMismatchError,
} = await import('../errors/activity-image.error.js');

interface CapturedResponse {
  statusCode?: number;
  body?: unknown;
}

function fakeResponse(captured: CapturedResponse): Response {
  return {
    status(code: number) {
      captured.statusCode = code;
      return this;
    },
    json(payload: unknown) {
      captured.body = payload;
      return this;
    },
  } as unknown as Response;
}

function fakeRequest(): Request {
  return {
    params: { activityId: '5' },
    body: {},
    user: { id: 17, sessionId: 's', tokenId: 't' },
  } as unknown as Request;
}

describe('typed activity-image error mapping (IP-2.6)', () => {
  const service = {
    listImages: jest.fn(),
    requestUploadUrl: jest.fn(),
    confirmUpload: jest.fn(),
    deleteImage: jest.fn(),
  };
  const controller = new ActivityImageController(service as never);

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it.each([
    [activityNotFoundError, 404, 'ACTIVITY_IMAGE_ACTIVITY_NOT_FOUND'],
    [unsupportedContentTypeError, 400, 'ACTIVITY_IMAGE_CONTENT_TYPE_UNSUPPORTED'],
    [imageTooLargeError, 400, 'ACTIVITY_IMAGE_TOO_LARGE'],
    [invalidClientImageIdError, 400, 'ACTIVITY_IMAGE_CLIENT_ID_INVALID'],
    [invalidChecksumError, 400, 'ACTIVITY_IMAGE_CHECKSUM_INVALID'],
    [invalidImageKeyError, 400, 'ACTIVITY_IMAGE_KEY_INVALID'],
    [uploadedSizeMismatchError, 400, 'ACTIVITY_IMAGE_SIZE_MISMATCH'],
  ])('maps %p to its declared status and stable code', async (
    factory,
    statusCode,
    code,
  ) => {
    service.listImages.mockRejectedValueOnce(factory());
    const captured: CapturedResponse = {};

    await controller.listImages(fakeRequest(), fakeResponse(captured));

    expect(captured.statusCode).toBe(statusCode);
    expect(captured.body).toMatchObject({ status: 'error', code });
  });

  it('keeps the status when the message text changes', async () => {
    // The whole point of the typed error: rewording must not alter routing.
    service.listImages.mockRejectedValueOnce(
      new ActivityImageServiceError(
        'ACTIVITY_IMAGE_KEY_INVALID',
        400,
        'Completely different wording',
      ),
    );
    const captured: CapturedResponse = {};

    await controller.listImages(fakeRequest(), fakeResponse(captured));

    expect(captured.statusCode).toBe(400);
    expect(captured.body).toMatchObject({
      code: 'ACTIVITY_IMAGE_KEY_INVALID',
      message: 'Completely different wording',
    });
  });

  it('collapses an unexpected failure to a safe 500 without echoing it', async () => {
    service.listImages.mockRejectedValueOnce(
      new Error('https://bucket.example/key?X-Amz-Signature=leaked'),
    );
    const consoleError = jest.spyOn(console, 'error').mockImplementation(() => {});
    const captured: CapturedResponse = {};

    try {
      await controller.listImages(fakeRequest(), fakeResponse(captured));

      expect(captured.statusCode).toBe(500);
      expect(captured.body).toEqual({
        status: 'error',
        message: 'Internal server error',
      });
      // Neither the response nor the log may carry the presigned URL.
      expect(JSON.stringify(captured.body)).not.toContain('X-Amz-Signature');
      expect(JSON.stringify(consoleError.mock.calls)).not.toContain(
        'X-Amz-Signature',
      );
    } finally {
      consoleError.mockRestore();
    }
  });

  it('does not distinguish a missing activity from someone else\'s activity', () => {
    // Both cases share one code and one 404, so activity ids stay unenumerable.
    expect(activityNotFoundError().statusCode).toBe(404);
    expect(activityNotFoundError().code).toBe(
      'ACTIVITY_IMAGE_ACTIVITY_NOT_FOUND',
    );
  });
});
