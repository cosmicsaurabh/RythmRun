import fs from 'node:fs';
import path from 'node:path';

type BackendPackage = {
  type?: string;
  engines?: Record<string, string>;
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
};

type BackendPackageLock = {
  packages?: Record<string, unknown>;
};

const packageJson = JSON.parse(
  fs.readFileSync(path.resolve(process.cwd(), 'package.json'), 'utf8'),
) as BackendPackage;
const packageLock = JSON.parse(
  fs.readFileSync(path.resolve(process.cwd(), 'package-lock.json'), 'utf8'),
) as BackendPackageLock;

const dependencies = packageJson.dependencies ?? {};
const devDependencies = packageJson.devDependencies ?? {};
const allDeclaredDependencies = {
  ...dependencies,
  ...devDependencies,
};

describe('backend production dependency surface', () => {
  it('uses the supported Node runtime required by the current AWS SDK', () => {
    expect(packageJson.engines?.node).toBe('22.x');
  });

  it('runs the backend and generated Prisma client as native ESM', () => {
    expect(packageJson.type).toBe('module');
  });

  it('keeps the Prisma 7 PostgreSQL adapter stack aligned and explicit', () => {
    expect(dependencies).toEqual(
      expect.objectContaining({
        '@prisma/adapter-pg': '7.8.0',
        '@prisma/client': '7.8.0',
        pg: '8.22.0',
      }),
    );
    expect(devDependencies.prisma).toBe('7.8.0');
  });

  it('uses the official Google verifier for backend ID-token validation', () => {
    expect(dependencies['google-auth-library']).toEqual(expect.any(String));
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
        '@aws-sdk/s3-presigned-post': expect.any(String),
        '@aws-sdk/s3-request-presigner': expect.any(String),
      }),
    );
  });

  it.each(['joi', 'winston'])(
    'does not restore the unused %s runtime dependency',
    dependency => {
      expect(dependencies).not.toHaveProperty(dependency);
    },
  );
});
