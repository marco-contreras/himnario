{{flutter_js}}
{{flutter_build_config}}

// En la primera visita se espera a que web/sw.js controle la página para que
// main.dart.js, canvaskit y las fuentes pasen por él y queden en caché.
async function registrarServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  try {
    await navigator.serviceWorker.register('sw.js');
    if (!navigator.serviceWorker.controller) {
      await new Promise((resolve) => {
        navigator.serviceWorker.addEventListener('controllerchange', resolve, { once: true });
        setTimeout(resolve, 3000);
      });
    }
    if (window.matchMedia('(display-mode: standalone)').matches) {
      await navigator.storage?.persist?.();
    }
  } catch (e) {
    console.warn('No se pudo registrar el service worker', e);
  }
}

registrarServiceWorker().finally(() => _flutter.loader.load());
