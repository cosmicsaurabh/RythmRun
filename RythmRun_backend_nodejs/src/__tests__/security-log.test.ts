import {
  logSecurityEvent,
  setSecurityLogSink,
  subjectDigest,
  type SecurityLogSink,
} from '../utils/security-log.js';

describe('privacy-safe security events', () => {
  const emitted: string[] = [];
  let restoreSink: SecurityLogSink;

  beforeEach(() => {
    emitted.length = 0;
    restoreSink = setSecurityLogSink((line) => emitted.push(line));
  });

  afterEach(() => {
    setSecurityLogSink(restoreSink);
  });

  it('emits one JSON line with the fixed field set', () => {
    logSecurityEvent({
      category: 'auth.login',
      outcome: 'rate_limited',
      requestId: 'request-1',
      subjectDigest: 'abcdef123456',
      retryAfterSeconds: 900,
    });

    expect(emitted).toHaveLength(1);
    const record = JSON.parse(emitted[0]) as Record<string, unknown>;
    expect(Object.keys(record).sort()).toEqual([
      'category',
      'outcome',
      'requestId',
      'retryAfterSeconds',
      'subjectDigest',
      'timestamp',
      'type',
    ]);
    expect(record.type).toBe('security_event');
    expect(Date.parse(record.timestamp as string)).not.toBeNaN();
  });

  it('omits optional fields rather than writing null placeholders', () => {
    logSecurityEvent({ category: 'auth.register', outcome: 'rate_limited' });

    const record = JSON.parse(emitted[0]) as Record<string, unknown>;
    expect(Object.keys(record).sort()).toEqual([
      'category',
      'outcome',
      'timestamp',
      'type',
    ]);
  });

  it('ignores any field the caller did not declare in the event contract', () => {
    logSecurityEvent({
      category: 'auth.login',
      outcome: 'rate_limited',
      // A future caller passing extra context must not be able to widen the
      // record: the logger copies named fields only, it never spreads.
      password: 'super-secret',
      email: 'runner@example.com',
      latitude: 51.5,
    } as never);

    expect(emitted[0]).not.toContain('super-secret');
    expect(emitted[0]).not.toContain('runner@example.com');
    expect(emitted[0]).not.toContain('51.5');
  });

  it('produces a stable, short, non-reversible subject digest', () => {
    const value = 'login:runner@example.com|203.0.113.10';

    expect(subjectDigest(value)).toBe(subjectDigest(value));
    expect(subjectDigest(value)).toHaveLength(12);
    expect(subjectDigest(value)).toMatch(/^[0-9a-f]{12}$/);
    expect(subjectDigest(value)).not.toContain('runner');
    expect(subjectDigest(value)).not.toBe(subjectDigest(`${value}x`));
  });
});
