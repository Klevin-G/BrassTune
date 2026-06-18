import { defineConfig, devices } from 'playwright/test';

const backendCommand = process.platform === 'win32'
  ? 'cd ../backend && .venv\\Scripts\\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000'
  : 'cd ../backend && (.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 || python3 -m uvicorn app.main:app --host 127.0.0.1 --port 8000)';

export default defineConfig({
  testDir: './e2e',
  timeout: 45_000,
  workers: 1,
  expect: {
    timeout: 10_000,
  },
  reporter: [
    ['list'],
    ['html', { outputFolder: '../docs/release-readiness/playwright-report', open: 'never' }],
  ],
  use: {
    baseURL: 'http://127.0.0.1:5173',
    trace: 'retain-on-failure',
  },
  webServer: [
    {
      command: backendCommand,
      url: 'http://127.0.0.1:8000/api/health',
      reuseExistingServer: true,
      timeout: 30_000,
    },
    {
      command: 'npm run dev -- --host 127.0.0.1 --port 5173',
      url: 'http://127.0.0.1:5173',
      reuseExistingServer: true,
      timeout: 30_000,
      env: {
        VITE_API_BASE_URL: 'http://127.0.0.1:8000',
        VITE_WS_BASE_URL: 'ws://127.0.0.1:8000',
        VITE_SUPABASE_URL: '',
        VITE_SUPABASE_PUBLISHABLE_KEY: '',
      },
    },
  ],
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'mobile-chromium', use: { ...devices['Pixel 7'] } },
  ],
});
