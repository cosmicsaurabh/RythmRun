import express, { Router } from 'express';
import type {
  NextFunction,
  Request,
  RequestHandler,
  Response,
} from 'express';
import { container } from '../config/container.js';
import { ActivityController } from '../controllers/activity.controller.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export const ACTIVITY_JSON_LIMIT_BYTES = 3 * 1024 * 1024;
export const ACTIVITY_GLOBAL_CONCURRENCY_LIMIT = 4;
export const ACTIVITY_USER_CONCURRENCY_LIMIT = 1;

export const ACTIVITY_BOUNDARY_ERROR_CODES = {
  busy: 'ACTIVITY_REQUEST_BUSY',
  invalidJson: 'ACTIVITY_PAYLOAD_INVALID_JSON',
  tooLarge: 'ACTIVITY_PAYLOAD_TOO_LARGE',
} as const;

export interface ActivityRouteController {
  listActivities: RequestHandler;
  getActivity: RequestHandler;
  createActivity: RequestHandler;
  updateActivity: RequestHandler;
  deleteActivity: RequestHandler;
}

export interface ActivityMutationBoundary {
  admit: RequestHandler;
  rejectOversizedContentLength: RequestHandler;
  parseJson: RequestHandler;
}

export interface ActivityMutationBoundaryOptions {
  bodyLimitBytes?: number;
  globalConcurrencyLimit?: number;
  userConcurrencyLimit?: number;
}

export interface ActivityRouterDependencies {
  controller: ActivityRouteController;
  authenticate: RequestHandler;
  mutationBoundary?: ActivityMutationBoundary;
}

type BodyParserError = Error & {
  status?: number;
  type?: string;
};

function requirePositiveInteger(value: number, name: string): number {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new RangeError(`${name} must be a positive safe integer`);
  }

  return value;
}

function sendBoundaryError(
  res: Response,
  statusCode: number,
  code: string,
  message: string,
  retryable = false,
) {
  return res.status(statusCode).json({
    status: 'error',
    code,
    message,
    retryable,
  });
}

function isBodyParserError(error: unknown): error is BodyParserError {
  return error instanceof Error && (
    'status' in error ||
    'type' in error
  );
}

/**
 * Bounds the number of fully admitted activity mutations held in this Node
 * process. It deliberately rejects instead of queueing so request bodies are
 * not buffered while waiting for a slot. Cross-process rate limiting remains
 * a deployment boundary concern.
 */
export function createActivityAdmissionGuard({
  globalConcurrencyLimit = ACTIVITY_GLOBAL_CONCURRENCY_LIMIT,
  userConcurrencyLimit = ACTIVITY_USER_CONCURRENCY_LIMIT,
}: Pick<
  ActivityMutationBoundaryOptions,
  'globalConcurrencyLimit' | 'userConcurrencyLimit'
> = {}): RequestHandler {
  const maxGlobal = requirePositiveInteger(
    globalConcurrencyLimit,
    'globalConcurrencyLimit',
  );
  const maxPerUser = requirePositiveInteger(
    userConcurrencyLimit,
    'userConcurrencyLimit',
  );
  const activeByUser = new Map<number, number>();
  let activeGlobal = 0;

  return (req: Request, res: Response, next: NextFunction) => {
    const userId = req.user?.id;
    if (typeof userId !== 'number' || !Number.isSafeInteger(userId)) {
      return sendBoundaryError(
        res,
        401,
        'AUTHENTICATION_REQUIRED',
        'Authentication is required',
      );
    }

    const activeForUser = activeByUser.get(userId) ?? 0;
    if (activeGlobal >= maxGlobal || activeForUser >= maxPerUser) {
      res.setHeader('Retry-After', '1');
      return sendBoundaryError(
        res,
        429,
        ACTIVITY_BOUNDARY_ERROR_CODES.busy,
        'Another activity request is already in progress',
        true,
      );
    }

    activeGlobal += 1;
    activeByUser.set(userId, activeForUser + 1);

    let released = false;
    const release = () => {
      if (released) {
        return;
      }

      released = true;
      activeGlobal -= 1;
      const remainingForUser = (activeByUser.get(userId) ?? 1) - 1;
      if (remainingForUser > 0) {
        activeByUser.set(userId, remainingForUser);
      } else {
        activeByUser.delete(userId);
      }
    };

    res.once('finish', release);
    res.once('close', release);

    try {
      next();
    } catch (error) {
      release();
      throw error;
    }
  };
}

export function createActivityContentLengthGuard(
  bodyLimitBytes = ACTIVITY_JSON_LIMIT_BYTES,
): RequestHandler {
  const maxBytes = requirePositiveInteger(bodyLimitBytes, 'bodyLimitBytes');
  const maxBytesAsBigInt = BigInt(maxBytes);

  return (req: Request, res: Response, next: NextFunction) => {
    const contentLength = req.headers['content-length'];

    // Node rejects malformed/conflicting Content-Length headers before this
    // middleware. The JSON parser remains authoritative when this header is
    // missing, compressed, or otherwise cannot be used as an early bound.
    if (contentLength && /^\d+$/.test(contentLength)) {
      if (BigInt(contentLength) > maxBytesAsBigInt) {
        return sendBoundaryError(
          res,
          413,
          ACTIVITY_BOUNDARY_ERROR_CODES.tooLarge,
          'Activity payload exceeds the 3 MiB limit',
        );
      }
    }

    next();
  };
}

export function createActivityJsonParser(
  bodyLimitBytes = ACTIVITY_JSON_LIMIT_BYTES,
): RequestHandler {
  const maxBytes = requirePositiveInteger(bodyLimitBytes, 'bodyLimitBytes');
  const parseJson = express.json({ limit: maxBytes });

  return (req: Request, res: Response, next: NextFunction) => {
    parseJson(req, res, (error?: unknown) => {
      if (error === undefined) {
        next();
        return;
      }

      if (isBodyParserError(error) && (
        error.status === 413 ||
        error.type === 'entity.too.large'
      )) {
        sendBoundaryError(
          res,
          413,
          ACTIVITY_BOUNDARY_ERROR_CODES.tooLarge,
          'Activity payload exceeds the 3 MiB limit',
        );
        return;
      }

      if (isBodyParserError(error) && (
        error.status === 400 ||
        error.type === 'entity.parse.failed'
      )) {
        sendBoundaryError(
          res,
          400,
          ACTIVITY_BOUNDARY_ERROR_CODES.invalidJson,
          'Activity payload is not valid JSON',
        );
        return;
      }

      next(error);
    });
  };
}

export function createActivityMutationBoundary({
  bodyLimitBytes = ACTIVITY_JSON_LIMIT_BYTES,
  globalConcurrencyLimit = ACTIVITY_GLOBAL_CONCURRENCY_LIMIT,
  userConcurrencyLimit = ACTIVITY_USER_CONCURRENCY_LIMIT,
}: ActivityMutationBoundaryOptions = {}): ActivityMutationBoundary {
  return {
    admit: createActivityAdmissionGuard({
      globalConcurrencyLimit,
      userConcurrencyLimit,
    }),
    rejectOversizedContentLength:
      createActivityContentLengthGuard(bodyLimitBytes),
    parseJson: createActivityJsonParser(bodyLimitBytes),
  };
}

/** Builds an activity router from injectable HTTP-boundary dependencies. */
export function createActivityRouter({
  controller,
  authenticate,
  mutationBoundary = createActivityMutationBoundary(),
}: ActivityRouterDependencies): Router {
  const router = Router();

  router.get('/', authenticate, controller.listActivities);
  router.get('/:activityId', authenticate, controller.getActivity);

  router.post(
    '/',
    authenticate,
    mutationBoundary.admit,
    mutationBoundary.rejectOversizedContentLength,
    mutationBoundary.parseJson,
    controller.createActivity,
  );

  router.patch(
    '/:activityId',
    authenticate,
    mutationBoundary.admit,
    mutationBoundary.rejectOversizedContentLength,
    mutationBoundary.parseJson,
    controller.updateActivity,
  );

  router.delete('/:activityId', authenticate, controller.deleteActivity);

  return router;
}

const router = createActivityRouter({
  controller: container.resolve(ActivityController),
  authenticate: authMiddleware,
});

export default router;
