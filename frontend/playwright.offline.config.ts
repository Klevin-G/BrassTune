import { defineConfig, devices } from 'playwright/test';

export default defineConfig({
  testDir: './e2e',
  testMatch: 'offline-pwa.spec.ts',
  timeout: 45_000,
  workers: 1,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'npm run preview -- --host 127.0.0.1 --port 4173',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: false,
    timeout: 30_000,
  },
  projects: [{ name: 'chromium-pwa', use: { ...devices['Desktop Chrome'] } }],
});
