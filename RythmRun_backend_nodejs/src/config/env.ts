import dotenv from 'dotenv';

export type EnvironmentSource = Readonly<Record<string, string | undefined>>;

export interface JwtSecrets {
  accessSecret: string;
  refreshSecret: string;
}

export interface ServerEnvironment {
  DATABASE_URL: string;
  JWT_SECRET: string;
  REFRESH_TOKEN_SECRET: string;
  AWS_REGION: string;
  AWS_ACCESS_KEY_ID: string;
  AWS_SECRET_ACCESS_KEY: string;
  S3_BUCKET: string;
  CLOUDFRONT_DOMAIN: string;
  CLOUDFRONT_KEY_PAIR_ID: string;
  CLOUDFRONT_PRIVATE_KEY: string;
}

export const MINIMUM_JWT_SECRET_LENGTH = 32;

export const REQUIRED_SERVER_ENVIRONMENT_VARIABLES = [
  'DATABASE_URL',
  'JWT_SECRET',
  'REFRESH_TOKEN_SECRET',
  'AWS_REGION',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'S3_BUCKET',
  'CLOUDFRONT_DOMAIN',
  'CLOUDFRONT_KEY_PAIR_ID',
  'CLOUDFRONT_PRIVATE_KEY',
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

/**
 * Validates only JWT configuration. This is intentionally pure so token unit
 * tests do not need to provide database, AWS, or CloudFront configuration.
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
    JWT_SECRET: jwtSecrets.accessSecret,
    REFRESH_TOKEN_SECRET: jwtSecrets.refreshSecret,
    AWS_REGION: requireConfiguredEnvironmentVariable(source, 'AWS_REGION'),
    AWS_ACCESS_KEY_ID: requireConfiguredEnvironmentVariable(
      source,
      'AWS_ACCESS_KEY_ID',
    ),
    AWS_SECRET_ACCESS_KEY: requireConfiguredEnvironmentVariable(
      source,
      'AWS_SECRET_ACCESS_KEY',
    ),
    S3_BUCKET: requireConfiguredEnvironmentVariable(source, 'S3_BUCKET'),
    CLOUDFRONT_DOMAIN: requireConfiguredEnvironmentVariable(
      source,
      'CLOUDFRONT_DOMAIN',
    ),
    CLOUDFRONT_KEY_PAIR_ID: requireConfiguredEnvironmentVariable(
      source,
      'CLOUDFRONT_KEY_PAIR_ID',
    ),
    CLOUDFRONT_PRIVATE_KEY: requireConfiguredEnvironmentVariable(
      source,
      'CLOUDFRONT_PRIVATE_KEY',
    ),
  };
}

/**
 * Bootstrap entry point. It loads a local .env when present and then fails
 * closed if any required runtime configuration is absent or unsafe.
 */
export function loadAndValidateEnvironment(): ServerEnvironment {
  dotenv.config();
  return validateServerEnvironment(process.env);
}
