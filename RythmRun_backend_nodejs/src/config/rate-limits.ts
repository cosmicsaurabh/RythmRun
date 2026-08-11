import type { RequestHandler } from 'express';

import {
  accountFromBody,
  authenticatedAccount,
  clientAddress,
  createRateLimiter,
  RateLimitStore,
  type RateLimiterDependencies,
  type RateLimitRule,
} from '../middleware/rate-limit.middleware.js';

const MINUTE_MS = 60 * 1000;
const FIFTEEN_MINUTES_MS = 15 * MINUTE_MS;
const HOUR_MS = 60 * MINUTE_MS;

/**
 * The configured budgets for the authentication and recovery surface
 * (IP-2.6 item 2). Exported so the tests assert the shipped numbers rather
 * than a copy of them.
 *
 * A public endpoint that names an account is keyed by account *and* client
 * address, which bounds password guessing against one account. That composite
 * key on its own does NOT bound the opposite attack: one password sprayed
 * across many accounts mints a fresh key every request and would never trip.
 * `loginAddress` is the second, broader ceiling that closes it — an addition
 * beyond the four budgets the plan enumerates, not one of them. Authenticated
 * endpoints are keyed by user id, which is already proven and cannot be
 * rotated.
 */
export const AUTH_RATE_LIMITS = {
  login: { limit: 5, windowMs: FIFTEEN_MINUTES_MS },
  loginAddress: { limit: 20, windowMs: FIFTEEN_MINUTES_MS },
  register: { limit: 5, windowMs: HOUR_MS },
  googleExchange: { limit: 10, windowMs: FIFTEEN_MINUTES_MS },
  passwordResetRequest: { limit: 3, windowMs: HOUR_MS },
  passwordResetSubmit: { limit: 10, windowMs: HOUR_MS },
  passwordChange: { limit: 5, windowMs: HOUR_MS },
  verificationResend: { limit: 5, windowMs: HOUR_MS },
  accountDeletion: { limit: 5, windowMs: HOUR_MS },
} as const;

export const AUTH_RATE_LIMIT_RULES: readonly RateLimitRule[] = [
  {
    name: 'login',
    category: 'auth.login',
    ...AUTH_RATE_LIMITS.login,
    // Only failed attempts are charged, so a user signing in correctly on a
    // shared address is never locked out by their own successful traffic.
    count: 'client_failures',
    key: (req) => `${accountFromBody(req, 'username')}|${clientAddress(req)}`,
  },
  {
    name: 'login-address',
    category: 'auth.login',
    ...AUTH_RATE_LIMITS.loginAddress,
    // Deliberately address-only and deliberately looser than the per-account
    // budget. It exists so credential spraying — one password, many accounts —
    // cannot walk past the composite key by never reusing an account.
    count: 'client_failures',
    key: (req) => clientAddress(req),
  },
  {
    name: 'register',
    category: 'auth.register',
    ...AUTH_RATE_LIMITS.register,
    count: 'all',
    key: (req) => clientAddress(req),
  },
  {
    name: 'google-exchange',
    category: 'auth.google_exchange',
    ...AUTH_RATE_LIMITS.googleExchange,
    // The account is unknown until Google verifies the token, so address is
    // the only dimension available. Charging only 4xx keeps a Google outage
    // (mapped to a retryable 503) from consuming a legitimate user's budget.
    count: 'client_failures',
    key: (req) => clientAddress(req),
  },
  {
    name: 'password-reset-request',
    category: 'auth.password_reset_request',
    ...AUTH_RATE_LIMITS.passwordResetRequest,
    // Every request is charged, not just failures: the endpoint answers
    // generically by design, so "failure" is not observable here, and the
    // thing being capped is outbound mail to a possibly unwilling recipient.
    count: 'all',
    key: (req) => `${accountFromBody(req, 'username')}|${clientAddress(req)}`,
  },
  {
    name: 'password-reset-submit',
    category: 'auth.password_reset_submit',
    ...AUTH_RATE_LIMITS.passwordResetSubmit,
    // Bounds token guessing against the public web form. The token itself is
    // never used as a key — that would put a secret in the limiter's memory.
    count: 'all',
    key: (req) => clientAddress(req),
  },
  {
    name: 'password-change',
    category: 'auth.password_change',
    ...AUTH_RATE_LIMITS.passwordChange,
    count: 'all',
    key: authenticatedAccount,
  },
  {
    name: 'verification-resend',
    category: 'auth.verification_resend',
    ...AUTH_RATE_LIMITS.verificationResend,
    // Caps outbound mail per account on top of the service's own 60s cooldown.
    count: 'all',
    key: authenticatedAccount,
  },
  {
    name: 'account-deletion',
    category: 'auth.account_deletion',
    ...AUTH_RATE_LIMITS.accountDeletion,
    // Deletion re-authenticates (password or Google token). Charging every
    // attempt, keyed by the proven user id, bounds re-auth guessing on a
    // destructive endpoint — same shape as password-change.
    count: 'all',
    key: authenticatedAccount,
  },
];

export interface AuthRateLimiters {
  login: RequestHandler;
  loginAddress: RequestHandler;
  register: RequestHandler;
  googleExchange: RequestHandler;
  passwordResetRequest: RequestHandler;
  passwordResetSubmit: RequestHandler;
  passwordChange: RequestHandler;
  verificationResend: RequestHandler;
  accountDeletion: RequestHandler;
}

const RULE_BY_NAME = new Map(AUTH_RATE_LIMIT_RULES.map((rule) => [rule.name, rule]));

function limiter(
  name: string,
  dependencies: RateLimiterDependencies,
): RequestHandler {
  const rule = RULE_BY_NAME.get(name);
  if (rule === undefined) {
    throw new Error(`Unknown rate limit rule: ${name}`);
  }
  return createRateLimiter(rule, dependencies);
}

/**
 * Builds one limiter per protected endpoint. Every rule shares a single store
 * so the process holds one bounded key space rather than one per rule; keys
 * are already namespaced by rule name, so the buckets stay independent.
 */
export function createAuthRateLimiters(
  dependencies: RateLimiterDependencies = {},
): AuthRateLimiters {
  const shared: RateLimiterDependencies = {
    store: dependencies.store ?? new RateLimitStore(),
    now: dependencies.now,
  };

  return {
    login: limiter('login', shared),
    loginAddress: limiter('login-address', shared),
    register: limiter('register', shared),
    googleExchange: limiter('google-exchange', shared),
    passwordResetRequest: limiter('password-reset-request', shared),
    passwordResetSubmit: limiter('password-reset-submit', shared),
    passwordChange: limiter('password-change', shared),
    verificationResend: limiter('verification-resend', shared),
    accountDeletion: limiter('account-deletion', shared),
  };
}

/** Every request passes; used by tests that are not exercising the budgets. */
export function createPassthroughRateLimiters(): AuthRateLimiters {
  const passthrough: RequestHandler = (_req, _res, next) => next();
  return {
    login: passthrough,
    loginAddress: passthrough,
    register: passthrough,
    googleExchange: passthrough,
    passwordResetRequest: passthrough,
    passwordResetSubmit: passthrough,
    passwordChange: passthrough,
    verificationResend: passthrough,
    accountDeletion: passthrough,
  };
}
