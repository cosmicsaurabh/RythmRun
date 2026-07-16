import assert from 'node:assert/strict';

const watchdog = setTimeout(() => {
  console.error('Built ESM runtime smoke exceeded 15 seconds.');
  process.exit(1);
}, 15_000);

Object.assign(process.env, {
  DATABASE_URL: 'postgresql://ci:ci@127.0.0.1:1/rythmrun_ci?schema=public',
  GOOGLE_SERVER_CLIENT_ID: 'runtime-smoke.apps.googleusercontent.com',
  JWT_SECRET: 'runtime-smoke-access-secret-0000000000000001',
  REFRESH_TOKEN_SECRET: 'runtime-smoke-refresh-secret-000000000000001',
  R2_ACCOUNT_ID: 'runtime-smoke-account',
  R2_ACCESS_KEY_ID: 'runtime-smoke-access-key',
  R2_SECRET_ACCESS_KEY: 'runtime-smoke-secret-key',
  R2_BUCKET_AVATARS: 'runtime-smoke-avatars',
  R2_BUCKET_ACTIVITY_IMAGES: 'runtime-smoke-activity-images',
  R2_PUBLIC_URL: 'https://runtime-smoke.example.com',
  NODE_ENV: 'production',
});

let server;
let stopServer;

try {
  const runtime = await import('../dist/server.js');
  stopServer = runtime.stopServer;
  const { startServer } = runtime;
  server = await startServer({ host: '127.0.0.1', port: 0 });
  const address = server.address();
  assert(address && typeof address === 'object');
  const origin = `http://127.0.0.1:${address.port}`;

  const healthResponse = await fetch(`${origin}/health`, {
    signal: AbortSignal.timeout(5_000),
  });
  assert.equal(healthResponse.status, 200);
  const healthBody = await healthResponse.json();
  assert.equal(healthBody.status, 'ok');

  const protectedResponse = await fetch(`${origin}/api/activities`, {
    signal: AbortSignal.timeout(5_000),
  });
  assert.equal(protectedResponse.status, 401);
} finally {
  if (server !== undefined && stopServer !== undefined) {
    await stopServer(server);
  }
  clearTimeout(watchdog);
}

console.log('Built ESM runtime smoke passed.');
