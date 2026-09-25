import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../data/himnos_repository.dart';
import '../models/himno.dart';
import '../services/download_service.dart';

class VisorScreen extends StatefulWidget {
  final Himno himnoActual;
  final List<Himno> listaHimnos;

  const VisorScreen({
    super.key,
    required this.himnoActual,
    required this.listaHimnos,
  });

  @override
  State<VisorScreen> createState() => _VisorScreenState();
}

class _VisorScreenState extends State<VisorScreen> {
  static const double _separacionPaginas = 8.0;
  static const double _zoomMaximo = 4.0;

  static const Widget _indicadorCarga = Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Cargando himno...'),
      ],
    ),
  );

  late Himno _himnoActual;
  final TransformationController _transformacion = TransformationController();
  final SearchController _buscador = SearchController();
  final List<ui.Image> _paginas = [];
  int _totalPaginas = 1;
  int _paginaActual = 1;
  bool _errorCarga = false;
  Size? _tamanoVista;

  // Si el usuario cambia de himno o sale antes de que termine una carga,
  // las páginas de esa carga ya no son las vigentes y se descartan.
  int _cargaVigente = 0;

  final Set<int> _dedosEnPantalla = {};
  Offset? _inicioDeslizamiento;
  bool _huboVariosDedos = false;

  @override
  void initState() {
    super.initState();
    _himnoActual = widget.himnoActual;
    _transformacion.addListener(_actualizarPaginaActual);
    _cargarHimno();
  }

  int get _indiceActual =>
      widget.listaHimnos.indexWhere((h) => h.numero == _himnoActual.numero);

  bool get _hayZoom => _transformacion.value.getMaxScaleOnAxis() > 1.01;

  void _abrirHimno(Himno himno) {
    _liberarPaginas();
    _transformacion.value = Matrix4.identity();
    setState(() {
      _himnoActual = himno;
      _errorCarga = false;
      _paginaActual = 1;
      _totalPaginas = 1;
    });
    _cargarHimno();
  }

  // Cada página es una imagen de 2400 px de ancho, con resolución de sobra
  // para el zoom: el zoom solo la escala y no hay que volver a dibujar nada.
  Future<void> _cargarHimno() async {
    final int carga = ++_cargaVigente;
    final Himno himno = _himnoActual;
    bool esVigente() => mounted && carga == _cargaVigente;

    try {
      final List<String> rutas = await DownloadService.paginasDe(himno);
      if (!esVigente()) return;
      if (rutas.isEmpty) {
        throw StateError('No hay páginas para el himno ${himno.numero}');
      }
      setState(() => _totalPaginas = rutas.length);

      for (final String ruta in rutas) {
        final ui.Image imagen =
            await decodeImageFromList(await DownloadService.obtenerPagina(ruta));
        if (!esVigente()) {
          imagen.dispose();
          return;
        }
        setState(() => _paginas.add(imagen));
      }
    } catch (e) {
      debugPrint('Error al cargar el himno ${himno.numero}: $e');
      if (esVigente()) {
        _liberarPaginas();
        setState(() => _errorCarga = true);
      }
    }
  }

  void _liberarPaginas() {
    for (final ui.Image pagina in _paginas) {
      pagina.dispose();
    }
    _paginas.clear();
  }

  double _altoPagina(int indice, double ancho) {
    final ui.Image referencia =
        indice < _paginas.length ? _paginas[indice] : _paginas.first;
    return ancho * referencia.height / referencia.width;
  }

  double _inicioPagina(int indice, double ancho) {
    double y = 0;
    for (int i = 0; i < indice; i++) {
      y += _altoPagina(i, ancho) + _separacionPaginas;
    }
    return y;
  }

  void _actualizarPaginaActual() {
    final Size? vista = _tamanoVista;
    if (vista == null || _paginas.isEmpty) return;
    final Matrix4 m = _transformacion.value;
    final double centro =
        (-m.getTranslation().y + vista.height / 2) / m.getMaxScaleOnAxis();
    int pagina = 1;
    while (pagina < _totalPaginas &&
        _inicioPagina(pagina, vista.width) <= centro) {
      pagina++;
    }
    if (pagina != _paginaActual) {
      setState(() => _paginaActual = pagina);
    }
  }

  void _irAPagina(int numero) {
    final Size? vista = _tamanoVista;
    if (vista == null || _paginas.isEmpty) return;
    final Matrix4 m = _transformacion.value;
    final double escala = m.getMaxScaleOnAxis();
    final double altoContenido =
        _inicioPagina(_totalPaginas, vista.width) - _separacionPaginas;
    final double maxY = math.max(0.0, altoContenido * escala - vista.height);
    final double y =
        (_inicioPagina(numero - 1, vista.width) * escala).clamp(0.0, maxY);
    _transformacion.value = Matrix4.diagonal3Values(escala, escala, 1)
      ..setTranslationRaw(m.getTranslation().x, -y, 0);
    setState(() => _paginaActual = numero);
  }

  void _cambiarHimno(int offset) {
    final int nuevoIndice = _indiceActual + offset;
    if (nuevoIndice >= 0 && nuevoIndice < widget.listaHimnos.length) {
      _abrirHimno(widget.listaHimnos[nuevoIndice]);
    }
  }

  // Deslizar a los lados cambia de himno. Se usan eventos de puntero crudos
  // porque el InteractiveViewer se queda con los gestos de arrastre; solo
  // cuenta con un dedo y sin zoom, para no chocar con el pellizco ni con
  // mover una página ampliada.
  void _alTocar(PointerDownEvent evento) {
    _dedosEnPantalla.add(evento.pointer);
    if (_dedosEnPantalla.length == 1) {
      _inicioDeslizamiento = evento.position;
      _huboVariosDedos = false;
    } else {
      _huboVariosDedos = true;
    }
  }

  void _alSoltar(PointerEvent evento) {
    _dedosEnPantalla.remove(evento.pointer);
    final Offset? inicio = _inicioDeslizamiento;
    if (_dedosEnPantalla.isNotEmpty || inicio == null) return;
    _inicioDeslizamiento = null;
    if (_huboVariosDedos || _hayZoom || evento is! PointerUpEvent) return;

    final Offset recorrido = evento.position - inicio;
    final double minimo = math.max(60.0, MediaQuery.sizeOf(context).width * 0.15);
    if (recorrido.dx.abs() >= minimo &&
        recorrido.dx.abs() > recorrido.dy.abs() * 2) {
      _cambiarHimno(recorrido.dx < 0 ? 1 : -1);
    }
  }

  // El número exacto va primero: al escribir "64" aparece el 64 antes que
  // el 164 o el 264.
  List<Himno> _sugerencias(String texto) {
    if (texto.trim().isEmpty) return const [];
    final List<Himno> resultados =
        HimnosRepository.buscar(texto, HimnosRepository.himnosPorNumero);
    final int? exacto = int.tryParse(texto.trim());
    return [
      ...resultados.where((h) => h.numero == exacto),
      ...resultados.where((h) => h.numero != exacto),
    ];
  }

  void _irAlHimnoBuscado(Himno himno) {
    _buscador.closeView('');
    _abrirHimno(himno);
  }

  Widget _construirBuscador() {
    return SearchAnchor(
      searchController: _buscador,
      viewHintText: 'Buscar por número o título',
      viewBackgroundColor: Colors.white,
      viewSurfaceTintColor: Colors.transparent,
      viewOnSubmitted: (texto) {
        final List<Himno> resultados = _sugerencias(texto);
        if (resultados.isNotEmpty) _irAlHimnoBuscado(resultados.first);
      },
      builder: (context, controller) => SearchBar(
        controller: controller,
        hintText: 'Buscar',
        leading: const Icon(Icons.search),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        constraints: const BoxConstraints(maxWidth: 140, minHeight: 40),
        side: WidgetStatePropertyAll(
          BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onTap: controller.openView,
        onChanged: (_) => controller.openView(),
      ),
      suggestionsBuilder: (context, controller) =>
          _sugerencias(controller.text).map(
        (himno) => ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            child: Text('${himno.numero}'),
          ),
          title: Text(himno.nombre),
          onTap: () => _irAlHimnoBuscado(himno),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _buscador.dispose();
    _transformacion.dispose();
    _liberarPaginas();
    super.dispose();
  }

  Widget _construirError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No se pudo abrir el himno #${_himnoActual.numero}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa tu conexión a internet o descarga el himnario para usarlo sin conexión.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _abrirHimno(_himnoActual),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirPaginas() {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final Size vista = restricciones.biggest;
        _tamanoVista = vista;
        final double ancho = vista.width;

        return InteractiveViewer(
          transformationController: _transformacion,
          constrained: false,
          minScale: 1.0,
          maxScale: _zoomMaximo,
          child: SizedBox(
            width: ancho,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: vista.height),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _totalPaginas; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i < _totalPaginas - 1 ? _separacionPaginas : 0,
                      ),
                      child: SizedBox(
                        width: ancho,
                        height: _altoPagina(i, ancho),
                        child: i < _paginas.length
                            ? RawImage(
                                image: _paginas[i],
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                              )
                            : const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _construirCuerpo() {
    if (_errorCarga) return _construirError();
    if (_paginas.isEmpty) return _indicadorCarga;
    return _construirPaginas();
  }

  @override
  Widget build(BuildContext context) {
    final int indice = _indiceActual;
    final bool hayAnterior = indice > 0;
    final bool haySiguiente =
        indice >= 0 && indice < widget.listaHimnos.length - 1;
    final bool mostrarPaginas = _paginas.isNotEmpty && _totalPaginas > 1;

    return Scaffold(
      // --- TOP BAR ---
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Himno #${_himnoActual.numero}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _construirBuscador(),
          ),
        ],
      ),

      // --- CENTRO (VISOR) ---
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _alTocar,
        onPointerUp: _alSoltar,
        onPointerCancel: _alSoltar,
        child: _construirCuerpo(),
      ),

      // --- BOTTOM BAR ---
      bottomNavigationBar: Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BARRA HORIZONTAL DE PÁGINAS (Solo si el himno tiene más de 1 página)
            if (mostrarPaginas)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  itemCount: _totalPaginas,
                  itemBuilder: (context, index) {
                    int numPagina = index + 1;
                    bool esSeleccionada = numPagina == _paginaActual;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text('Pág $numPagina'),
                        selected: esSeleccionada,
                        onSelected: (bool selected) {
                          if (selected) _irAPagina(numPagina);
                        },
                      ),
                    );
                  },
                ),
              ),

            if (mostrarPaginas) const SizedBox(height: 6),

            // NAVEGACIÓN ENTRE HIMNOS << # >>
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  onPressed: hayAnterior ? () => _cambiarHimno(-1) : null,
                  tooltip: 'Himno Anterior',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    '${_himnoActual.numero}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  onPressed: haySiguiente ? () => _cambiarHimno(1) : null,
                  tooltip: 'Himno Siguiente',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
