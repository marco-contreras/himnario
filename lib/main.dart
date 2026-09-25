import 'package:flutter/material.dart';
import 'screens/menu_screen.dart';
import 'screens/descarga_screen.dart';
import 'services/download_service.dart';

void main() {
  runApp(const HimnarioApp());
}

class HimnarioApp extends StatefulWidget {
  const HimnarioApp({super.key});

  @override
  State<HimnarioApp> createState() => _HimnarioAppState();
}

class _HimnarioAppState extends State<HimnarioApp> {
  final Future<bool> _descargaCompleta =
      DownloadService.estanArchivosDescargados();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Himnario IBEFI',
      debugShowCheckedModeBanner: false,
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
