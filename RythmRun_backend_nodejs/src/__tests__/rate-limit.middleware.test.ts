import 'reflect-metadata';
import { jest } from '@jest/globals';
import type { Request, Response } from 'express';

import {
  accountFromBody,
  authenticatedAccount,
  clientAddress,
  createRateLimiter,
  RateLimitStore,
  type RateLimitRule,
} from '../middleware/rate-limit.middleware.js';
import {
  setSecurityLogSink,
  subjectDigest,
  type SecurityLogSink,
} from '../utils/security-log.js';

const WINDOW_MS = 15 * 60 * 1000;

interface FakeResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: unknown;
  finish: () => void;
}

function fakeResponse(): Response & FakeResponse {
  const listeners: Array<() => void> = [];
  const response = {
    statusCode: 200,
    headers: {} as Record<string, string>,
    body: undefined as unknown,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    set(name: string, value: string) {
      this.headers[name] = value;
      return this;
    },
    json(payload: unknown) {
      this.body = payload;
      return this;
    },
    on(event: string, listener: () => void) {
      if (event === 'finish') {
        listeners.push(listener);
      }
      return this;
    },
    finish() {
      listeners.forEach((listener) => listener());
    },
  };

  return response as unknown as Response & FakeResponse;
}

function fakeRequest(overrides: Partial<Request> = {}): Request {
  return {
    ip: '203.0.113.10',
    socket: { remoteAddress: '203.0.113.10' },
    body: {},
    requestId: 'test-request-id',
    ...overrides,
  } as unknown as Request;
}

describe('rate limit store', () => {
  it('admits up to the limit and reports when the oldest hit ages out', () => {
    const store = new RateLimitStore();

    for (let attempt = 0; attempt < 5; attempt += 1) {
      expect(store.check('k', 1_000 + attempt, WINDOW_MS, 5).allowed).toBe(true);
      store.record('k', 1_000 + attempt, WINDOW_MS);
    }

    const decision = store.check('k', 1_005, WINDOW_MS, 5);
    expect(decision.allowed).toBe(false);
    // The first hit was at 1_000, so budget returns one window after it.
    expect(decision.retryAfterMs).toBe(1_000 + WINDOW_MS - 1_005);
  });

  it('recovers once the window has fully elapsed', () => {
    const store = new RateLimitStore();
    for (let attempt = 0; attempt < 5; attempt += 1) {
      store.record('k', 1_000, WINDOW_MS);
    }

    expect(store.check('k', 1_000 + WINDOW_MS - 1, WINDOW_MS, 5).allowed).toBe(
      false,
    );
    expect(store.check('k', 1_000 + WINDOW_MS + 1, WINDOW_MS, 5).allowed).toBe(
      true,
    );
  });

  it('keeps distinct keys independent', () => {
    const store = new RateLimitStore();
    for (let attempt = 0; attempt < 5; attempt += 1) {
      store.record('a', 1_000, WINDOW_MS);
    }

    expect(store.check('a', 1_000, WINDOW_MS, 5).allowed).toBe(false);
    expect(store.check('b', 1_000, WINDOW_MS, 5).allowed).toBe(true);
  });

  it('bounds the key space so rotating the dimension cannot exhaust memory', () => {
    const store = new RateLimitStore(10);

    for (let index = 0; index < 500; index += 1) {
      store.record(`key-${index}`, 1_000 + index, WINDOW_MS);
    }

    expect(store.size()).toBe(10);
    // The most recent keys survive; the oldest were evicted.
    expect(store.check('key-499', 1_500, WINDOW_MS, 1).allowed).toBe(false);
    expect(store.check('key-0', 1_500, WINDOW_MS, 1).allowed).toBe(true);
  });

  it('refunds exactly one hit, even when several share a millisecond', () => {
    const store = new RateLimitStore();
    for (let attempt = 0; attempt < 3; attempt += 1) {
      store.record('k', 1_000, WINDOW_MS);
    }

    expect(store.check('k', 1_000, WINDOW_MS, 3).allowed).toBe(false);
    store.refund('k', 1_000);
    expect(store.check('k', 1_000, WINDOW_MS, 3).allowed).toBe(true);
    // Only one of the three concurrent reservations was released.
    store.record('k', 1_000, WINDOW_MS);
    expect(store.check('k', 1_000, WINDOW_MS, 3).allowed).toBe(false);
  });

  it('ignores a refund for an unknown key or an already-expired hit', () => {
    const store = new RateLimitStore();
    store.record('k', 1_000, WINDOW_MS);

    expect(() => store.refund('missing', 1_000)).not.toThrow();
    expect(() => store.refund('k', 999)).not.toThrow();
    expect(store.check('k', 1_000, WINDOW_MS, 1).allowed).toBe(false);

    store.refund('k', 1_000);
    expect(store.size()).toBe(0);
  });

  it('drops a key entirely once every hit has expired', () => {
    const store = new RateLimitStore();
    store.record('k', 1_000, WINDOW_MS);

    expect(store.size()).toBe(1);
    store.check('k', 1_000 + WINDOW_MS + 1, WINDOW_MS, 5);
    expect(store.size()).toBe(0);
  });
});

describe('rate limit middleware', () => {
  const rule: RateLimitRule = {
    name: 'test',
    category: 'auth.login',
    limit: 3,
    windowMs: WINDOW_MS,
    count: 'all',
    key: (req) => clientAddress(req),
  };

  let currentTime = 10_000;
  let restoreSink: SecurityLogSink;
  const emitted: string[] = [];

  beforeEach(() => {
    currentTime = 10_000;
    emitted.length = 0;
    restoreSink = setSecurityLogSink((line) => emitted.push(line));
  });

  afterEach(() => {
    setSecurityLogSink(restoreSink);
  });

  function limiterFor(overrides: Partial<RateLimitRule> = {}) {
    return createRateLimiter(
      { ...rule, ...overrides },
      { store: new RateLimitStore(), now: () => currentTime },
    );
  }

  it('rejects the request after the budget is spent and sets Retry-After', () => {
    const limiter = limiterFor();
    const next = jest.fn();

    for (let attempt = 0; attempt < 3; attempt += 1) {
      limiter(fakeRequest(), fakeResponse(), next);
    }
    expect(next).toHaveBeenCalledTimes(3);

    const blocked = fakeResponse();
    limiter(fakeRequest(), blocked, next);

    expect(next).toHaveBeenCalledTimes(3);
    expect(blocked.statusCode).toBe(429);
    expect(blocked.headers['Retry-After']).toBe(String(WINDOW_MS / 1000));
    expect(blocked.body).toMatchObject({
      error: 'AUTH_RATE_LIMITED',
      message: 'Too many requests. Please wait and try again.',
      retryable: true,
      statusCode: 429,
    });
  });

  it('admits again once the window has passed', () => {
    const limiter = limiterFor();
    const next = jest.fn();

    for (let attempt = 0; attempt < 3; attempt += 1) {
      limiter(fakeRequest(), fakeResponse(), next);
    }
    limiter(fakeRequest(), fakeResponse(), next);
    expect(next).toHaveBeenCalledTimes(3);

    currentTime += WINDOW_MS + 1;
    limiter(fakeRequest(), fakeResponse(), next);
    expect(next).toHaveBeenCalledTimes(4);
  });

  it('does not charge rejections, so sustained abuse still recovers on time', () => {
    const limiter = limiterFor();
    const next = jest.fn();

    for (let attempt = 0; attempt < 3; attempt += 1) {
      limiter(fakeRequest(), fakeResponse(), next);
    }

    // Keep hammering right up to the edge of the window.
    for (let attempt = 0; attempt < 20; attempt += 1) {
      currentTime += 1_000;
      limiter(fakeRequest(), fakeResponse(), next);
    }
    expect(next).toHaveBeenCalledTimes(3);

    // Budget returns one window after the ORIGINAL three hits, not after the
    // most recent rejection.
    currentTime = 10_000 + WINDOW_MS + 1;
    limiter(fakeRequest(), fakeResponse(), next);
    expect(next).toHaveBeenCalledTimes(4);
  });

  it('charges only client failures when configured to do so', () => {
    const limiter = limiterFor({ count: 'client_failures' });
    const next = jest.fn();

    // Four successes cost nothing.
    for (let attempt = 0; attempt < 4; attempt += 1) {
      const response = fakeResponse();
      limiter(fakeRequest(), response, next);
      response.statusCode = 200;
      response.finish();
    }
    expect(next).toHaveBeenCalledTimes(4);

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const response = fakeResponse();
      limiter(fakeRequest(), response, next);
      response.statusCode = 401;
      response.finish();
    }
    expect(next).toHaveBeenCalledTimes(7);

    const blocked = fakeResponse();
    limiter(fakeRequest(), blocked, next);
    expect(blocked.statusCode).toBe(429);
  });

  it('does not charge the caller for a server-side failure', () => {
    const limiter = limiterFor({ count: 'client_failures' });
    const next = jest.fn();

    for (let attempt = 0; attempt < 10; attempt += 1) {
      const response = fakeResponse();
      limiter(fakeRequest(), response, next);
      response.statusCode = 503;
      response.finish();
    }

    expect(next).toHaveBeenCalledTimes(10);
  });

  it('exempts a request whose dimension is not knowable', () => {
    const limiter = limiterFor({ key: () => null });
    const next = jest.fn();

    for (let attempt = 0; attempt < 50; attempt += 1) {
      limiter(fakeRequest(), fakeResponse(), next);
    }

    expect(next).toHaveBeenCalledTimes(50);
  });

  it('logs a rejection without the address, account, or key in clear text', () => {
    const limiter = limiterFor({
      key: (req) => `${accountFromBody(req, 'username')}|${clientAddress(req)}`,
    });
    const next = jest.fn();
    const request = () =>
      fakeRequest({
        body: { username: 'Runner@Example.com' },
      } as Partial<Request>);

    for (let attempt = 0; attempt < 3; attempt += 1) {
      limiter(request(), fakeResponse(), next);
    }
    limiter(request(), fakeResponse(), next);

    expect(emitted).toHaveLength(1);
    const record = JSON.parse(emitted[0]) as Record<string, unknown>;
    expect(record).toMatchObject({
      type: 'security_event',
      category: 'auth.login',
      outcome: 'rate_limited',
      requestId: 'test-request-id',
    });
    expect(record.subjectDigest).toBe(
      subjectDigest('test:runner@example.com|203.0.113.10'),
    );
    expect(emitted[0]).not.toContain('runner@example.com');
    expect(emitted[0]).not.toContain('Runner@Example.com');
    expect(emitted[0]).not.toContain('203.0.113.10');
  });
});

describe('rate limit key dimensions', () => {
  it('canonicalises the account so casing and padding cannot buy a new budget', () => {
    const request = fakeRequest({
      body: { username: '  Runner@Example.COM ' },
    } as Partial<Request>);

    expect(accountFromBody(request, 'username')).toBe('runner@example.com');
  });

  it('returns an empty account component when the field is absent or not a string', () => {
    expect(accountFromBody(fakeRequest(), 'username')).toBe('');
    expect(
      accountFromBody(
        fakeRequest({ body: { username: 42 } } as Partial<Request>),
        'username',
      ),
    ).toBe('');
  });

  it('digests an over-long account so one request cannot bloat the key space', () => {
    const long = `${'a'.repeat(400)}@example.com`;
    const derived = accountFromBody(
      fakeRequest({ body: { username: long } } as Partial<Request>),
      'username',
    );

    expect(derived).toBe(subjectDigest(long.toLowerCase()));
    expect(derived.length).toBeLessThan(20);
  });

  it('normalises an IPv4-mapped IPv6 address to one budget', () => {
    expect(
      clientAddress(fakeRequest({ ip: '::ffff:203.0.113.10' } as Partial<Request>)),
    ).toBe('203.0.113.10');
  });

  it('falls back to the socket address when express reports no ip', () => {
    expect(
      clientAddress(
        fakeRequest({
          ip: undefined,
          socket: { remoteAddress: '198.51.100.7' },
        } as unknown as Partial<Request>),
      ),
    ).toBe('198.51.100.7');
  });

  it('exempts an unauthenticated request from an account-keyed rule', () => {
    expect(authenticatedAccount(fakeRequest())).toBeNull();
    expect(
      authenticatedAccount(
        fakeRequest({
          user: { id: 17, sessionId: 's', tokenId: 't' },
        } as Partial<Request>),
      ),
    ).toBe('17');
  });
});
