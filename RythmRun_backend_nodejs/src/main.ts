import { startServer, stopServer } from './server.js';

const SHUTDOWN_GRACE_MS = 10_000;
let shutdown: Promise<void> | undefined;

try {
  const server = await startServer();

  const requestShutdown = (signal: NodeJS.Signals): void => {
    shutdown ??= (async () => {
      const forceCloseTimer = setTimeout(() => {
        server.closeAllConnections();
      }, SHUTDOWN_GRACE_MS);
      forceCloseTimer.unref();

      try {
        await stopServer(server);
        console.log(`Server stopped after ${signal}`);
      } catch (error: unknown) {
        const category = error instanceof Error ? error.name : 'UnknownError';
        console.error(`Server shutdown failed (${category})`);
        process.exitCode = 1;
      } finally {
        clearTimeout(forceCloseTimer);
      }
    })();
  };

  process.once('SIGINT', () => requestShutdown('SIGINT'));
  process.once('SIGTERM', () => requestShutdown('SIGTERM'));
} catch (error: unknown) {
  const category = error instanceof Error ? error.name : 'UnknownError';
  console.error(`Server startup failed (${category})`);
  process.exitCode = 1;
}
