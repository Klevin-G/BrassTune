const CACHE_NAME = 'brasstune-shell-v1';
const SHELL = ['/', '/index.html', '/theme-init.js', '/manifest.webmanifest'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || url.pathname.startsWith('/api') || url.pathname.startsWith('/ws')) return;
  if (['audio', 'video'].includes(request.destination)) return;

  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).then((response) => response.ok ? response : Promise.reject(new Error('navigation failed'))).catch(() => caches.match('/index.html')));
    return;
  }

  if (!['script', 'style', 'font', 'image', 'manifest'].includes(request.destination)) return;
  event.respondWith(caches.match(request).then((cached) => cached || fetch(request).then((response) => {
    if (response.ok && response.type === 'basic') {
      const copy = response.clone();
      void caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
    }
    return response;
  })));
});
