import 'package:shared_preferences/shared_preferences.dart';

class SyncService {
  static const String _keyUltimaSincronizacion = 'ultima_sincronizacion';

  /// Comprueba si el token ha vencido (vence cada Domingo a las 00:00 AM)
  static Future<bool> necesitaActualizar() async {
    final prefs = await SharedPreferences.getInstance();
    final String? fechaStr = prefs.getString(_keyUltimaSincronizacion);

    if (fechaStr == null) {
      // Primera vez que entra a la app, necesita descargar
      return true;
    }

    final DateTime ultimaFecha = DateTime.parse(fechaStr);
    final DateTime ahora = DateTime.now();

    // Calcular el domingo más reciente
    final DateTime domingoMasCercano = ahora.subtract(Duration(days: ahora.weekday % 7));
    final DateTime domingoInicio = DateTime(
      domingoMasCercano.year,
      domingoMasCercano.month,
      domingoMasCercano.day,
      0, 0, 0,
    );

    // Si la última sincronización fue antes del último domingo a las 00:00 AM, el token venció
    return ultimaFecha.isBefore(domingoInicio);
  }

  /// Guarda la fecha actual como la última sincronización exitosa
  static Future<void> marcarSincronizado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUltimaSincronizacion, DateTime.now().toIso8601String());
  }
}