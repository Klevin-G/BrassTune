const oldWorkboxPrecacheCaches = /^(workbox-precache|brasstune-precache)/;
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil((async () => {
  const names = await caches.keys();
  await Promise.all(names.filter((name) => oldWorkboxPrecacheCaches.test(name)).map((name) => caches.delete(name)));
  await self.registration.unregister();
})()));
