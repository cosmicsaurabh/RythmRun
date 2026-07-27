import { randomUUID } from 'node:crypto';
import type { RequestHandler } from 'express';

export const REQUEST_ID_HEADER = 'X-Request-Id';

/**
 * Assigns a server-minted correlation id to every request and echoes it back
 * (IP-2.6 item 5).
 *
 * An inbound `X-Request-Id` is deliberately ignored rather than reused: a
 * client that picks its own id could collide with, or forge, another
 * request's log trail, and the header is an unvalidated string that would end
 * up written into logs verbatim.
 */
export const requestContextMiddleware: RequestHandler = (req, res, next) => {
  const requestId = randomUUID();
  req.requestId = requestId;
  res.setHeader(REQUEST_ID_HEADER, requestId);
  next();
};
