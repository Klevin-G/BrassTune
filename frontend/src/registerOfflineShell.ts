export function registerOfflineShell(): void {
  if (!import.meta.env.PROD || !('serviceWorker' in navigator)) return;
  window.addEventListener('load', () => {
    void navigator.serviceWorker.register('/sw.js').catch(() => {
      // Offline support is optional; online practice should continue normally.
    });
  }, { once: true });
}
