import dotenv from 'dotenv';
import { defineConfig, env } from 'prisma/config';

dotenv.config({ quiet: true });

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
    seed: 'npm run seed',
  },
  datasource: {
    url: env('DATABASE_URL'),
  },
});
