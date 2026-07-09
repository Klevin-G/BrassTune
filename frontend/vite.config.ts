import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

// The deployed app serves the backend same-origin under /api via the vercel.json
// service rewrite, so VITE_API_BASE_URL/VITE_WS_BASE_URL are optional (set them
// only to point the frontend at a separately hosted backend). runtimeConfig.ts
// still hard-fails at runtime on an unknown, unconfigured production origin.
export default defineConfig({
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
});
