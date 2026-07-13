import { PrismaPg } from '@prisma/adapter-pg';
import type { PoolConfig } from 'pg';

import { PrismaClient } from '../generated/prisma/client.js';

export const POSTGRES_POOL_MAX = 10;
export const POSTGRES_CONNECT_TIMEOUT_MS = 5_000;
export const POSTGRES_IDLE_TIMEOUT_MS = 300_000;

export interface DatabaseRuntime {
  client: PrismaClient;
  disconnect: () => Promise<void>;
}

export function buildPostgresPoolConfig(databaseUrl: string): PoolConfig {
  if (databaseUrl.trim().length === 0) {
    throw new Error('DATABASE_URL must not be empty');
  }

  return {
    connectionString: databaseUrl,
    max: POSTGRES_POOL_MAX,
    connectionTimeoutMillis: POSTGRES_CONNECT_TIMEOUT_MS,
    idleTimeoutMillis: POSTGRES_IDLE_TIMEOUT_MS,
    maxLifetimeSeconds: 0,
  };
}

export function getPostgresSchema(databaseUrl: string): string | undefined {
  const schema = new URL(databaseUrl).searchParams.get('schema');
  if (schema === null || schema.trim().length === 0) {
    return undefined;
  }
  return schema;
}

export function onceAsync(operation: () => Promise<void>): () => Promise<void> {
  let result: Promise<void> | undefined;
  return () => {
    result ??= operation();
    return result;
  };
}

function logDriverError(scope: string, error: Error): void {
  console.error(`${scope} (${error.name})`);
}

export function createDatabase(databaseUrl: string): DatabaseRuntime {
  const adapter = new PrismaPg(buildPostgresPoolConfig(databaseUrl), {
    schema: getPostgresSchema(databaseUrl),
    onPoolError: error => logDriverError('PostgreSQL pool error', error),
    onConnectionError: error =>
      logDriverError('PostgreSQL connection error', error),
  });
  const client = new PrismaClient({ adapter });

  return {
    client,
    disconnect: onceAsync(() => client.$disconnect()),
  };
}
