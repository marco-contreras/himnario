import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Definida en web/index.html: lanza el aviso de instalación del navegador.
@JS('himnarioInstalar')
external JSPromise<JSString> _himnarioInstalar();

enum ResultadoInstalacion { aceptada, rechazada, noDisponible }

class InstalacionWeb {
  /// True cuando la app se está usando ya instalada (su propia ventana).
  static bool get estaInstalada =>
      web.window.matchMedia('(display-mode: standalone)').matches;

  /// Abre el aviso de instalación del navegador. "noDisponible" si el
  /// navegador no lo ofrece (iPhone/iPad, Firefox, navegador de Xiaomi) o la
  /// app ya está instalada.
  static Future<ResultadoInstalacion> instalar() async {
    try {
      final String resultado = (await _himnarioInstalar().toDart).toDart;
      return switch (resultado) {
        'accepted' => ResultadoInstalacion.aceptada,
        'dismissed' => ResultadoInstalacion.rechazada,
        _ => ResultadoInstalacion.noDisponible,
      };
    } catch (_) {
      return ResultadoInstalacion.noDisponible;
    }
  }
}
