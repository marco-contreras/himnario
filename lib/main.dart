import 'package:flutter/material.dart';
import 'screens/menu_screen.dart';
import 'screens/descarga_screen.dart';
import 'services/download_service.dart';
import 'services/red_web.dart';
import 'services/version_app_service.dart';

void main() {
  runApp(const HimnarioApp());
}

class HimnarioApp extends StatefulWidget {
  const HimnarioApp({super.key});

  @override
  State<HimnarioApp> createState() => _HimnarioAppState();
}

class _HimnarioAppState extends State<HimnarioApp> {
  // En la PC la app vuelve a primer plano cada vez que recupera el foco.
  static const Duration _esperaEntreRevisiones = Duration(minutes: 5);

  final Future<bool> _descargaCompleta =
      DownloadService.estanArchivosDescargados();
  final GlobalKey<ScaffoldMessengerState> _mensajes = GlobalKey();
  late final AppLifecycleListener _cicloDeVida;
  DateTime? _ultimaRevision;
  bool _avisoMostrado = false;

  @override
  void initState() {
    super.initState();
    _cicloDeVida = AppLifecycleListener(onResume: _revisarVersion);
    _revisarVersion();
  }

  @override
  void dispose() {
    _cicloDeVida.dispose();
    super.dispose();
  }

  Future<void> _revisarVersion() async {
    final DateTime ahora = DateTime.now();
    final DateTime? ultima = _ultimaRevision;
    if (_avisoMostrado ||
        (ultima != null && ahora.difference(ultima) < _esperaEntreRevisiones)) {
      return;
    }
    _ultimaRevision = ahora;
    if (!await VersionAppService.hayVersionNueva() || !mounted) return;

    _avisoMostrado = true;
    // Banner y no SnackBar: uno de un día bloquearía la fila de mensajes que
    // usa el menú.
    _mensajes.currentState?.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update),
        content: const Text('Hay una versión nueva de la app.'),
        actions: [
          TextButton(
            onPressed: () =>
                _mensajes.currentState?.hideCurrentMaterialBanner(),
            child: const Text('Después'),
          ),
          const FilledButton(
            onPressed: RedWeb.recargarPagina,
            child: Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Himnario IBEFI',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _mensajes,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: FutureBuilder<bool>(
        future: _descargaCompleta,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final bool descargado = snapshot.data ?? false;

          // Si ya están descargados va directo al Menú, si no, pide descargar
          return descargado ? const MenuScreen() : const DescargaScreen();
        },
      ),
    );
  }
}
