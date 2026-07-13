import { createDefaultEsmPreset } from 'ts-jest';

const esmPreset = createDefaultEsmPreset({
  tsconfig: 'tsconfig.test.json',
});

export default {
  ...esmPreset,
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.test.ts'],
  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },
  setupFilesAfterEnv: ['<rootDir>/src/__tests__/setup.ts'],
};
