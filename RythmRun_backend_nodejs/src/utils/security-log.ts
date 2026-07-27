import { createHash } from 'node:crypto';

/**
 * Privacy-safe security event logging (IP-2.6 item 5).
 *
 * The emitted record is assembled from a fixed, allowlisted field set — never
 * from a caller-supplied object — so a request body, bearer/refresh token,
 * verification or reset link, presigned URL, email address, or coordinate can
 * never reach the log by accident. Anything that identifies a person is
 * reduced to `subjectDigest` before it gets here.
 */
export type SecurityEventCategory =
  | 'auth.login'
  | 'auth.register'
  | 'auth.google_exchange'
  | 'auth.password_change'
  | 'auth.password_reset_request'
  | 'auth.password_reset_submit'
  | 'auth.verification_resend';

export type SecurityEventOutcome = 'rate_limited';

export interface SecurityEvent {
  category: SecurityEventCategory;
  outcome: SecurityEventOutcome;
  requestId?: string;
  /** Non-reversible short digest of the limiter key — see `subjectDigest`. */
  subjectDigest?: string;
  retryAfterSeconds?: number;
}

const DIGEST_LENGTH = 12;

/**
 * Reduces an identifying value (email address, client address, or a composite
 * limiter key) to a short hex digest. Repeat offenders stay correlatable
 * across log lines while the address or mailbox itself is never written down.
 *
 * This is a plain digest, not a keyed MAC: it is a log-minimisation measure,
 * not a claim that a determined reader could not confirm a guessed address.
 */
export function subjectDigest(value: string): string {
  return createHash('sha256').update(value).digest('hex').slice(0, DIGEST_LENGTH);
}

export interface SecurityLogSink {
  (line: string): void;
}

let sink: SecurityLogSink = (line) => console.warn(line);

/** Test seam. Returns the previous sink so a caller can restore it. */
export function setSecurityLogSink(next: SecurityLogSink): SecurityLogSink {
  const previous = sink;
  sink = next;
  return previous;
}

export function logSecurityEvent(event: SecurityEvent): void {
  // Built field by field on purpose: spreading the argument would let a future
  // caller smuggle an unreviewed field into the log.
  const record: Record<string, string | number> = {
    type: 'security_event',
    category: event.category,
    outcome: event.outcome,
    timestamp: new Date().toISOString(),
  };

  if (event.requestId !== undefined) {
    record.requestId = event.requestId;
  }
  if (event.subjectDigest !== undefined) {
    record.subjectDigest = event.subjectDigest;
  }
  if (event.retryAfterSeconds !== undefined) {
    record.retryAfterSeconds = event.retryAfterSeconds;
  }

  sink(JSON.stringify(record));
}
