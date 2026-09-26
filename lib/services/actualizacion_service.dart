import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'download_service.dart';
import 'red_web.dart';

/// Huella y tamaño de una hoja, tal como los calcula
/// `tool/generar_versiones.py`.
class HojaVersion {
  final String hash;
  final int bytes;

  const HojaVersion(this.hash, this.bytes);
}

/// Contenido de `versiones.json`: la versión general y la de cada hoja
/// ("34-1" es el himno 34, página 1).
class Manifiesto {
  final String version;
  final Map<String, HojaVersion> hojas;

  const Manifiesto(this.version, this.hojas);

  factory Manifiesto.desdeJson(String texto) {
    final Map<String, dynamic> datos = jsonDecode(texto) as Map<String, dynamic>;
    final Map<String, dynamic> archivos =
        datos['archivos'] as Map<String, dynamic>;
    return Manifiesto(datos['version'] as String, {
      for (final MapEntry<String, dynamic> hoja in archivos.entries)
        hoja.key: HojaVersion(
          hoja.value['hash'] as String,
          hoja.value['bytes'] as int,
        ),
    });
  }

  String aJson() => jsonEncode({
        'version': version,
        'archivos': {
          for (final MapEntry<String, HojaVersion> hoja in hojas.entries)
            hoja.key: {'hash': hoja.value.hash, 'bytes': hoja.value.bytes},
        },
      });
}

class ActualizacionPendiente {
  final Manifiesto remoto;
  final Manifiesto local;

  /// Hojas por descargar: las nuevas o mejoradas y las que faltan en el
  /// dispositivo.
  final List<String> hojas;
  final int faltantes;
  final List<String> eliminadas;

  const ActualizacionPendiente({
    required this.remoto,
    required this.local,
    required this.hojas,
    required this.faltantes,
    required this.eliminadas,
  });

  int get mejoradas => hojas.length - faltantes;

  int get bytes =>
      hojas.fold(0, (total, clave) => total + remoto.hojas[clave]!.bytes);
}

enum EstadoRevision { sinConexion, alDia, pendiente }

class Revision {
  final EstadoRevision estado;
  final ActualizacionPendiente? pendiente;

  const Revision(this.estado, [this.pendiente]);
}

class ActualizacionService {
  static const String _keyManifiestoLocal =
      'manifiesto_${DownloadService.himnario}';
  static const int _descargasSimultaneas = 4;

  static Future<Manifiesto?> leerRemoto() async {
    final String? texto = await RedWeb.leerSinCache(
        RedWeb.urlDeAsset(DownloadService.rutaManifiesto));
    if (texto == null) return null;
    try {
      return Manifiesto.desdeJson(texto);
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarLocal(Manifiesto manifiesto) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyManifiestoLocal, manifiesto.aJson());
  }

  // Sin registro guardado (por ejemplo, quien descargó antes de que existiera
  // este sistema) se calcula la huella de las hojas que el dispositivo tiene
  // guardadas. Se guarda enseguida para no repetir el cálculo.
  static Future<Manifiesto> _leerLocal(Manifiesto remoto) async {
    final prefs = await SharedPreferences.getInstance();
    final String? guardado = prefs.getString(_keyManifiestoLocal);
    if (guardado != null) return Manifiesto.desdeJson(guardado);

    final Map<String, HojaVersion> hojas = {};
    final List<String> claves = remoto.hojas.keys.toList();
    for (int i = 0; i < claves.length; i += _descargasSimultaneas) {
      final List<String> lote =
          claves.skip(i).take(_descargasSimultaneas).toList();
      final List<String?> huellas = await Future.wait(
          lote.map((clave) => RedWeb.huellaGuardada(_url(clave))));
      for (int j = 0; j < lote.length; j++) {
        final String? huella = huellas[j];
        if (huella != null) hojas[lote[j]] = HojaVersion(huella, 0);
      }
    }
    final Manifiesto reconstruido = Manifiesto('', hojas);
    await guardarLocal(reconstruido);
    return reconstruido;
  }

  static String _url(String clave) =>
      RedWeb.urlDeAsset(DownloadService.rutaPagina(clave));

  /// Compara las hojas del dispositivo con las publicadas y revisa que no
  /// falte ninguna de las descargadas.
  static Future<Revision> revisar() async {
    final Manifiesto? remoto = await leerRemoto();
    if (remoto == null) return const Revision(EstadoRevision.sinConexion);
    final Manifiesto local = await _leerLocal(remoto);

    final Set<String> cambiadas = {
      for (final MapEntry<String, HojaVersion> hoja in remoto.hojas.entries)
        if (local.hojas[hoja.key]?.hash != hoja.value.hash) hoja.key,
    };
    final List<String> eliminadas = [
      for (final String clave in local.hojas.keys)
        if (!remoto.hojas.containsKey(clave)) clave,
    ];

    if (!await DownloadService.estanArchivosDescargados()) {
      // Sin la descarga completa solo se borran las hojas viejas que se hayan
      // guardado al verlas; las nuevas bajan la próxima vez que se abran.
      await _borrar([...cambiadas, ...eliminadas]);
      await guardarLocal(remoto);
      return const Revision(EstadoRevision.alDia);
    }

    // El navegador puede borrar datos si el dispositivo se queda sin espacio.
    final List<String> revisadas = [
      for (final String clave in remoto.hojas.keys)
        if (!cambiadas.contains(clave)) clave,
    ];
    final List<bool> guardadas = await Future.wait(
        revisadas.map((clave) => RedWeb.estaGuardado(_url(clave))));
    final List<String> faltantes = [
      for (int i = 0; i < revisadas.length; i++)
        if (!guardadas[i]) revisadas[i],
    ];

    if (cambiadas.isEmpty && faltantes.isEmpty) {
      await _borrar(eliminadas);
      if (local.version != remoto.version) await guardarLocal(remoto);
      return const Revision(EstadoRevision.alDia);
    }
    return Revision(
      EstadoRevision.pendiente,
      ActualizacionPendiente(
        remoto: remoto,
        local: local,
        hojas: [...cambiadas, ...faltantes],
        faltantes: faltantes.length,
        eliminadas: eliminadas,
      ),
    );
  }

  /// Descarga las hojas pendientes. Devuelve cuántas fallaron (0 = todo bien).
  static Future<int> aplicar(
    ActualizacionPendiente pendiente, {
    required void Function(int hechas, int total) onProgreso,
  }) async {
    final Map<String, HojaVersion> descargadas = Map.of(pendiente.local.hojas);
    final List<String> hojas = pendiente.hojas;
    int hechas = 0;
    int fallidas = 0;

    for (int i = 0; i < hojas.length; i += _descargasSimultaneas) {
      await Future.wait(
          hojas.skip(i).take(_descargasSimultaneas).map((clave) async {
        if (await RedWeb.descargarVersionNueva(_url(clave))) {
          descargadas[clave] = pendiente.remoto.hojas[clave]!;
        } else {
          fallidas++;
        }
        hechas++;
        onProgreso(hechas, hojas.length);
      }));
      // Se guarda el avance: si se corta, la próxima vez solo baja lo que faltó.
      await guardarLocal(Manifiesto(pendiente.local.version, descargadas));
    }

    if (fallidas > 0) return fallidas;
    await _borrar(pendiente.eliminadas);
    await guardarLocal(pendiente.remoto);
    return 0;
  }

  static Future<void> _borrar(Iterable<String> claves) =>
      Future.wait(claves.map((clave) => RedWeb.borrarGuardado(_url(clave))));
}
