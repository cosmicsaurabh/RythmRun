/**
 * Typed activity-image failures (IP-2.6 item 4).
 *
 * Before this existed the controller decided an HTTP status by comparing
 * `error.message` against a list of exact English sentences. Any reworded
 * message silently became a 500, and any new failure defaulted to 500 as well,
 * so the mapping was both fragile and invisible when it broke. The status and
 * the stable code now travel with the error itself.
 */
export type ActivityImageErrorCode =
  | 'ACTIVITY_IMAGE_ACTIVITY_NOT_FOUND'
  | 'ACTIVITY_IMAGE_CHECKSUM_INVALID'
  | 'ACTIVITY_IMAGE_CLIENT_ID_INVALID'
  | 'ACTIVITY_IMAGE_CONTENT_TYPE_UNSUPPORTED'
  | 'ACTIVITY_IMAGE_KEY_INVALID'
  | 'ACTIVITY_IMAGE_SIZE_MISMATCH'
  | 'ACTIVITY_IMAGE_TOO_LARGE'
  | 'ACTIVITY_IMAGE_ACTIVITY_LIMIT_EXCEEDED'
  | 'ACTIVITY_IMAGE_USER_QUOTA_EXCEEDED'
  | 'ACTIVITY_IMAGE_TOO_MANY_PENDING';

export class ActivityImageServiceError extends Error {
  constructor(
    readonly code: ActivityImageErrorCode,
    readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = 'ActivityImageServiceError';
    Object.setPrototypeOf(this, ActivityImageServiceError.prototype);
  }
}

/**
 * Deliberately 404 for both "no such activity" and "not yours": distinguishing
 * them would let a caller enumerate other users' activity ids.
 */
export function activityNotFoundError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_ACTIVITY_NOT_FOUND',
    404,
    'Activity not found or unauthorized',
  );
}

export function unsupportedContentTypeError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_CONTENT_TYPE_UNSUPPORTED',
    400,
    'Unsupported image content type',
  );
}

export function imageTooLargeError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_TOO_LARGE',
    400,
    'Image file too large',
  );
}

export function invalidClientImageIdError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_CLIENT_ID_INVALID',
    400,
    'Invalid client image ID',
  );
}

export function invalidChecksumError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_CHECKSUM_INVALID',
    400,
    'Invalid checksum',
  );
}

export function invalidImageKeyError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_KEY_INVALID',
    400,
    'Invalid image key',
  );
}

export function uploadedSizeMismatchError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_SIZE_MISMATCH',
    400,
    'Uploaded image size mismatch',
  );
}

export function activityImageLimitExceededError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_ACTIVITY_LIMIT_EXCEEDED',
    400,
    'Activity image limit reached',
  );
}

export function userImageQuotaExceededError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_USER_QUOTA_EXCEEDED',
    400,
    'User activity image quota exceeded',
  );
}

export function tooManyPendingUploadsError(): ActivityImageServiceError {
  return new ActivityImageServiceError(
    'ACTIVITY_IMAGE_TOO_MANY_PENDING',
    429,
    'Too many pending image uploads',
  );
}

