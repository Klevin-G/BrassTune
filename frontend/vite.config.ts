import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

const fullGitSha = /^[0-9a-f]{40}$/i;

export function resolveBuildRevision(environment: Record<string, string | undefined>) {
  const candidates = [
    ['BRASSTUNE_FRONTEND_BUILD_SHA', environment.BRASSTUNE_FRONTEND_BUILD_SHA],
    ['VERCEL_GIT_COMMIT_SHA', environment.VERCEL_GIT_COMMIT_SHA],
    ['GITHUB_SHA', environment.GITHUB_SHA],
  ] as const;
  const selected = candidates.find(([, value]) => value?.trim());
  if (!selected) return 'unknown';

  const [source, rawRevision] = selected;
  const revision = rawRevision!.trim();
  if (!fullGitSha.test(revision)) {
    throw new Error(`${source} must be a full 40-character Git commit SHA.`);
  }
  return revision.toLowerCase();
}

const buildRevision = resolveBuildRevision(process.env);

// The deployed app serves the backend same-origin under /api via the vercel.json
// service rewrite, so VITE_API_BASE_URL/VITE_WS_BASE_URL are optional (set them
// only to point the frontend at a separately hosted backend). runtimeConfig.ts
// still hard-fails at runtime on an unknown, unconfigured production origin.
export default defineConfig({
  define: {
    __BRASSTUNE_BUILD_REVISION__: JSON.stringify(buildRevision),
  },
  plugins: [
    react(),
    VitePWA({
      strategies: 'generateSW',
      injectRegister: null,
      manifest: false,
      registerType: 'autoUpdate',
      workbox: {
        cleanupOutdatedCaches: true,
        clientsClaim: true,
        skipWaiting: true,
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api(?:\/|$)/, /^\/ws(?:\/|$)/],
        globPatterns: ['**/*.{html,js,mjs,css,svg,webmanifest}'],
        maximumFileSizeToCacheInBytes: 3_000_000,
      },
    }),
  ],
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
});
