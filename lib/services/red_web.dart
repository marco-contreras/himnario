import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// Acceso directo a la red y a la caché del navegador. La app solo se publica
/// como PWA, así que puede usar las APIs web sin alternativa para móvil.
class RedWeb {
  // Tiene que coincidir con CACHE en web/sw.js.
  static const String _cache = 'himnario-v1';

  /// La misma URL que usa `rootBundle.load` para ese asset.
  static String urlDeAsset(String ruta) =>
      ui_web.assetManager.getAssetUrl(ruta);

  /// Lee un archivo de texto sin pasar por ninguna caché. Devuelve null si no
  /// hay internet o el archivo no existe.
  static Future<String?> leerSinCache(String url) async {
    try {
      final web.Response respuesta = await web.window
          .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
          .toDart;
      if (!respuesta.ok) return null;
      return (await respuesta.text().toDart).toDart;
    } catch (_) {
      return null;
    }
  }

  /// Baja la versión más nueva del archivo desde el servidor. El service
  /// worker la guarda en su caché en lugar de la que hubiera.
  static Future<bool> descargarVersionNueva(String url) async {
    try {
      final web.Response respuesta = await web.window
          .fetch(url.toJS, web.RequestInit(cache: 'reload'))
          .toDart;
      if (!respuesta.ok) return false;
      await respuesta.arrayBuffer().toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Huella de la copia guardada en el dispositivo, calculada igual que en
  /// `tool/generar_versiones.py` (SHA-256, 12 caracteres). Null si no está.
  static Future<String?> huellaGuardada(String url) async {
    try {
      final web.Response? respuesta =
          await web.window.caches.match(url.toJS).toDart;
      if (respuesta == null) return null;
      final JSArrayBuffer datos = await respuesta.arrayBuffer().toDart;
      final JSAny? resumen = await web.window.crypto.subtle
          .digest('SHA-256'.toJS, datos)
          .toDart;
      final List<int> bytes = (resumen as JSArrayBuffer).toDart.asUint8List();
      return bytes
          .take(6)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> estaGuardado(String url) async {
    try {
      return await web.window.caches.match(url.toJS).toDart != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> borrarGuardado(String url) async {
    try {
      final web.Cache cache = await web.window.caches.open(_cache).toDart;
      await cache.delete(url.toJS).toDart;
    } catch (_) {}
  }
}
