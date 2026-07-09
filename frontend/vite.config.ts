import { defineConfig } from 'vitest/config';
import { loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig(({ command, mode }) => {
  // Surface missing hosted API/WS bases at build time so a deployed app can never
  // silently fall back to localhost or same-origin. The runtime guard in
  // runtimeConfig.ts/client.ts is the enforced protection; this is a deploy safety net.
  // Hard-fail only during an actual hosted deploy build (Vercel sets process.env.VERCEL);
  // CI test builds and local `npm run build` (which intentionally omit VITE_* vars) only warn.
  if (command === 'build' && mode === 'production') {
    const env = loadEnv(mode, process.cwd(), 'VITE_');
    const missing = ['VITE_API_BASE_URL', 'VITE_WS_BASE_URL'].filter((key) => !env[key]?.trim());
    if (missing.length > 0) {
      const message = `Hosted config check: ${missing.join(' and ')} not set. The deployed app must define these so it never falls back to localhost or same-origin.`;
      if (process.env.VERCEL || process.env.BRASSTUNE_ENFORCE_HOSTED_ENV) {
        throw new Error(`Production deploy blocked — ${message}`);
      }
      console.warn(`[vite] WARNING — ${message} (non-fatal for CI/local builds)`);
    }
  }

  return {
    plugins: [react()],
    test: {
      exclude: ['e2e/**', 'node_modules/**', 'dist/**'],
    },
    server: {
      port: 5173,
      proxy: {
        '/api': 'http://127.0.0.1:8000',
        '/ws': {
          target: 'ws://127.0.0.1:8000',
          ws: true,
        },
      },
    },
  };
});
