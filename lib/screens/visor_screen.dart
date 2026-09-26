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
  bool? _busquedaPantallaCompleta;
  ui.PointerDeviceKind? _ultimoPuntero;
  // Un lugar por página del himno; null mientras esa imagen se decodifica.
  final List<ui.Image?> _paginas = [];
  int _paginaActual = 1;
  bool _errorCarga = false;

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
    _cargarHimno();
  }

  int get _indiceActual =>
      widget.listaHimnos.indexWhere((h) => h.numero == _himnoActual.numero);

  int get _totalPaginas => _paginas.length;

  bool get _hayZoom => _transformacion.value.getMaxScaleOnAxis() > 1.01;

  // "24-1", "24-2"... en los himnos de varias hojas; "64" en los de una.
  String _etiqueta(int pagina) => _totalPaginas > 1
      ? '${_himnoActual.numero}-$pagina'
      : '${_himnoActual.numero}';

  void _abrirHimno(Himno himno, {bool enUltimaPagina = false}) {
    _liberarPaginas();
    _transformacion.value = Matrix4.identity();
    setState(() {
      _himnoActual = himno;
      _errorCarga = false;
      _paginaActual = 1;
    });
    _cargarHimno(enUltimaPagina: enUltimaPagina);
  }

  // Cada página es una imagen de 2400 px de ancho, con resolución de sobra
  // para el zoom: el zoom solo la escala y no hay que volver a dibujar nada.
  Future<void> _cargarHimno({bool enUltimaPagina = false}) async {
    final int carga = ++_cargaVigente;
    final Himno himno = _himnoActual;
    bool esVigente() => mounted && carga == _cargaVigente;

    try {
      final List<String> rutas = await DownloadService.paginasDe(himno);
      if (!esVigente()) return;
      if (rutas.isEmpty) {
        throw StateError('No hay páginas para el himno ${himno.numero}');
      }
      final int inicial = enUltimaPagina ? rutas.length : 1;
      setState(() {
        _paginas.addAll(List<ui.Image?>.filled(rutas.length, null));
        _paginaActual = inicial;
      });

      // Primero la página que se va a mostrar y después las demás.
      final List<int> orden = [
        inicial - 1,
        for (int i = 0; i < rutas.length; i++)
          if (i != inicial - 1) i,
      ];
      for (final int i in orden) {
        final ui.Image imagen = await decodeImageFromList(
            await DownloadService.obtenerPagina(rutas[i]));
        if (!esVigente()) {
          imagen.dispose();
          return;
        }
        setState(() => _paginas[i] = imagen);
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
    for (final ui.Image? pagina in _paginas) {
      pagina?.dispose();
    }
    _paginas.clear();
  }

  void _irAPagina(int numero) {
    _transformacion.value = Matrix4.identity();
    setState(() => _paginaActual = numero);
  }

  // Como un libro: primero se pasan las páginas del himno y después se llega
  // al himno vecino. Al retroceder desde la primera página se abre el himno
  // anterior en su última página.
  void _avanzar(int direccion) {
    final int pagina = _paginaActual + direccion;
    if (pagina >= 1 && pagina <= _totalPaginas) {
      _irAPagina(pagina);
      return;
    }
    final int nuevoIndice = _indiceActual + direccion;
    if (nuevoIndice >= 0 && nuevoIndice < widget.listaHimnos.length) {
      _abrirHimno(widget.listaHimnos[nuevoIndice],
          enUltimaPagina: direccion < 0);
    }
  }

  // Deslizar a los lados pasa de página o de himno. Se usan eventos de
  // puntero crudos porque el InteractiveViewer se queda con los gestos de
  // arrastre; solo cuenta con un dedo y sin zoom, para no chocar con el
  // pellizco ni con mover una página ampliada.
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
      _avanzar(recorrido.dx < 0 ? 1 : -1);
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
    FocusManager.instance.primaryFocus?.unfocus();
    _abrirHimno(himno);
  }

  // Chrome en tablets grandes abre los sitios en modo escritorio, así que
  // Flutter cree que es una PC y abre la búsqueda como panel. Ese panel se
  // cierra cuando el teclado en pantalla cambia el tamaño de la ventana, antes
  // de que llegue el toque en la sugerencia. Por eso se decide según con qué
  // se tocó la barra: dedo o lápiz, pantalla completa; mouse, panel.
  void _abrirBusqueda(SearchController controller) {
    if (controller.isOpen) return;
    final ui.PointerDeviceKind? puntero = _ultimoPuntero;
    final bool? pantallaCompleta =
        puntero == null ? null : puntero != ui.PointerDeviceKind.mouse;
    if (pantallaCompleta == _busquedaPantallaCompleta) {
      controller.openView();
      return;
    }
    setState(() => _busquedaPantallaCompleta = pantallaCompleta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !controller.isOpen) controller.openView();
    });
  }

  Widget _construirBuscador() {
    return SearchAnchor(
      searchController: _buscador,
      isFullScreen: _busquedaPantallaCompleta,
      viewHintText: 'Buscar por número o título',
      viewBackgroundColor: Colors.white,
      viewSurfaceTintColor: Colors.transparent,
      viewOnSubmitted: (texto) {
        final List<Himno> resultados = _sugerencias(texto);
        if (resultados.isNotEmpty) _irAlHimnoBuscado(resultados.first);
      },
      builder: (context, controller) => Listener(
        onPointerDown: (evento) => _ultimoPuntero = evento.kind,
        child: SearchBar(
          controller: controller,
          hintText: 'Buscar',
          leading: const Icon(Icons.search),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          constraints: const BoxConstraints(maxWidth: 130, minHeight: 40),
          side: WidgetStatePropertyAll(
            BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onTap: () => _abrirBusqueda(controller),
          onChanged: (_) => _abrirBusqueda(controller),
        ),
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

  Widget _construirPagina(ui.Image imagen) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final Size vista = restricciones.biggest;
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
              child: Center(
                child: SizedBox(
                  width: ancho,
                  height: ancho * imagen.height / imagen.width,
                  child: RawImage(
                    image: imagen,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _construirCuerpo() {
    if (_errorCarga) return _construirError();
    final ui.Image? imagen =
        _paginas.isEmpty ? null : _paginas[_paginaActual - 1];
    if (imagen == null) return _indicadorCarga;
    return _construirPagina(imagen);
  }

  @override
  Widget build(BuildContext context) {
    final int indice = _indiceActual;
    final bool hayAnterior = indice > 0 || _paginaActual > 1;
    final bool haySiguiente = (indice >= 0 &&
            indice < widget.listaHimnos.length - 1) ||
        _paginaActual < _totalPaginas;
    final bool mostrarPaginas = _totalPaginas > 1;

    return Scaffold(
      // --- TOP BAR ---
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Himno #${_etiqueta(_paginaActual)}',
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
                        label: Text(_etiqueta(numPagina)),
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

            // NAVEGACIÓN << # >> (páginas y himnos, como un libro)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  onPressed: hayAnterior ? () => _avanzar(-1) : null,
                  tooltip: 'Anterior',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    _etiqueta(_paginaActual),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  onPressed: haySiguiente ? () => _avanzar(1) : null,
                  tooltip: 'Siguiente',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
