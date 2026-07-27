import {
  EnvironmentValidationError,
  MAX_TRUST_PROXY_HOPS,
  MINIMUM_JWT_SECRET_LENGTH,
  getJwtSecrets,
  validateEmailEnvironment,
  validateHttpSecurityEnvironment,
  validateJwtSecrets,
  validateServerEnvironment,
} from '../config/env.js';

const ACCESS_SECRET = 'a'.repeat(MINIMUM_JWT_SECRET_LENGTH);
const REFRESH_SECRET = 'b'.repeat(MINIMUM_JWT_SECRET_LENGTH);

const validServerEnvironment = {
  DATABASE_URL: 'postgresql://user:password@localhost:5432/rythmrun',
  GOOGLE_SERVER_CLIENT_ID: 'test.apps.googleusercontent.com',
  JWT_SECRET: ACCESS_SECRET,
  REFRESH_TOKEN_SECRET: REFRESH_SECRET,
  R2_ACCOUNT_ID: 'test-account-id',
  R2_ACCESS_KEY_ID: 'test-access-key',
  R2_SECRET_ACCESS_KEY: 'test-secret-access-key',
  R2_BUCKET_AVATARS: 'test-avatars-bucket',
  R2_BUCKET_ACTIVITY_IMAGES: 'test-activity-images-bucket',
  R2_PUBLIC_URL: 'https://test-account-id.r2.cloudflarestorage.com',
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
    'GOOGLE_SERVER_CLIENT_ID',
    'R2_ACCOUNT_ID',
    'R2_ACCESS_KEY_ID',
    'R2_SECRET_ACCESS_KEY',
    'R2_BUCKET_AVATARS',
    'R2_BUCKET_ACTIVITY_IMAGES',
    'R2_PUBLIC_URL',
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
    ['GOOGLE_SERVER_CLIENT_ID', 'REPLACE_WITH_GOOGLE_SERVER_CLIENT_ID'],
    ['R2_ACCOUNT_ID', 'REPLACE_WITH_ACCOUNT_ID'],
    ['R2_ACCESS_KEY_ID', 'REPLACE_WITH_ACCESS_KEY_ID'],
    ['R2_SECRET_ACCESS_KEY', 'REPLACE_WITH_SECRET_ACCESS_KEY'],
    ['R2_BUCKET_AVATARS', 'REPLACE_WITH_BUCKET_NAME'],
  ] as const)('rejects a documented %s placeholder', (name, value) => {
    expect(() =>
      validateServerEnvironment({
        ...validServerEnvironment,
        [name]: value,
      }),
    ).toThrow(`${name} must not use a documented placeholder`);
  });

  it.each([
    ' test.apps.googleusercontent.com',
    'test.apps.googleusercontent.com ',
    'not-a-google-client-id',
    'one.apps.googleusercontent.com,two.apps.googleusercontent.com',
  ])('rejects an invalid Google server client ID: %s', (clientId) => {
    expect(() =>
      validateServerEnvironment({
        ...validServerEnvironment,
        GOOGLE_SERVER_CLIENT_ID: clientId,
      }),
    ).toThrow('GOOGLE_SERVER_CLIENT_ID');
  });
});

describe('email environment validation', () => {
  const validEmailEnvironment = {
    SMTP_HOST: 'smtp-relay.brevo.com',
    SMTP_PORT: '587',
    SMTP_SECURE: 'false',
    SMTP_USER: 'mailer@reshapeapp.ai',
    SMTP_PASS: 'brevo-smtp-key',
    MAIL_FROM: 'RythmRun <noreply@reshapeapp.ai>',
    PUBLIC_APP_URL: 'https://rythmrun.onrender.com',
  };

  it('returns null when no email variables are set (feature disabled)', () => {
    expect(validateEmailEnvironment({})).toBeNull();
  });

  it('parses a fully configured mailer with defaults applied', () => {
    expect(validateEmailEnvironment(validEmailEnvironment)).toEqual({
      host: 'smtp-relay.brevo.com',
      port: 587,
      secure: false,
      user: 'mailer@reshapeapp.ai',
      pass: 'brevo-smtp-key',
      from: 'RythmRun <noreply@reshapeapp.ai>',
      publicAppUrl: 'https://rythmrun.onrender.com',
    });
  });

  it('defaults port to 587 and secure to false when omitted', () => {
    const source: Record<string, string | undefined> = {
      ...validEmailEnvironment,
    };
    delete source.SMTP_PORT;
    delete source.SMTP_SECURE;

    const result = validateEmailEnvironment(source);
    expect(result?.port).toBe(587);
    expect(result?.secure).toBe(false);
  });

  it('strips a trailing slash from PUBLIC_APP_URL for clean link building', () => {
    expect(
      validateEmailEnvironment({
        ...validEmailEnvironment,
        PUBLIC_APP_URL: 'https://rythmrun.onrender.com/',
      })?.publicAppUrl,
    ).toBe('https://rythmrun.onrender.com');
  });

  it.each(['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS', 'MAIL_FROM', 'PUBLIC_APP_URL'])(
    'throws when partially configured and %s is missing',
    (name) => {
      const source: Record<string, string | undefined> = {
        ...validEmailEnvironment,
      };
      delete source[name];

      expect(() => validateEmailEnvironment(source)).toThrow(
        EnvironmentValidationError,
      );
    },
  );

  it.each([
    'not-a-url',
    'ftp://rythmrun.onrender.com',
    ' https://rythmrun.onrender.com',
    'REPLACE_WITH_PUBLIC_APP_URL',
  ])('rejects an invalid PUBLIC_APP_URL: %s', (url) => {
    expect(() =>
      validateEmailEnvironment({ ...validEmailEnvironment, PUBLIC_APP_URL: url }),
    ).toThrow('PUBLIC_APP_URL');
  });

  it.each(['0', '70000', 'abc'])('rejects an invalid SMTP_PORT: %s', (port) => {
    expect(() =>
      validateEmailEnvironment({ ...validEmailEnvironment, SMTP_PORT: port }),
    ).toThrow('SMTP_PORT');
  });

  it('rejects a non-boolean SMTP_SECURE', () => {
    expect(() =>
      validateEmailEnvironment({ ...validEmailEnvironment, SMTP_SECURE: 'yes' }),
    ).toThrow('SMTP_SECURE');
  });
});

describe('HTTP security environment validation', () => {
  const PRODUCTION = { NODE_ENV: 'production' };

  it('defaults to an empty allowlist and no trusted proxy outside production', () => {
    expect(validateHttpSecurityEnvironment({})).toEqual({
      allowedOrigins: [],
      trustProxyHops: 0,
    });
  });

  it('requires an explicit allowlist in production', () => {
    expect(() => validateHttpSecurityEnvironment(PRODUCTION)).toThrow(
      'CORS_ALLOWED_ORIGINS environment variable is required in production',
    );
    expect(() =>
      validateHttpSecurityEnvironment({
        ...PRODUCTION,
        CORS_ALLOWED_ORIGINS: '  ,  ',
      }),
    ).toThrow('CORS_ALLOWED_ORIGINS environment variable is required in production');
  });

  it('parses, trims, and de-duplicates a comma-separated allowlist', () => {
    expect(
      validateHttpSecurityEnvironment({
        CORS_ALLOWED_ORIGINS:
          'https://app.example.com, https://admin.example.com ,https://app.example.com',
      }).allowedOrigins,
    ).toEqual(['https://app.example.com', 'https://admin.example.com']);
  });

  it('normalises an entry to its origin, discarding a default port', () => {
    expect(
      validateHttpSecurityEnvironment({
        CORS_ALLOWED_ORIGINS: 'https://app.example.com:443',
      }).allowedOrigins,
    ).toEqual(['https://app.example.com']);
    expect(
      validateHttpSecurityEnvironment({
        CORS_ALLOWED_ORIGINS: 'http://localhost:3000',
      }).allowedOrigins,
    ).toEqual(['http://localhost:3000']);
  });

  it('rejects a wildcard origin', () => {
    expect(() =>
      validateHttpSecurityEnvironment({ CORS_ALLOWED_ORIGINS: '*' }),
    ).toThrow('must not contain a wildcard origin');
  });

  it.each([
    'app.example.com',
    'ftp://app.example.com',
    'https://app.example.com/dashboard',
    'https://app.example.com/?tenant=1',
    'https://app.example.com/#fragment',
    'https://user:pass@app.example.com',
    'REPLACE_WITH_FRONTEND_ORIGIN',
  ])('rejects an unusable allowlist entry: %s', (origin) => {
    expect(() =>
      validateHttpSecurityEnvironment({ CORS_ALLOWED_ORIGINS: origin }),
    ).toThrow('CORS_ALLOWED_ORIGINS');
  });

  it('refuses a plaintext origin in production but allows it in development', () => {
    expect(() =>
      validateHttpSecurityEnvironment({
        ...PRODUCTION,
        CORS_ALLOWED_ORIGINS: 'http://app.example.com',
      }),
    ).toThrow('must use https in production');
    expect(
      validateHttpSecurityEnvironment({
        CORS_ALLOWED_ORIGINS: 'http://app.example.com',
      }).allowedOrigins,
    ).toEqual(['http://app.example.com']);
  });

  it('accepts a proxy hop count within the supported range', () => {
    expect(
      validateHttpSecurityEnvironment({ TRUST_PROXY_HOPS: '1' }).trustProxyHops,
    ).toBe(1);
    expect(
      validateHttpSecurityEnvironment({ TRUST_PROXY_HOPS: '  2 ' })
        .trustProxyHops,
    ).toBe(2);
    expect(
      validateHttpSecurityEnvironment({ TRUST_PROXY_HOPS: '' }).trustProxyHops,
    ).toBe(0);
  });

  it.each(['-1', '1.5', 'two', String(MAX_TRUST_PROXY_HOPS + 1)])(
    'rejects an unusable TRUST_PROXY_HOPS: %s',
    (hops) => {
      expect(() =>
        validateHttpSecurityEnvironment({ TRUST_PROXY_HOPS: hops }),
      ).toThrow('TRUST_PROXY_HOPS');
    },
  );

  it('raises a typed configuration error', () => {
    expect(() =>
      validateHttpSecurityEnvironment({ CORS_ALLOWED_ORIGINS: '*' }),
    ).toThrow(EnvironmentValidationError);
  });
});
