import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../services/download_service.dart';
import '../services/red_web.dart';
import '../services/respaldo_service.dart';

/// Guardar y restaurar el respaldo, con su diálogo de progreso. Se usa desde
/// el menú y desde la pantalla de bienvenida.
class RespaldoUi {
  static Future<void> guardar(BuildContext context) async {
    final ScaffoldMessengerState mensajes = ScaffoldMessenger.of(context);
    if (!await DownloadService.estanArchivosDescargados()) {
      mensajes.showSnackBar(const SnackBar(
          content: Text(
              'Primero descarga el himnario completo para poder respaldarlo.')));
      return;
    }
    if (!context.mounted) return;
    final int faltantes = await _conProgreso(
      context,
      'Preparando respaldo',
      (onProgreso) => RespaldoService.guardar(onProgreso: onProgreso),
    );
    mensajes.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(faltantes == 0
          ? 'Respaldo listo: ${RespaldoService.nombreArchivo(DateTime.now())}. '
              'Consérvalo, sirve para restaurar el himnario sin internet.'
          : 'Faltan $faltantes hojas en este dispositivo. Usa "Verificar '
              'descargas" y vuelve a intentarlo.'),
    ));
  }

  /// Devuelve el resultado, o null si no se eligió archivo o no era válido.
  static Future<ResultadoRestauracion?> restaurar(BuildContext context) async {
    // Sin esperas antes: el navegador solo abre el selector durante un toque.
    final web.File? archivo =
        await RedWeb.elegirArchivo('.zip,application/zip');
    if (archivo == null || !context.mounted) return null;

    final ScaffoldMessengerState mensajes = ScaffoldMessenger.of(context);
    try {
      final ResultadoRestauracion resultado = await _conProgreso(
        context,
        'Restaurando himnario',
        (onProgreso) =>
            RespaldoService.restaurar(archivo, onProgreso: onProgreso),
      );
      final String danadas = resultado.danadas == 0
          ? ''
          : ' ${resultado.danadas} venían dañadas.';
      mensajes.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(resultado.faltantes == 0
            ? 'Himnario restaurado (${resultado.restauradas} hojas).$danadas'
            : 'Se restauraron ${resultado.restauradas} hojas; faltan '
                '${resultado.faltantes}. Descárgalas con internet desde '
                '"Verificar descargas".$danadas'),
      ));
      return resultado;
    } on FormatException catch (e) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No se pudo restaurar'),
            content: Text(e.message),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      return null;
    }
  }

  static Future<T> _conProgreso<T>(
    BuildContext context,
    String titulo,
    Future<T> Function(void Function(int hechas, int total) onProgreso) tarea,
  ) async {
    final ValueNotifier<(int, int)> avance = ValueNotifier((0, 0));
    final NavigatorState navegador = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(titulo),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: avance,
            builder: (context, valor, _) {
              final (int hechas, int total) = valor;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: total == 0 ? null : hechas / total),
                  const SizedBox(height: 12),
                  Text(total == 0 ? 'Preparando...' : '$hechas de $total hojas'),
                ],
              );
            },
          ),
        ),
      ),
    );
    try {
      return await tarea((hechas, total) => avance.value = (hechas, total));
    } finally {
      navegador.pop();
      avance.dispose();
    }
  }
}
