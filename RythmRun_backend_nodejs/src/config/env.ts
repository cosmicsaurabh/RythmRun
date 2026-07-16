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
  R2_PUBLIC_URL: string;
}

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
  'R2_PUBLIC_URL',
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

const DOCUMENTED_CONFIGURATION_PLACEHOLDER = /REPLACE[_-]?WITH/i;

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
    R2_PUBLIC_URL: requireConfiguredEnvironmentVariable(
      source,
      'R2_PUBLIC_URL',
    ),
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
