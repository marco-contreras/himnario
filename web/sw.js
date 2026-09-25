'use strict';

// Desde Flutter 3.x el flutter_service_worker.js generado ya no guarda nada
// en caché (se da de baja solo), por eso la app registra este en su lugar
// desde web/flutter_bootstrap.js.
const CACHE = 'himnario-v1';

const ARCHIVOS_BASE = [
  './',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

// Recursos externos con URL versionada: si ya están en caché no cambian.
const HOSTS_EXTERNOS = ['fonts.gstatic.com', 'www.gstatic.com', 'cdn.jsdelivr.net'];

const ESPERA_RED_MS = 4000;

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.allSettled(ARCHIVOS_BASE.map((url) => cache.add(url)))
    )
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const nombres = await caches.keys();
      await Promise.all(
        nombres.filter((nombre) => nombre !== CACHE).map((nombre) => caches.delete(nombre))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin === self.location.origin) {
    event.respondWith(
      url.pathname.endsWith('.pdf') ? cacheYActualizar(event) : redPrimero(event)
    );
  } else if (HOSTS_EXTERNOS.includes(url.hostname)) {
    event.respondWith(cachePrimero(request));
  }
});

function descargarYGuardar(request) {
  return fetch(request).then(async (respuesta) => {
    if (respuesta.ok) {
      try {
        const cache = await caches.open(CACHE);
        await cache.put(request, respuesta.clone());
      } catch (e) {
        console.warn('No se pudo guardar en caché', request.url, e);
      }
    }
    return respuesta;
  });
}

// PDFs: se sirven desde la caché y se revisa en segundo plano si cambiaron,
// así una actualización del PDF llega sin tener que borrar nada.
async function cacheYActualizar(event) {
  const red = descargarYGuardar(event.request);
  event.waitUntil(red.catch(() => {}));

  const guardada = await caches.match(event.request);
  return guardada ?? red;
}

async function cachePrimero(request) {
  const guardada = await caches.match(request);
  return guardada ?? descargarYGuardar(request);
}

// App (index.html, main.dart.js, canvaskit...): la versión más nueva si hay
// red; si la red falla o tarda demasiado, la copia guardada.
async function redPrimero(event) {
  const request = event.request;
  const red = descargarYGuardar(request);
  event.waitUntil(red.catch(() => {}));

  try {
    return await Promise.race([
      red,
      new Promise((_, rechazar) =>
        setTimeout(() => rechazar(new Error('timeout')), ESPERA_RED_MS)
      ),
    ]);
  } catch (e) {
    const guardada =
      (await caches.match(request)) ??
      (request.mode === 'navigate' ? await caches.match('./') : undefined);
    return guardada ?? red;
  }
}
