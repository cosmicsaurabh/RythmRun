import type { Request, RequestHandler } from 'express';

import { rateLimitedError } from '../errors/auth.error.js';
import {
  logSecurityEvent,
  subjectDigest,
  type SecurityEventCategory,
} from '../utils/security-log.js';

/**
 * In-process request budgets for the authentication and account-recovery
 * surface (IP-2.6 items 2, 3, and 9).
 *
 * Topology contract: counters live in this process's heap only. They are
 * therefore lost on restart or redeploy — an attacker who can force a restart
 * regains a full budget — and they are NOT shared between replicas, so N
 * replicas multiply every limit by N. This is acceptable only while the
 * backend runs a single replica, which is the current deployment. Before a
 * second replica or an autoscaler is introduced, these budgets must move to a
 * shared store (or the edge), otherwise they silently stop being limits.
 *
 * Restart behaviour is fail-open by construction: losing the counters admits
 * traffic rather than denying it. That is the correct trade for a login
 * endpoint — a limiter that failed closed on restart would lock every user out
 * of a healthy deployment — but it is the reason these limits are a
 * defence-in-depth layer and never the primary control. Authentication,
 * anti-enumeration, and the single-use token rules remain mandatory.
 */

/** Bounds heap growth from an attacker who rotates the key dimension. */
export const MAX_TRACKED_KEYS = 20_000;

/** Longest identifying value folded into a key; longer values are digested. */
const MAX_KEY_COMPONENT_LENGTH = 320;

export interface RateLimitRule {
  /** Security-event category recorded when this rule rejects a request. */
  readonly category: SecurityEventCategory;
  /** Distinct namespace so two rules never share a bucket. */
  readonly name: string;
  readonly limit: number;
  readonly windowMs: number;
  /**
   * Derives the bucket key from the request, or null to exempt the request
   * entirely (for example when the dimension is not knowable yet).
   */
  readonly key: (req: Request) => string | null;
  /**
   * `all` keeps every admitted request charged. `client_failures` refunds the
   * charge unless the response was a 4xx, so a correct sign-in is never
   * limited by its own success and a 5xx outage does not consume the caller's
   * budget for a fault that is ours.
   *
   * Both modes charge on the way in; only the refund is deferred. Deciding
   * whether to charge at response time instead would leave a concurrency hole,
   * because overlapping requests would all read an uncharged bucket.
   */
  readonly count: 'all' | 'client_failures';
}

export interface RateLimitDecision {
  readonly allowed: boolean;
  readonly retryAfterMs: number;
}

/**
 * Sliding-window counter keyed by an opaque string. Timestamps older than the
 * window are pruned on access, so a key that stops being used costs nothing
 * beyond its map entry, and the map itself is LRU-bounded.
 */
export class RateLimitStore {
  private readonly hits = new Map<string, number[]>();

  constructor(private readonly maxKeys: number = MAX_TRACKED_KEYS) {}

  check(
    key: string,
    now: number,
    windowMs: number,
    limit: number,
  ): RateLimitDecision {
    const recent = this.prune(key, now, windowMs);
    if (recent.length < limit) {
      return { allowed: true, retryAfterMs: 0 };
    }

    // The oldest hit still inside the window is the one that must age out
    // before this key regains budget.
    const oldest = recent[recent.length - limit];
    return {
      allowed: false,
      retryAfterMs: Math.max(0, oldest + windowMs - now),
    };
  }

  record(key: string, now: number, windowMs: number): void {
    const recent = this.prune(key, now, windowMs);
    recent.push(now);
    this.touch(key, recent);
  }

  /**
   * Releases one hit previously charged at `timestamp`. Used to give back a
   * reservation once the response turns out not to be chargeable. Removing a
   * single occurrence matters: several concurrent requests can share a
   * millisecond, and each owns exactly one of those entries.
   */
  refund(key: string, timestamp: number): void {
    const existing = this.hits.get(key);
    if (existing === undefined) {
      return;
    }

    const index = existing.indexOf(timestamp);
    if (index === -1) {
      // Already pruned by its window expiring; nothing is owed.
      return;
    }

    existing.splice(index, 1);
    if (existing.length === 0) {
      this.hits.delete(key);
    }
  }

  /** Test/inspection helper. */
  size(): number {
    return this.hits.size;
  }

  private prune(key: string, now: number, windowMs: number): number[] {
    const existing = this.hits.get(key);
    if (existing === undefined) {
      return [];
    }

    const threshold = now - windowMs;
    // Timestamps are appended in order, so the survivors are always a suffix.
    let firstLive = 0;
    while (firstLive < existing.length && existing[firstLive] <= threshold) {
      firstLive += 1;
    }

    if (firstLive === 0) {
      return existing;
    }

    const recent = existing.slice(firstLive);
    if (recent.length === 0) {
      this.hits.delete(key);
      return [];
    }

    this.hits.set(key, recent);
    return recent;
  }

  private touch(key: string, recent: number[]): void {
    // Re-insertion moves the key to the end of the Map's iteration order,
    // which makes the first key the least recently written one.
    this.hits.delete(key);
    this.hits.set(key, recent);

    while (this.hits.size > this.maxKeys) {
      const oldest = this.hits.keys().next();
      if (oldest.done === true) {
        break;
      }
      this.hits.delete(oldest.value);
    }
  }
}

export interface RateLimiterDependencies {
  store?: RateLimitStore;
  now?: () => number;
}

function bounded(value: string): string {
  return value.length <= MAX_KEY_COMPONENT_LENGTH
    ? value
    : subjectDigest(value);
}

/**
 * The address the limiter charges. `req.ip` honours `X-Forwarded-For` only as
 * far as the configured `trust proxy` hop count allows, so with the default of
 * 0 a forged forwarding header is ignored entirely and the socket address is
 * used. Setting TRUST_PROXY_HOPS higher than the real proxy depth would let a
 * client choose its own key and escape every address-keyed limit.
 */
export function clientAddress(req: Request): string {
  const address = req.ip ?? req.socket.remoteAddress ?? 'unknown';
  // Normalise IPv4-mapped IPv6 so the same client cannot hold two budgets.
  return address.startsWith('::ffff:') ? address.slice('::ffff:'.length) : address;
}

/**
 * Account dimension for a public endpoint, read from the request body before
 * validation. It is canonicalised the same way the DTOs canonicalise a
 * username so casing or padding cannot buy a fresh budget. A missing or
 * non-string value yields an empty component, which still leaves the request
 * bounded by its address component.
 */
export function accountFromBody(req: Request, field: string): string {
  const raw = (req.body as Record<string, unknown> | undefined)?.[field];
  if (typeof raw !== 'string') {
    return '';
  }
  return bounded(raw.trim().toLowerCase());
}

export function authenticatedAccount(req: Request): string | null {
  const id = req.user?.id;
  return id === undefined ? null : String(id);
}

/**
 * Whether a finished response should keep its reservation under a
 * `client_failures` rule.
 *
 * 4xx is the caller's fault and is charged — except 429, which means some
 * limiter refused the request outright. The application never saw it, so it
 * produced neither work nor information. Charging it would let a limiter that
 * trips first (the broad per-address login ceiling) quietly drain the
 * narrower per-account budget of every user sharing that address.
 */
function isChargeable(statusCode: number): boolean {
  return statusCode >= 400 && statusCode < 500 && statusCode !== 429;
}

export function createRateLimiter(
  rule: RateLimitRule,
  dependencies: RateLimiterDependencies = {},
): RequestHandler {
  const store = dependencies.store ?? new RateLimitStore();
  const now = dependencies.now ?? (() => Date.now());

  return (req, res, next) => {
    const dimension = rule.key(req);
    if (dimension === null) {
      next();
      return;
    }

    const key = `${rule.name}:${dimension}`;
    const timestamp = now();
    const decision = store.check(key, timestamp, rule.windowMs, rule.limit);

    if (!decision.allowed) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil(decision.retryAfterMs / 1000),
      );
      const error = rateLimitedError();

      logSecurityEvent({
        category: rule.category,
        outcome: 'rate_limited',
        requestId: req.requestId,
        subjectDigest: subjectDigest(key),
        retryAfterSeconds,
      });

      // Rejections are deliberately not charged to the bucket. Charging them
      // would keep pushing the window forward under sustained abuse and the
      // key would never recover.
      res
        .status(error.statusCode)
        .set('Retry-After', String(retryAfterSeconds))
        .json({
          error: error.code,
          message: error.message,
          retryable: error.retryable,
          statusCode: error.statusCode,
          timestamp: new Date().toISOString(),
        });
      return;
    }

    // Charge on the way in, always. Waiting for the response to decide would
    // let a burst of overlapping requests all pass this check before any of
    // them was counted — dozens of concurrent password guesses against a
    // limit of 5. The clock reading is the one taken above, so a slow handler
    // cannot stretch the window.
    store.record(key, timestamp, rule.windowMs);

    if (rule.count === 'client_failures') {
      res.on('finish', () => {
        if (!isChargeable(res.statusCode)) {
          // Give the reservation back. A request that never finishes (aborted
          // connection) keeps its charge, which is the safe direction.
          store.refund(key, timestamp);
        }
      });
    }

    next();
  };
}
