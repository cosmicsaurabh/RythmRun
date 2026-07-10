import {
  EnvironmentValidationError,
  MINIMUM_JWT_SECRET_LENGTH,
  getJwtSecrets,
  validateJwtSecrets,
  validateServerEnvironment,
} from '../config/env';

const ACCESS_SECRET = 'a'.repeat(MINIMUM_JWT_SECRET_LENGTH);
const REFRESH_SECRET = 'b'.repeat(MINIMUM_JWT_SECRET_LENGTH);

const validServerEnvironment = {
  DATABASE_URL: 'postgresql://user:password@localhost:5432/rythmrun',
  JWT_SECRET: ACCESS_SECRET,
  REFRESH_TOKEN_SECRET: REFRESH_SECRET,
  AWS_REGION: 'us-east-1',
  AWS_ACCESS_KEY_ID: 'test-access-key',
  AWS_SECRET_ACCESS_KEY: 'test-secret-access-key',
  S3_BUCKET: 'test-bucket',
  CLOUDFRONT_DOMAIN: 'assets.example.test',
  CLOUDFRONT_KEY_PAIR_ID: 'test-key-pair',
  CLOUDFRONT_PRIVATE_KEY: 'test-private-key',
};

describe('JWT environment validation', () => {
  it('validates JWT secrets without requiring unrelated server variables', () => {
    expect(
      validateJwtSecrets({
        JWT_SECRET: ACCESS_SECRET,
        REFRESH_TOKEN_SECRET: REFRESH_SECRET,
      }),
    ).toEqual({
      accessSecret: ACCESS_SECRET,
      refreshSecret: REFRESH_SECRET,
    });
  });

  it.each(['JWT_SECRET', 'REFRESH_TOKEN_SECRET'] as const)(
    'rejects a missing %s',
    (name) => {
      const source = {
        JWT_SECRET: ACCESS_SECRET,
        REFRESH_TOKEN_SECRET: REFRESH_SECRET,
      };
      delete source[name];

      expect(() => validateJwtSecrets(source)).toThrow(
        `${name} environment variable is required`,
      );
    },
  );

  it.each([
    ['JWT_SECRET', 'your-secret-key-here-minimum-32-characters-long'],
    [
      'REFRESH_TOKEN_SECRET',
      'your-refresh-secret-key-here-minimum-32-characters-long',
    ],
  ] as const)('rejects a placeholder %s', (name, value) => {
    expect(() =>
      validateJwtSecrets({
        JWT_SECRET: name === 'JWT_SECRET' ? value : ACCESS_SECRET,
        REFRESH_TOKEN_SECRET:
          name === 'REFRESH_TOKEN_SECRET' ? value : REFRESH_SECRET,
      }),
    ).toThrow(`${name} must not use a documented or development placeholder`);
  });

  it.each(['JWT_SECRET', 'REFRESH_TOKEN_SECRET'] as const)(
    'rejects a short %s without exposing its value',
    (name) => {
      const secretValue = 'sensitive-short-value';

      try {
        validateJwtSecrets({
          JWT_SECRET: name === 'JWT_SECRET' ? secretValue : ACCESS_SECRET,
          REFRESH_TOKEN_SECRET:
            name === 'REFRESH_TOKEN_SECRET' ? secretValue : REFRESH_SECRET,
        });
        throw new Error('Expected validation to fail');
      } catch (error) {
        expect(error).toBeInstanceOf(EnvironmentValidationError);
        expect((error as Error).message).toContain(name);
        expect((error as Error).message).not.toContain(secretValue);
      }
    },
  );

  it('rejects reuse of the access secret as the refresh secret', () => {
    expect(() =>
      validateJwtSecrets({
        JWT_SECRET: ACCESS_SECRET,
        REFRESH_TOKEN_SECRET: ACCESS_SECRET,
      }),
    ).toThrow('JWT_SECRET and REFRESH_TOKEN_SECRET must be different');
  });

  it('uses REFRESH_TOKEN_SECRET as the only refresh secret name', () => {
    expect(() =>
      getJwtSecrets({
        JWT_SECRET: ACCESS_SECRET,
        JWT_REFRESH_SECRET: REFRESH_SECRET,
      }),
    ).toThrow('REFRESH_TOKEN_SECRET environment variable is required');
  });
});

describe('server environment validation', () => {
  it('returns the complete validated environment', () => {
    expect(validateServerEnvironment(validServerEnvironment)).toEqual(
      validServerEnvironment,
    );
  });

  it.each([
    'DATABASE_URL',
    'AWS_REGION',
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'S3_BUCKET',
    'CLOUDFRONT_DOMAIN',
    'CLOUDFRONT_KEY_PAIR_ID',
    'CLOUDFRONT_PRIVATE_KEY',
  ] as const)('rejects a missing %s', (name) => {
    const source: Record<string, string | undefined> = {
      ...validServerEnvironment,
    };
    delete source[name];

    expect(() => validateServerEnvironment(source)).toThrow(
      `${name} environment variable is required`,
    );
  });

  it.each([
    ['DATABASE_URL', 'REPLACE_WITH_DATABASE_URL'],
    ['AWS_ACCESS_KEY_ID', 'REPLACE_WITH_ACCESS_KEY_ID'],
    ['AWS_SECRET_ACCESS_KEY', 'REPLACE_WITH_SECRET_ACCESS_KEY'],
    ['S3_BUCKET', 'REPLACE_WITH_BUCKET_NAME'],
    ['CLOUDFRONT_DOMAIN', 'REPLACE_WITH_CLOUDFRONT_DOMAIN'],
    ['CLOUDFRONT_KEY_PAIR_ID', 'REPLACE_WITH_KEY_PAIR_ID'],
    ['CLOUDFRONT_PRIVATE_KEY', 'REPLACE_WITH_PRIVATE_KEY'],
  ] as const)('rejects a documented %s placeholder', (name, value) => {
    expect(() =>
      validateServerEnvironment({
        ...validServerEnvironment,
        [name]: value,
      }),
    ).toThrow(`${name} must not use a documented placeholder`);
  });
});
