import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defineConfig, devices } from 'playwright/test';

const startLocalServers = process.env.E2E_START_LOCAL_SERVERS !== '0';
const baseURL = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:5173';
const apiBaseURL = process.env.E2E_API_BASE_URL ?? 'http://127.0.0.1:8000';
const wsBaseURL = process.env.E2E_WS_BASE_URL ?? apiBaseURL.replace(/^http/, 'ws');
const ci = !!process.env.CI;
const defaultBackendPython = process.platform === 'win32'
  ? (existsSync('../backend/.venv/Scripts/python.exe') ? '.venv\\Scripts\\python.exe' : 'py -3')
  : (existsSync('../backend/.venv/bin/python') ? '.venv/bin/python' : 'python3');
const backendPython = process.env.E2E_BACKEND_PYTHON ?? defaultBackendPython;
const backendCommand = `cd ../backend && ${backendPython} -m uvicorn app.main:app --host 127.0.0.1 --port 8000`;
const backendDatabaseURL = process.env.E2E_BACKEND_DATABASE_URL ?? `sqlite:///${join(tmpdir(), `brasstune-e2e-${process.pid}.db`)}`;

export default defineConfig({
  testDir: './e2e',
  timeout: 45_000,
  globalTimeout: ci ? 12 * 60_000 : undefined,
  workers: 1,
  forbidOnly: ci,
  expect: {
    timeout: 10_000,
  },
  reporter: ci ? [
    ['list'],
    ['blob', { outputDir: 'test-results/blob-report' }],
  ] : [
    ['list'],
    ['html', { outputFolder: '../docs/release-readiness/playwright-report', open: 'never' }],
  ],
  use: {
    baseURL,
    trace: 'retain-on-failure',
  },
  webServer: startLocalServers ? [
    {
      command: backendCommand,
      url: `${apiBaseURL}/api/health`,
      reuseExistingServer: !ci,
      timeout: 30_000,
      env: {
        APP_ENV: 'local',
        BRASSTUNE_AUTH_MODE: 'disabled',
        BRASSTUNE_DATABASE_URL: backendDatabaseURL,
        FRONTEND_ORIGIN: baseURL,
        CORS_ALLOWED_ORIGINS: `${baseURL},http://localhost:5173,http://127.0.0.1:5173`,
      },
    },
    {
      command: 'npm run dev -- --host 127.0.0.1 --port 5173',
      url: baseURL,
      reuseExistingServer: !ci,
      timeout: 30_000,
      env: {
        VITE_API_BASE_URL: apiBaseURL,
        VITE_WS_BASE_URL: wsBaseURL,
        VITE_SUPABASE_URL: '',
        VITE_SUPABASE_PUBLISHABLE_KEY: '',
        VITE_ENABLE_INTERNAL_TOOLS: 'false',
      },
    },
  ] : undefined,
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'mobile-chromium', use: { ...devices['Pixel 7'] } },
    { name: 'mobile-webkit', use: { ...devices['iPhone 15'] } },
  ],
});
