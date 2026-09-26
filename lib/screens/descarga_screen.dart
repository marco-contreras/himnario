import 'package:flutter/material.dart';
import '../services/actualizacion_service.dart';
import '../services/download_service.dart';
import 'menu_screen.dart';

class DescargaScreen extends StatefulWidget {
  /// Si se abrió desde el menú, al terminar vuelve a él en lugar de abrir
  /// uno nuevo.
  final bool desdeMenu;

  const DescargaScreen({super.key, this.desdeMenu = false});

  @override
  State<DescargaScreen> createState() => _DescargaScreenState();
}

class _DescargaScreenState extends State<DescargaScreen> {
  int _completados = 0;
  int _total = 270;
  bool _descargando = false;
  bool _huboFallos = false;
  String _estado =
      'Para usar el himnario sin internet, es necesario descargar los archivos en este dispositivo (cerca de 170 MB, se recomienda usar Wi-Fi).';

  Future<void> _iniciarDescarga() async {
    setState(() {
      _descargando = true;
      _huboFallos = false;
      _completados = 0;
      _estado = 'Descargando himnos a la memoria local...';
    });

    // Se lee antes de descargar: si se publica algo a mitad de la descarga,
    // la próxima revisión lo detecta como actualización.
    final Manifiesto? manifiesto = await ActualizacionService.leerRemoto();
    final int fallidos = await DownloadService.descargarTodosLosHimnos(
      onProgreso: (completados, total) {
        if (!mounted) return;
        setState(() {
          _completados = completados;
          _total = total;
        });
      },
    );

    if (!mounted) return;

    if (fallidos == 0) {
      if (manifiesto != null) await ActualizacionService.guardarLocal(manifiesto);
      if (mounted) _irAlMenu();
      return;
    }

    setState(() {
      _descargando = false;
      _huboFallos = true;
      _estado =
          'No se pudieron descargar $fallidos de $_total himnos. Revisa tu conexión e inténtalo de nuevo.';
    });
  }

  void _irAlMenu() {
    if (widget.desdeMenu) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MenuScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    double progreso = _total > 0 ? _completados / _total : 0.0;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_download, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Bienvenido al Himnario IBEFI',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _estado,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _huboFallos
                      ? Theme.of(context).colorScheme.error
                      : Colors.grey,
                ),
              ),
              const SizedBox(height: 32),

              if (_descargando) ...[
                LinearProgressIndicator(value: progreso, minHeight: 10),
                const SizedBox(height: 16),
                Text('Descargado: $_completados de $_total (${(progreso * 100).toInt()}%)'),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _iniciarDescarga,
                  icon: Icon(_huboFallos ? Icons.refresh : Icons.download),
                  label: Text(_huboFallos
                      ? 'Reintentar descarga'
                      : 'Descargar Himnario Localmente'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _irAlMenu,
                  child: const Text('Continuar sin descargar (requiere internet)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
