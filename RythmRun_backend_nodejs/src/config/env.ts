import dotenv from 'dotenv';

export type EnvironmentSource = Readonly<Record<string, string | undefined>>;

export interface JwtSecrets {
  accessSecret: string;
  refreshSecret: string;
}

export interface ServerEnvironment {
  DATABASE_URL: string;
  GOOGLE_SERVER_CLIENT_ID: string;
  JWT_SECRET: string;
  REFRESH_TOKEN_SECRET: string;
  R2_ACCOUNT_ID: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_BUCKET_AVATARS: string;
  R2_BUCKET_ACTIVITY_IMAGES: string;
}

/**
 * Optional email/SMTP configuration. Email verification is a feature module:
 * when NONE of these variables are set the feature is disabled and the app
 * still boots (fail-closed only for the always-required ServerEnvironment).
 * When ANY are set, ALL required fields must be present — a half-configured
 * mailer is worse than none.
 */
export interface EmailEnvironment {
  host: string;
  port: number;
  secure: boolean;
  user: string;
  pass: string;
  from: string;
  publicAppUrl: string;
}

/**
 * HTTP edge configuration. Browsers are the only clients CORS can constrain —
 * the mobile app sends no `Origin` and is unaffected — so this allowlist is a
 * defence for the web surface only and never replaces authentication.
 *
 * `trustProxyHops` is the number of proxies in front of this process. It must
 * match the real deployment: too high lets a client forge `X-Forwarded-For`
 * and escape every address-keyed rate limit, so the default is 0 (trust
 * nothing, use the socket address).
 */
export interface HttpSecurityEnvironment {
  allowedOrigins: readonly string[];
  trustProxyHops: number;
}

/**
 * Tunable auth timing. Every field replaces a value that used to be hardcoded in
 * a service, so the defaults reproduce today's behavior exactly. Resolved once at
 * boot from the environment and injected as 'AuthTiming' into AuthSessionService
 * and UserService, so a deployment can force a real-world scenario (a 30-second
 * access token, a 1-minute session) without a code change.
 *
 * `RETRY_SWEEP_INTERVAL_SECONDS` is deliberately absent: no service reads it, so
 * it is parsed at bootstrap by parseRetrySweepIntervalSeconds and used directly in
 * server.ts rather than injected here.
 */
export interface AuthTimingEnvironment {
  accessTokenTtlSeconds: number;
  refreshSessionTtlSeconds: number;
  maxActiveSessionsPerUser: number;
  // Consumed in Phase 2 (refresh reuse grace window); parsed now so the spine is
  // complete and Phase 2 is a behavior-only change.
  refreshReuseGraceSeconds: number;
  emailVerificationTtlSeconds: number;
  emailVerificationCooldownSeconds: number;
  passwordResetTtlSeconds: number;
  passwordResetCooldownSeconds: number;
}

/**
 * The timing values the services shipped with before they became tunable. This
 * is the single source of truth for the defaults: parseAuthTiming reads each
 * field as its fallback, and unit tests that construct the services directly
 * (bypassing the DI container) inject this constant.
 */
export const DEFAULT_AUTH_TIMING: AuthTimingEnvironment = {
  accessTokenTtlSeconds: 900,
  refreshSessionTtlSeconds: 604800,
  maxActiveSessionsPerUser: 5,
  refreshReuseGraceSeconds: 60,
  emailVerificationTtlSeconds: 86400,
  emailVerificationCooldownSeconds: 60,
  passwordResetTtlSeconds: 1800,
  passwordResetCooldownSeconds: 60,
};

export const HTTP_SECURITY_ENVIRONMENT_VARIABLES = [
  'CORS_ALLOWED_ORIGINS',
  'TRUST_PROXY_HOPS',
] as const;

export const MAX_TRUST_PROXY_HOPS = 10;

export const EMAIL_ENVIRONMENT_VARIABLES = [
  'SMTP_HOST',
  'SMTP_PORT',
  'SMTP_SECURE',
  'SMTP_USER',
  'SMTP_PASS',
  'MAIL_FROM',
  'PUBLIC_APP_URL',
] as const;

export const DEFAULT_SMTP_PORT = 587;

export const MINIMUM_JWT_SECRET_LENGTH = 32;

export const REQUIRED_SERVER_ENVIRONMENT_VARIABLES = [
  'DATABASE_URL',
  'GOOGLE_SERVER_CLIENT_ID',
  'JWT_SECRET',
  'REFRESH_TOKEN_SECRET',
  'R2_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET_AVATARS',
  'R2_BUCKET_ACTIVITY_IMAGES',
] as const satisfies ReadonlyArray<keyof ServerEnvironment>;

export class EnvironmentValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EnvironmentValidationError';
  }
}

const PLACEHOLDER_SECRET_PATTERNS = [
  /^your-secret-key(?:$|-)/i,
  /^your-refresh-secret-key(?:$|-)/i,
  /^change[-_]?me$/i,
  /^replace[-_]?me$/i,
  /^placeholder$/i,
];

const DOCUMENTED_CONFIGURATION_PLACEHOLDER =
  /(?:REPLACE[_-]?WITH|^your[-_])/i;

function requireEnvironmentVariable(
  source: EnvironmentSource,
  name: string,
): string {
  const value = source[name];

  if (value === undefined || value.trim().length === 0) {
    throw new EnvironmentValidationError(
      `${name} environment variable is required`,
    );
  }

  return value;
}

function requireConfiguredEnvironmentVariable(
  source: EnvironmentSource,
  name: Exclude<keyof ServerEnvironment, 'JWT_SECRET' | 'REFRESH_TOKEN_SECRET'>,
): string {
  const value = requireEnvironmentVariable(source, name);

  if (DOCUMENTED_CONFIGURATION_PLACEHOLDER.test(value)) {
    throw new EnvironmentValidationError(
      `${name} must not use a documented placeholder`,
    );
  }

  return value;
}

function requireJwtSecret(
  source: EnvironmentSource,
  name: 'JWT_SECRET' | 'REFRESH_TOKEN_SECRET',
): string {
  const value = requireEnvironmentVariable(source, name);

  if (value !== value.trim()) {
    throw new EnvironmentValidationError(
      `${name} must not have leading or trailing whitespace`,
    );
  }

  if (value.length < MINIMUM_JWT_SECRET_LENGTH) {
    throw new EnvironmentValidationError(
      `${name} must be at least ${MINIMUM_JWT_SECRET_LENGTH} characters long`,
    );
  }

  if (PLACEHOLDER_SECRET_PATTERNS.some((pattern) => pattern.test(value))) {
    throw new EnvironmentValidationError(
      `${name} must not use a documented or development placeholder`,
    );
  }

  return value;
}

function requireGoogleServerClientId(source: EnvironmentSource): string {
  const value = requireConfiguredEnvironmentVariable(
    source,
    'GOOGLE_SERVER_CLIENT_ID',
  );

  if (value !== value.trim()) {
    throw new EnvironmentValidationError(
      'GOOGLE_SERVER_CLIENT_ID must not have leading or trailing whitespace',
    );
  }
  if (!/^[^\s,]+\.apps\.googleusercontent\.com$/.test(value)) {
    throw new EnvironmentValidationError(
      'GOOGLE_SERVER_CLIENT_ID must be a Google OAuth client ID ending in .apps.googleusercontent.com',
    );
  }

  return value;
}

/**
 * Validates only JWT configuration. This is intentionally pure so token unit
 * tests do not need to provide database or R2 configuration.
 */
export function validateJwtSecrets(source: EnvironmentSource): JwtSecrets {
  const accessSecret = requireJwtSecret(source, 'JWT_SECRET');
  const refreshSecret = requireJwtSecret(source, 'REFRESH_TOKEN_SECRET');

  if (accessSecret === refreshSecret) {
    throw new EnvironmentValidationError(
      'JWT_SECRET and REFRESH_TOKEN_SECRET must be different',
    );
  }

  return { accessSecret, refreshSecret };
}

export function getJwtSecrets(
  source: EnvironmentSource = process.env,
): JwtSecrets {
  return validateJwtSecrets(source);
}

/**
 * Validates every variable required by the currently mounted backend routes.
 * Calling this function has no import-time side effects.
 */
export function validateServerEnvironment(
  source: EnvironmentSource,
): ServerEnvironment {
  const jwtSecrets = validateJwtSecrets(source);

  return {
    DATABASE_URL: requireConfiguredEnvironmentVariable(source, 'DATABASE_URL'),
    GOOGLE_SERVER_CLIENT_ID: requireGoogleServerClientId(source),
    JWT_SECRET: jwtSecrets.accessSecret,
    REFRESH_TOKEN_SECRET: jwtSecrets.refreshSecret,
    R2_ACCOUNT_ID: requireConfiguredEnvironmentVariable(
      source,
      'R2_ACCOUNT_ID',
    ),
    R2_ACCESS_KEY_ID: requireConfiguredEnvironmentVariable(
      source,
      'R2_ACCESS_KEY_ID',
    ),
    R2_SECRET_ACCESS_KEY: requireConfiguredEnvironmentVariable(
      source,
      'R2_SECRET_ACCESS_KEY',
    ),
    R2_BUCKET_AVATARS: requireConfiguredEnvironmentVariable(
      source,
      'R2_BUCKET_AVATARS',
    ),
    R2_BUCKET_ACTIVITY_IMAGES: requireConfiguredEnvironmentVariable(
      source,
      'R2_BUCKET_ACTIVITY_IMAGES',
    ),
  };
}

function parsePublicAppUrl(value: string): string {
  if (value !== value.trim()) {
    throw new EnvironmentValidationError(
      'PUBLIC_APP_URL must not have leading or trailing whitespace',
    );
  }
  if (DOCUMENTED_CONFIGURATION_PLACEHOLDER.test(value)) {
    throw new EnvironmentValidationError(
      'PUBLIC_APP_URL must not use a documented placeholder',
    );
  }

  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new EnvironmentValidationError(
      'PUBLIC_APP_URL must be an absolute http(s) URL',
    );
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new EnvironmentValidationError(
      'PUBLIC_APP_URL must use the http or https scheme',
    );
  }

  // Normalize away trailing slashes so verification links concatenate cleanly.
  return value.replace(/\/+$/, '');
}

function parseSmtpPort(source: EnvironmentSource): number {
  const raw = source.SMTP_PORT;
  if (raw === undefined || raw.trim().length === 0) {
    return DEFAULT_SMTP_PORT;
  }

  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new EnvironmentValidationError(
      'SMTP_PORT must be an integer between 1 and 65535',
    );
  }
  return port;
}

function parseSmtpSecure(source: EnvironmentSource): boolean {
  const raw = source.SMTP_SECURE;
  if (raw === undefined || raw.trim().length === 0) {
    return false;
  }

  const normalized = raw.trim().toLowerCase();
  if (normalized === 'true') {
    return true;
  }
  if (normalized === 'false') {
    return false;
  }
  throw new EnvironmentValidationError("SMTP_SECURE must be 'true' or 'false'");
}

/**
 * Validates the optional email feature configuration. Returns null when the
 * feature is entirely unconfigured (no email variables set), and throws when
 * it is only partially configured so a broken mailer never boots silently.
 */
export function validateEmailEnvironment(
  source: EnvironmentSource,
): EmailEnvironment | null {
  const anyConfigured = EMAIL_ENVIRONMENT_VARIABLES.some((name) => {
    const value = source[name];
    return value !== undefined && value.trim().length > 0;
  });
  if (!anyConfigured) {
    return null;
  }

  return {
    host: requireEnvironmentVariable(source, 'SMTP_HOST'),
    port: parseSmtpPort(source),
    secure: parseSmtpSecure(source),
    user: requireEnvironmentVariable(source, 'SMTP_USER'),
    pass: requireEnvironmentVariable(source, 'SMTP_PASS'),
    from: requireEnvironmentVariable(source, 'MAIL_FROM'),
    publicAppUrl: parsePublicAppUrl(
      requireEnvironmentVariable(source, 'PUBLIC_APP_URL'),
    ),
  };
}

function parseAllowedOrigin(raw: string, production: boolean): string {
  if (raw === '*') {
    throw new EnvironmentValidationError(
      'CORS_ALLOWED_ORIGINS must not contain a wildcard origin',
    );
  }
  if (DOCUMENTED_CONFIGURATION_PLACEHOLDER.test(raw)) {
    throw new EnvironmentValidationError(
      'CORS_ALLOWED_ORIGINS must not use a documented placeholder',
    );
  }

  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new EnvironmentValidationError(
      `CORS_ALLOWED_ORIGINS entry must be an absolute http(s) origin: ${raw}`,
    );
  }

  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new EnvironmentValidationError(
      `CORS_ALLOWED_ORIGINS entry must use the http or https scheme: ${raw}`,
    );
  }
  // An origin is scheme+host+port only. Accepting a path here would silently
  // widen the allowlist, because the browser only ever sends the origin.
  if (parsed.pathname !== '/' || parsed.search !== '' || parsed.hash !== '') {
    throw new EnvironmentValidationError(
      `CORS_ALLOWED_ORIGINS entry must not carry a path, query, or fragment: ${raw}`,
    );
  }
  if (parsed.username !== '' || parsed.password !== '') {
    throw new EnvironmentValidationError(
      `CORS_ALLOWED_ORIGINS entry must not carry credentials: ${raw}`,
    );
  }
  if (production && parsed.protocol !== 'https:') {
    throw new EnvironmentValidationError(
      `CORS_ALLOWED_ORIGINS entry must use https in production: ${raw}`,
    );
  }

  return parsed.origin;
}

function parseAllowedOrigins(
  source: EnvironmentSource,
  production: boolean,
): readonly string[] {
  const raw = source.CORS_ALLOWED_ORIGINS;
  const entries =
    raw === undefined
      ? []
      : raw
          .split(',')
          .map((entry) => entry.trim())
          .filter((entry) => entry.length > 0);

  if (entries.length === 0) {
    if (production) {
      throw new EnvironmentValidationError(
        'CORS_ALLOWED_ORIGINS environment variable is required in production',
      );
    }
    // Outside production an empty allowlist is the safe default: no browser
    // origin is granted access, and non-browser clients are unaffected.
    return [];
  }

  const origins = entries.map((entry) => parseAllowedOrigin(entry, production));
  return [...new Set(origins)];
}

function parseTrustProxyHops(source: EnvironmentSource): number {
  const raw = source.TRUST_PROXY_HOPS;
  if (raw === undefined || raw.trim().length === 0) {
    return 0;
  }

  const hops = Number(raw.trim());
  if (!Number.isInteger(hops) || hops < 0 || hops > MAX_TRUST_PROXY_HOPS) {
    throw new EnvironmentValidationError(
      `TRUST_PROXY_HOPS must be an integer between 0 and ${MAX_TRUST_PROXY_HOPS}`,
    );
  }

  return hops;
}

/**
 * Parses one optional integer environment variable. Absent or blank falls back
 * to the default; anything present must be an integer inside [min, max] or boot
 * fails closed. The bounds are typo protection, not policy —
 * `ACCESS_TOKEN_TTL_SECONDS=9000000` should stop the boot, not silently mint a
 * three-month token.
 */
function parseIntEnv(
  source: EnvironmentSource,
  name: string,
  bounds: { fallback: number; min: number; max: number },
): number {
  const raw = source[name];
  if (raw === undefined || raw.trim().length === 0) {
    return bounds.fallback;
  }

  const value = Number(raw.trim());
  if (!Number.isInteger(value) || value < bounds.min || value > bounds.max) {
    throw new EnvironmentValidationError(
      `${name} must be an integer between ${bounds.min} and ${bounds.max}`,
    );
  }
  return value;
}

/**
 * Resolves the tunable auth timing knobs once at boot. Each fallback comes from
 * DEFAULT_AUTH_TIMING so the defaults live in exactly one place; the bounds are
 * per-variable here.
 */
export function parseAuthTiming(
  source: EnvironmentSource,
): AuthTimingEnvironment {
  return {
    accessTokenTtlSeconds: parseIntEnv(source, 'ACCESS_TOKEN_TTL_SECONDS', {
      fallback: DEFAULT_AUTH_TIMING.accessTokenTtlSeconds,
      min: 30,
      max: 86400,
    }),
    refreshSessionTtlSeconds: parseIntEnv(
      source,
      'REFRESH_SESSION_TTL_SECONDS',
      { fallback: DEFAULT_AUTH_TIMING.refreshSessionTtlSeconds, min: 60, max: 7776000 },
    ),
    maxActiveSessionsPerUser: parseIntEnv(
      source,
      'MAX_ACTIVE_SESSIONS_PER_USER',
      { fallback: DEFAULT_AUTH_TIMING.maxActiveSessionsPerUser, min: 1, max: 100 },
    ),
    refreshReuseGraceSeconds: parseIntEnv(
      source,
      'REFRESH_REUSE_GRACE_SECONDS',
      { fallback: DEFAULT_AUTH_TIMING.refreshReuseGraceSeconds, min: 0, max: 300 },
    ),
    emailVerificationTtlSeconds: parseIntEnv(
      source,
      'EMAIL_VERIFICATION_TTL_SECONDS',
      { fallback: DEFAULT_AUTH_TIMING.emailVerificationTtlSeconds, min: 60, max: 604800 },
    ),
    emailVerificationCooldownSeconds: parseIntEnv(
      source,
      'EMAIL_VERIFICATION_COOLDOWN_SECONDS',
      { fallback: DEFAULT_AUTH_TIMING.emailVerificationCooldownSeconds, min: 0, max: 3600 },
    ),
    passwordResetTtlSeconds: parseIntEnv(
      source,
      'PASSWORD_RESET_TTL_SECONDS',
      { fallback: DEFAULT_AUTH_TIMING.passwordResetTtlSeconds, min: 60, max: 86400 },
    ),
    passwordResetCooldownSeconds: parseIntEnv(
      source,
      'PASSWORD_RESET_COOLDOWN_SECONDS',
      { fallback: DEFAULT_AUTH_TIMING.passwordResetCooldownSeconds, min: 0, max: 3600 },
    ),
  };
}

/**
 * The background sweep interval (expired sessions/tokens, pending media
 * cleanup). Bootstrap-only — no service reads it — so it is parsed here and used
 * directly by the sweep timer in server.ts rather than injected with the auth
 * timing knobs.
 */
export function parseRetrySweepIntervalSeconds(
  source: EnvironmentSource,
): number {
  return parseIntEnv(source, 'RETRY_SWEEP_INTERVAL_SECONDS', {
    fallback: 900,
    min: 10,
    max: 86400,
  });
}

/**
 * Validates the browser-facing edge configuration. Production must name its
 * allowed origins explicitly; every other environment defaults to an empty
 * allowlist rather than the permissive wildcard the app used before IP-2.6.
 */
export function validateHttpSecurityEnvironment(
  source: EnvironmentSource,
): HttpSecurityEnvironment {
  const production = source.NODE_ENV === 'production';

  return {
    allowedOrigins: parseAllowedOrigins(source, production),
    trustProxyHops: parseTrustProxyHops(source),
  };
}

/**
 * Bootstrap entry point. It loads a local .env when present and then fails
 * closed if any required runtime configuration is absent or unsafe.
 */
export function loadAndValidateEnvironment(): ServerEnvironment {
  dotenv.config({ quiet: true });
  return validateServerEnvironment(process.env);
}
