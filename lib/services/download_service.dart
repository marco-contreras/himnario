import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/himnos_repository.dart';
import '../models/himno.dart';

/// Los PDF viajan dentro de la app como assets. En web, `rootBundle.load`
/// hace una petición que intercepta `web/sw.js` y guarda en la caché del
/// navegador, así que "descargar" es pedir los 270 una vez para que queden
/// disponibles sin conexión.
class DownloadService {
  static const String _keyDescargaCompleta = 'descarga_inicial_completa';
  static const String _carpetaAssets = 'assets/HIMNARIOS/IBEFI';
  static const int _descargasSimultaneas = 4;

  static Future<bool> estanArchivosDescargados() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDescargaCompleta) ?? false;
  }

  /// Devuelve cuántos himnos no se pudieron descargar (0 = todo bien).
  static Future<int> descargarTodosLosHimnos({
    required void Function(int completados, int total) onProgreso,
  }) async {
    final himnos = HimnosRepository.todosLosHimnos;
    int completados = 0;
    int fallidos = 0;

    for (int i = 0; i < himnos.length; i += _descargasSimultaneas) {
      final lote = himnos.skip(i).take(_descargasSimultaneas);
      await Future.wait(lote.map((himno) async {
        try {
          await obtenerPdf(himno);
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

  static Future<Uint8List> obtenerPdf(Himno himno) async {
    final ByteData datos =
        await rootBundle.load('$_carpetaAssets/${himno.nombreArchivo}');
    return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
  }
}
