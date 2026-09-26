import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/himnos_repository.dart';
import '../models/himno.dart';
import 'red_web.dart';

/// Cada página de un himno es una imagen WebP dentro de la app
/// (`assets/HIMNARIOS/IBEFI/<numero>-<pagina>.webp`). En web, `rootBundle.load`
/// hace una petición que intercepta `web/sw.js` y guarda en la caché del
/// navegador, así que "descargar" es pedir todas las páginas una vez para que
/// queden disponibles sin conexión.
class DownloadService {
  // Cambió al pasar de PDF a WebP: quien descargó los PDF tiene que volver a
  // descargar, porque las imágenes no están en su caché.
  static const String _keyDescargaCompleta = 'descarga_webp_completa';
  static const String himnario = 'IBEFI';
  static const String _carpetaAssets = 'assets/HIMNARIOS/$himnario/';
  // Con 8 a la vez la descarga fue ~55% más rápida que con 4 (medido contra
  // GitHub Pages): el límite era la espera de cada petición, no la conexión.
  static const int descargasSimultaneas = 8;
  static final RegExp _nombrePagina = RegExp(r'^(\d+)-(\d+)\.webp$');

  static Future<Map<int, List<String>>>? _paginasPorHimno;

  /// Ruta del asset de una hoja: "34-1" es el himno 34, página 1.
  static String rutaPagina(String clave) => '$_carpetaAssets$clave.webp';

  static String _clave(String ruta) =>
      ruta.substring(_carpetaAssets.length, ruta.length - '.webp'.length);

  /// Manifiesto del himnario, generado por `tool/generar_versiones.py`.
  static const String rutaManifiesto = '${_carpetaAssets}versiones.json';

  static Future<bool> estanArchivosDescargados() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDescargaCompleta) ?? false;
  }

  /// Devuelve cuántos himnos no se pudieron descargar (0 = todo bien).
  /// Con [huellasPublicadas] ("34-1" → huella), las hojas que ya están
  /// guardadas e iguales a las publicadas no se vuelven a bajar.
  static Future<int> descargarTodosLosHimnos({
    required void Function(int completados, int total) onProgreso,
    Map<String, String>? huellasPublicadas,
  }) async {
    final himnos = HimnosRepository.todosLosHimnos;
    int completados = 0;
    int fallidos = 0;

    for (int i = 0; i < himnos.length; i += descargasSimultaneas) {
      final lote = himnos.skip(i).take(descargasSimultaneas);
      await Future.wait(lote.map((himno) async {
        try {
          final rutas = await paginasDe(himno);
          if (rutas.isEmpty) {
            throw StateError('No hay páginas para el himno ${himno.numero}');
          }
          for (final ruta in rutas) {
            final String url = RedWeb.urlDeAsset(ruta);
            final String? publicada = huellasPublicadas?[_clave(ruta)];
            if (publicada != null &&
                await RedWeb.huellaGuardada(url) == publicada) {
              continue;
            }
            if (!await RedWeb.descargarVersionNueva(url)) {
              throw StateError('No se pudo descargar $ruta');
            }
          }
        } catch (e) {
          fallidos++;
          debugPrint('Error al descargar himno ${himno.numero}: $e');
        }
        completados++;
        onProgreso(completados, himnos.length);
      }));
    }

    if (fallidos == 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDescargaCompleta, true);
    }
    return fallidos;
  }

  /// Rutas de las páginas del himno, en orden.
  static Future<List<String>> paginasDe(Himno himno) async {
    final Future<Map<int, List<String>>> lectura =
        _paginasPorHimno ??= _leerPaginas();
    try {
      return (await lectura)[himno.numero] ?? const [];
    } catch (_) {
      // Sin esto, un fallo (por ejemplo, sin internet la primera vez) quedaría
      // guardado y no se volvería a intentar.
      if (identical(_paginasPorHimno, lectura)) _paginasPorHimno = null;
      rethrow;
    }
  }

  static Future<Map<int, List<String>>> _leerPaginas() async {
    final AssetManifest manifiesto =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    final Map<int, Map<int, String>> encontradas = {};
    for (final String ruta in manifiesto.listAssets()) {
      if (!ruta.startsWith(_carpetaAssets)) continue;
      final RegExpMatch? partes =
          _nombrePagina.firstMatch(ruta.substring(_carpetaAssets.length));
      if (partes == null) continue;
      encontradas.putIfAbsent(int.parse(partes[1]!), () => {})[
          int.parse(partes[2]!)] = ruta;
    }
    return encontradas.map((numero, paginas) {
      final List<int> orden = paginas.keys.toList()..sort();
      return MapEntry(numero, [for (final p in orden) paginas[p]!]);
    });
  }

  static Future<Uint8List> obtenerPagina(String ruta) async {
    final ByteData datos = await rootBundle.load(ruta);
    return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
  }
}
