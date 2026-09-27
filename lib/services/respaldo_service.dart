import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'actualizacion_service.dart';
import 'download_service.dart';
import 'red_web.dart';
import 'zip_simple.dart';

class ResultadoRestauracion {
  final int restauradas;

  /// Hojas del respaldo que venían dañadas y no se guardaron.
  final int danadas;

  /// Hojas del himnario que siguen sin estar en el dispositivo.
  final int faltantes;

  const ResultadoRestauracion(this.restauradas, this.danadas, this.faltantes);
}

/// Respaldo del himnario en un archivo .zip que queda fuera del navegador
/// (Descargas, o Archivos en iPad): si el navegador borra sus datos, se
/// restaura desde ahí sin internet. Adentro va `HIMNARIOS/<himnario>/` con
/// las hojas y su versiones.json.
class RespaldoService {
  static const String _carpeta = 'HIMNARIOS/${DownloadService.himnario}/';
  static const int _enParalelo = 8;
  static final RegExp _hoja = RegExp(r'(?:^|/)(\d+-\d+)\.webp$');

  static String nombreArchivo(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return 'HIMNARIOS-${DownloadService.himnario}-'
        '${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}.zip';
  }

  /// Arma el respaldo con las hojas guardadas en el dispositivo (sin usar
  /// internet) y lo descarga. Devuelve cuántas hojas faltaban; si falta
  /// alguna no se crea nada, porque el respaldo quedaría incompleto.
  static Future<int> guardar({
    required void Function(int hechas, int total) onProgreso,
  }) async {
    final List<String> rutas = await DownloadService.todasLasRutas();
    final List<bool> guardadas = await Future.wait(
        rutas.map((ruta) => RedWeb.estaGuardado(RedWeb.urlDeAsset(ruta))));
    final int faltantes = guardadas.where((guardada) => !guardada).length;
    if (faltantes > 0) return faltantes;

    final DateTime ahora = DateTime.now();
    final EscritorZip zip = EscritorZip(ahora);
    final List<web.Blob> partes = [];
    final Map<String, HojaVersion> hojas = {};

    // Se lee de a una: cada hoja pasa a la memoria del navegador y se suelta,
    // así los ~170 MB nunca están juntos en la memoria de la app.
    for (int i = 0; i < rutas.length; i++) {
      final Uint8List? datos =
          await RedWeb.leerGuardado(RedWeb.urlDeAsset(rutas[i]));
      if (datos == null) return 1; // se borró mientras se armaba el respaldo
      final String clave = DownloadService.claveDe(rutas[i]);
      partes
        ..add(RedWeb.aBlob(zip.cabecera('$_carpeta$clave.webp', datos)))
        ..add(RedWeb.aBlob(datos));
      hojas[clave] = HojaVersion(await RedWeb.huellaDe(datos), datos.length);
      onProgreso(i + 1, rutas.length);
    }

    final Uint8List versiones = utf8.encode(Manifiesto('', hojas).aJson());
    partes
      ..add(RedWeb.aBlob(zip.cabecera('${_carpeta}versiones.json', versiones)))
      ..add(RedWeb.aBlob(versiones))
      ..add(RedWeb.aBlob(zip.cierre()));
    RedWeb.descargarArchivo(partes, nombreArchivo(ahora), 'application/zip');
    return 0;
  }

  /// Guarda en el dispositivo las hojas de un respaldo. Solo toma las hojas
  /// que el himnario conoce y revisa cada una (CRC) antes de guardarla. Si el
  /// respaldo es más viejo que lo publicado, la próxima revisión con internet
  /// baja solo las hojas que cambiaron.
  static Future<ResultadoRestauracion> restaurar(
    web.File archivo, {
    required void Function(int hechas, int total) onProgreso,
  }) async {
    final int tamano = archivo.size;
    final IndiceZip? indice = buscarIndice(await RedWeb.leerTrozo(
        archivo, math.max(0, tamano - 65557), tamano));
    if (indice == null) {
      throw const FormatException('El archivo no es un respaldo .zip válido.');
    }
    final List<EntradaZip> entradas = leerIndice(await RedWeb.leerTrozo(
        archivo, indice.inicio, indice.inicio + indice.tamano));

    final Map<String, String> rutaPorClave = {
      for (final String ruta in await DownloadService.todasLasRutas())
        DownloadService.claveDe(ruta): ruta,
    };
    final Map<String, EntradaZip> porClave = {};
    for (final EntradaZip entrada in entradas) {
      final String? clave = _hoja.firstMatch(entrada.nombre)?[1];
      // Solo este himnario: se descartan hojas de otras carpetas de HIMNARIOS.
      final bool otroHimnario = entrada.nombre.contains('HIMNARIOS/') &&
          !entrada.nombre.contains(_carpeta);
      if (clave != null && rutaPorClave.containsKey(clave) && !otroHimnario) {
        porClave[clave] = entrada;
      }
    }
    if (porClave.isEmpty) {
      throw const FormatException(
          'El archivo no contiene hojas de este himnario.');
    }

    final Map<String, HojaVersion> restauradas = {};
    int danadas = 0;
    int hechas = 0;
    final List<String> claves = porClave.keys.toList();
    for (int i = 0; i < claves.length; i += _enParalelo) {
      await Future.wait(claves.skip(i).take(_enParalelo).map((clave) async {
        final Uint8List? datos = await _leerEntrada(archivo, porClave[clave]!);
        if (datos == null) {
          danadas++;
        } else {
          await RedWeb.guardar(
              RedWeb.urlDeAsset(rutaPorClave[clave]!), datos, 'image/webp');
          restauradas[clave] =
              HojaVersion(await RedWeb.huellaDe(datos), datos.length);
        }
        hechas++;
        onProgreso(hechas, claves.length);
      }));
    }

    final Manifiesto? local = await ActualizacionService.leerLocalGuardado();
    await ActualizacionService.guardarLocal(Manifiesto(
        local?.version ?? '', {...?local?.hojas, ...restauradas}));

    final List<bool> guardadas = await Future.wait(rutaPorClave.values
        .map((ruta) => RedWeb.estaGuardado(RedWeb.urlDeAsset(ruta))));
    final int faltantes = guardadas.where((guardada) => !guardada).length;
    if (faltantes == 0) {
      await DownloadService.marcarDescargaCompleta();
      await RedWeb.pedirAlmacenamientoPersistente();
    }
    return ResultadoRestauracion(restauradas.length, danadas, faltantes);
  }

  static Future<Uint8List?> _leerEntrada(
      web.File archivo, EntradaZip entrada) async {
    try {
      final int datos = inicioDatos(
          entrada,
          await RedWeb.leerTrozo(
              archivo, entrada.inicioCabecera, entrada.inicioCabecera + 30));
      final web.Blob trozo =
          archivo.slice(datos, datos + entrada.tamanoComprimido);
      final Uint8List contenido = switch (entrada.metodo) {
        0 => await RedWeb.leerTrozo(trozo, 0, entrada.tamanoComprimido),
        8 => await RedWeb.descomprimir(trozo),
        _ => Uint8List(0),
      };
      if (contenido.length != entrada.tamano || crc32(contenido) != entrada.crc) {
        return null;
      }
      return contenido;
    } catch (_) {
      return null;
    }
  }
}
