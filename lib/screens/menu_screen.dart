import 'package:flutter/material.dart';
import '../data/himnos_repository.dart';
import '../models/himno.dart';
import '../services/sync_service.dart';
import 'visor_screen.dart';

enum OrdenHimnos { numero, nombre }

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Himno> _himnosFiltrados = [];
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _estaVerificandoToken = true;
  OrdenHimnos _orden = OrdenHimnos.numero;

  List<Himno> get _himnosOrdenados => _orden == OrdenHimnos.numero
      ? HimnosRepository.himnosPorNumero
      : HimnosRepository.himnosPorNombre;

  @override
  void initState() {
    super.initState();
    _himnosFiltrados = _himnosOrdenados;
    _verificarTokenDominical();
  }

  Future<void> _verificarTokenDominical() async {
    bool necesitaSync = await SyncService.necesitaActualizar();
    if (necesitaSync) {
      // Aquí dispararemos la lógica de sincronización con Google Drive
      await SyncService.marcarSincronizado();
    }
    if (!mounted) return;
    setState(() {
      _estaVerificandoToken = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _cambiarOrden(OrdenHimnos orden) {
    _orden = orden;
    _filtrarHimnos(_searchController.text);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _filtrarHimnos(String query) {
    setState(() {
      if (query.isEmpty) {
        _himnosFiltrados = _himnosOrdenados;
      } else {
        _himnosFiltrados = _himnosOrdenados.where((himno) {
          final queryLower = query.toLowerCase();
          final coincideNombre = himno.nombre.toLowerCase().contains(queryLower);
          final coincideNumero = himno.numero.toString().contains(queryLower);
          return coincideNombre || coincideNumero;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Himnario IBEFI'),
        centerTitle: true,
      ),
      body: _estaVerificandoToken
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Comprobando actualizaciones dominicales...'),
                ],
              ),
            )
          : Column(
              children: [
                // Buscador
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filtrarHimnos,
                    decoration: InputDecoration(
                      labelText: 'Buscar por número o título',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _filtrarHimnos('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                // Orden de la lista
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 8.0),
                  child: SegmentedButton<OrdenHimnos>(
                    segments: const [
                      ButtonSegment(
                        value: OrdenHimnos.numero,
                        icon: Icon(Icons.format_list_numbered),
                        label: Text('Número'),
                      ),
                      ButtonSegment(
                        value: OrdenHimnos.nombre,
                        icon: Icon(Icons.sort_by_alpha),
                        label: Text('Nombre'),
                      ),
                    ],
                    selected: {_orden},
                    onSelectionChanged: (seleccion) =>
                        _cambiarOrden(seleccion.first),
                  ),
                ),
                // Lista de Himnos
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _himnosFiltrados.length,
                    itemBuilder: (context, index) {
                      final himno = _himnosFiltrados[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          child: Text('${himno.numero}'),
                        ),
                        title: Text(himno.nombre),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VisorScreen(
                                himnoActual: himno,
                                listaHimnos: HimnosRepository.himnosPorNumero,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}