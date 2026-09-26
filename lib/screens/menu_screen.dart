import 'package:flutter/material.dart';
import '../data/himnos_repository.dart';
import '../models/himno.dart';
import '../services/actualizacion_service.dart';
import '../services/download_service.dart';
import 'descarga_screen.dart';
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
  OrdenHimnos _orden = OrdenHimnos.numero;
  ActualizacionPendiente? _actualizacion;

  List<Himno> get _himnosOrdenados => _orden == OrdenHimnos.numero
      ? HimnosRepository.himnosPorNumero
      : HimnosRepository.himnosPorNombre;

  @override
  void initState() {
    super.initState();
    _himnosFiltrados = _himnosOrdenados;
    _revisarActualizaciones();
  }

  Future<void> _revisarActualizaciones() async {
    final Revision revision = await ActualizacionService.revisar();
    if (!mounted) return;
    setState(() => _actualizacion = revision.pendiente);
    if (revision.pendiente != null) await _ofrecerActualizacion();
  }

  Future<void> _verificarDescarga() async {
    if (!await DownloadService.estanArchivosDescargados()) {
      if (!mounted) return;
      final bool? descargar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Verificar descarga'),
          content: const Text(
              'Todavía no has descargado el himnario para usarlo sin internet. ¿Descargarlo ahora?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descargar'),
            ),
          ],
        ),
      );
      if (descargar == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const DescargaScreen(desdeMenu: true)),
        );
      }
      return;
    }

    if (!mounted) return;
    final ScaffoldMessengerState mensajes = ScaffoldMessenger.of(context);
    mensajes.showSnackBar(
        const SnackBar(content: Text('Verificando la descarga...')));
    final Revision revision = await ActualizacionService.revisar();
    if (!mounted) return;
    mensajes.hideCurrentSnackBar();
    setState(() => _actualizacion = revision.pendiente);
    switch (revision.estado) {
      case EstadoRevision.sinConexion:
        mensajes.showSnackBar(const SnackBar(
            content: Text(
                'Sin conexión. Conéctate a internet para verificar la descarga.')));
      case EstadoRevision.alDia:
        mensajes.showSnackBar(const SnackBar(
            content: Text('Todo el himnario está descargado y al día.')));
      case EstadoRevision.pendiente:
        await _ofrecerActualizacion();
    }
  }

  String _describir(ActualizacionPendiente pendiente) {
    final int mejoradas = pendiente.mejoradas;
    final int faltantes = pendiente.faltantes;
    final List<String> partes = [
      if (mejoradas > 0)
        mejoradas == 1
            ? '1 hoja nueva o mejorada'
            : '$mejoradas hojas nuevas o mejoradas',
      if (faltantes > 0)
        faltantes == 1
            ? '1 hoja que falta en este dispositivo'
            : '$faltantes hojas que faltan en este dispositivo',
    ];
    final double mb = pendiente.bytes / 1e6;
    final String tamano =
        mb < 10 ? mb.toStringAsFixed(1) : mb.round().toString();
    final String descargar =
        pendiente.hojas.length == 1 ? 'Descargarla' : 'Descargarlas';
    return 'Hay ${partes.join(' y ')} (≈$tamano MB). ¿$descargar ahora?';
  }

  Future<void> _ofrecerActualizacion() async {
    final ActualizacionPendiente? pendiente = _actualizacion;
    if (pendiente == null) return;
    final bool? aceptar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualización del himnario'),
        content: Text(_describir(pendiente)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );
    if (aceptar == true && mounted) await _aplicarActualizacion(pendiente);
  }

  Future<void> _aplicarActualizacion(ActualizacionPendiente pendiente) async {
    final ValueNotifier<int> hechas = ValueNotifier(0);
    final int total = pendiente.hojas.length;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Actualizando himnario'),
          content: ValueListenableBuilder<int>(
            valueListenable: hechas,
            builder: (context, valor, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: valor / total),
                const SizedBox(height: 12),
                Text('$valor de $total hojas'),
              ],
            ),
          ),
        ),
      ),
    );

    final int fallidas = await ActualizacionService.aplicar(
      pendiente,
      onProgreso: (valor, _) => hechas.value = valor,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    hechas.dispose();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fallidas == 0
          ? 'Himnario actualizado.'
          : 'No se pudieron descargar $fallidas hojas. Revisa tu conexión e inténtalo de nuevo.'),
    ));

    // Si algo falló, se vuelve a revisar para dejar pendiente solo lo que faltó.
    final ActualizacionPendiente? restante = fallidas == 0
        ? null
        : (await ActualizacionService.revisar()).pendiente;
    if (mounted) setState(() => _actualizacion = restante);
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
      _himnosFiltrados = HimnosRepository.buscar(query, _himnosOrdenados);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Himnario IBEFI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (_actualizacion != null)
            IconButton(
              tooltip: 'Descargar actualización',
              onPressed: _ofrecerActualizacion,
              icon: Badge(
                label: Text('${_actualizacion!.hojas.length}'),
                child: const Icon(Icons.system_update_alt),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (_) => _verificarDescarga(),
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'verificar',
                child: Text('Verificar descarga'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
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