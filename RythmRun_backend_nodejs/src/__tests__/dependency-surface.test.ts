import fs from 'fs';
import path from 'path';

type BackendPackage = {
  engines?: Record<string, string>;
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
};

type BackendPackageLock = {
  packages?: Record<string, unknown>;
};

const packageJson = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../../package.json'), 'utf8'),
) as BackendPackage;
const packageLock = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../../package-lock.json'), 'utf8'),
) as BackendPackageLock;

const dependencies = packageJson.dependencies ?? {};
const allDeclaredDependencies = {
  ...dependencies,
  ...(packageJson.devDependencies ?? {}),
};

describe('backend production dependency surface', () => {
  it('uses the supported Node runtime required by the current AWS SDK', () => {
    expect(packageJson.engines?.node).toBe('22.x');
  });

  it('keeps the end-of-support monolithic AWS SDK out of the dependency graph', () => {
    expect(allDeclaredDependencies).not.toHaveProperty('aws-sdk');
    expect(
      Object.keys(packageLock.packages ?? {}).some(
        packagePath =>
          packagePath === 'node_modules/aws-sdk' ||
          packagePath.endsWith('/node_modules/aws-sdk'),
      ),
    ).toBe(false);
    expect(dependencies).toEqual(
      expect.objectContaining({
        '@aws-sdk/client-s3': expect.any(String),
        '@aws-sdk/cloudfront-signer': expect.any(String),
        '@aws-sdk/s3-presigned-post': expect.any(String),
        '@aws-sdk/s3-request-presigner': expect.any(String),
      }),
    );
  });

  it.each(['joi', 'pg', 'winston'])(
    'does not restore the unused %s runtime dependency',
    dependency => {
      expect(dependencies).not.toHaveProperty(dependency);
    },
  );
});
