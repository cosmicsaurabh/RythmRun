import fs from 'node:fs';
import path from 'node:path';
import { jest } from '@jest/globals';

import {
  POSTGRES_CONNECT_TIMEOUT_MS,
  POSTGRES_IDLE_TIMEOUT_MS,
  POSTGRES_POOL_MAX,
  buildPostgresPoolConfig,
  getPostgresSchema,
  onceAsync,
} from '../config/database.js';

function listTypeScriptFiles(directory: string): string[] {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return listTypeScriptFiles(absolutePath);
    }
    return entry.isFile() && entry.name.endsWith('.ts') ? [absolutePath] : [];
  });
}

describe('Prisma 7 database runtime', () => {
  it('uses an explicit bounded PostgreSQL pool configuration', () => {
    const databaseUrl = 'postgresql://app:secret@db.example.com:5432/rythmrun';

    expect(buildPostgresPoolConfig(databaseUrl)).toEqual({
      connectionString: databaseUrl,
      max: POSTGRES_POOL_MAX,
      connectionTimeoutMillis: POSTGRES_CONNECT_TIMEOUT_MS,
      idleTimeoutMillis: POSTGRES_IDLE_TIMEOUT_MS,
      maxLifetimeSeconds: 0,
    });
    expect(() => buildPostgresPoolConfig('   ')).toThrow(
      'DATABASE_URL must not be empty',
    );
    expect(getPostgresSchema(`${databaseUrl}?schema=tenant_42`)).toBe(
      'tenant_42',
    );
    expect(getPostgresSchema(databaseUrl)).toBeUndefined();
    expect(getPostgresSchema(`${databaseUrl}?schema=`)).toBeUndefined();
  });

  it('disconnects an owned adapter exactly once across concurrent callers', async () => {
    let finishOperation: (() => void) | undefined;
    const pendingOperation = new Promise<void>(resolve => {
      finishOperation = resolve;
    });
    const operation = jest.fn<() => Promise<void>>(() => pendingOperation);
    const disconnect = onceAsync(operation);

    const first = disconnect();
    const second = disconnect();

    expect(first).toBe(second);
    expect(operation).toHaveBeenCalledTimes(1);
    finishOperation?.();
    await Promise.all([first, second, disconnect()]);
    expect(operation).toHaveBeenCalledTimes(1);
  });

  it('keeps client construction centralized and imports the explicit ESM client entry', () => {
    const sourceRoot = path.resolve(process.cwd(), 'src');
    const applicationFiles = listTypeScriptFiles(sourceRoot).filter(
      file =>
        !file.includes(`${path.sep}__tests__${path.sep}`) &&
        !file.includes(`${path.sep}generated${path.sep}`),
    );
    const sources = applicationFiles.map(file => ({
      file: path.relative(sourceRoot, file),
      contents: fs.readFileSync(file, 'utf8'),
    }));

    expect(
      sources
        .filter(({ contents }) => contents.includes('new PrismaClient('))
        .map(({ file }) => file),
    ).toEqual([path.join('config', 'database.ts')]);
    expect(
      sources.filter(({ contents }) =>
        /from ['\"]@prisma\/client['\"]/.test(contents),
      ),
    ).toEqual([]);

    const generatedClientImports = sources.flatMap(({ file, contents }) =>
      contents
        .split('\n')
        .filter(line => line.includes('generated/prisma'))
        .map(line => ({ file, line })),
    );
    expect(generatedClientImports.length).toBeGreaterThan(0);
    expect(
      generatedClientImports.filter(({ line }) =>
        !line.includes('generated/prisma/client.js'),
      ),
    ).toEqual([]);
  });
});
