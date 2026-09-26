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
const HOSTS_EXTERNOS = ['fonts.gstatic.com', 'www.gstatic.com'];

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
      await borrarPdfViejos();
      await self.clients.claim();
    })()
  );
});

// Los himnos pasaron de PDF a WebP: se borran solo los PDF (~400 MB) y no la
// caché entera, porque ahí también está la app que se necesita sin conexión.
async function borrarPdfViejos() {
  const cache = await caches.open(CACHE);
  for (const request of await cache.keys()) {
    if (new URL(request.url).pathname.endsWith('.pdf')) await cache.delete(request);
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  // 'no-store' es versiones.json: siempre de la red, nunca una copia vieja.
  if (request.method !== 'GET' || request.cache === 'no-store') return;

  const url = new URL(request.url);
  if (url.origin === self.location.origin) {
    if (url.pathname.includes('/assets/HIMNARIOS/')) {
      // Las hojas no cambian salvo que la app pida la versión nueva
      // ('reload'), cuando versiones.json indica que cambió.
      event.respondWith(
        request.cache === 'reload' ? descargarYGuardar(request) : cachePrimero(request)
      );
    } else {
      event.respondWith(redPrimero(event));
    }
  } else if (HOSTS_EXTERNOS.includes(url.hostname)) {
    event.respondWith(cachePrimero(request));
  }
});

function descargarYGuardar(request, opciones) {
  return fetch(request, opciones).then(async (respuesta) => {
    if (respuesta.ok) {
      try {
        const cache = await caches.open(CACHE);
        const etag = respuesta.headers.get('etag');
        const guardada = etag ? await cache.match(request) : undefined;
        // Si el servidor dice que no cambió no se reescribe: main.dart.js y
        // canvaskit pesan ~8 MB y se revisan cada vez que se abre la app.
        if (!guardada || guardada.headers.get('etag') !== etag) {
          await cache.put(request, respuesta.clone());
        }
      } catch (e) {
        console.warn('No se pudo guardar en caché', request.url, e);
      }
    }
    return respuesta;
  });
}

async function cachePrimero(request) {
  const guardada = await caches.match(request);
  return guardada ?? descargarYGuardar(request);
}

// App (index.html, main.dart.js, canvaskit...): la versión más nueva si hay
// red; si la red falla o tarda demasiado, la copia guardada. 'no-cache' salta
// la caché HTTP de GitHub Pages (10 minutos): siempre le pregunta al servidor
// si cambió, y si no cambió la respuesta es mínima.
async function redPrimero(event) {
  const request = event.request;
  const red = descargarYGuardar(request, { cache: 'no-cache' });
  event.waitUntil(red.catch(() => {}));

  try {
    return sinReusoEnMemoria(await Promise.race([
      red,
      new Promise((_, rechazar) =>
        setTimeout(() => rechazar(new Error('timeout')), ESPERA_RED_MS)
      ),
    ]));
  } catch (e) {
    const guardada =
      (await caches.match(request)) ??
      (request.mode === 'navigate' ? await caches.match('./') : undefined);
    return sinReusoEnMemoria(guardada ?? (await red));
  }
}

// Chrome guarda en memoria los scripts ya cargados (main.dart.js, canvaskit.js)
// y al recargar los reutiliza sin pasar por aquí mientras el Cache-Control de
// GitHub Pages (10 minutos) diga que siguen frescos: "Actualizar" recargaba la
// versión vieja. Con no-cache tiene que volver a pedírselos a este worker.
function sinReusoEnMemoria(respuesta) {
  if (!respuesta.ok) return respuesta;
  const encabezados = new Headers(respuesta.headers);
  encabezados.set('Cache-Control', 'no-cache');
  return new Response(respuesta.body, {
    status: respuesta.status,
    statusText: respuesta.statusText,
    headers: encabezados,
  });
}
