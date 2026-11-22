export function registerOfflineShell({ nativeRuntime = false }: { nativeRuntime?: boolean } = {}): void {
  // Capacitor already packages the built Vite assets. A service worker inside
  // its WebView adds a second update/cache authority and can leave native users
  // running stale bundles after `cap sync`.
  if (nativeRuntime) return;
  if (!import.meta.env.PROD || !('serviceWorker' in navigator)) return;
  window.addEventListener('load', () => {
    void navigator.serviceWorker.register('/sw.js').catch(() => {
      // Offline support is optional; online practice should continue normally.
    });
  }, { once: true });
}
