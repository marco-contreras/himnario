import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
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
  PdfDocument? _documento;
  PdfControllerPinch? _pdfController;
  int _totalPaginasPdf = 1;
  int _paginaActualPdf = 1;
  bool _cargandoPdf = true;
  bool _errorCarga = false;

  // Si el usuario cambia de himno o sale antes de que termine una carga,
  // el documento de esa carga ya no es el vigente y se cierra.
  int _cargaVigente = 0;

  @override
  void initState() {
    super.initState();
    _himnoActual = widget.himnoActual;
    _cargarPdf();
  }

  int get _indiceActual =>
      widget.listaHimnos.indexWhere((h) => h.numero == _himnoActual.numero);

  void _abrirHimno(Himno himno) {
    _liberarDespuesDelFrame(_pdfController, _documento);
    setState(() {
      _himnoActual = himno;
      _pdfController = null;
      _documento = null;
      _cargandoPdf = true;
      _errorCarga = false;
      _paginaActualPdf = 1;
      _totalPaginasPdf = 1;
    });
    _cargarPdf();
  }

  Future<void> _cargarPdf() async {
    final int carga = ++_cargaVigente;
    final PdfDocument? documento = await _abrirDocumento(_himnoActual);

    if (!mounted || carga != _cargaVigente) {
      await documento?.close();
      return;
    }

    setState(() {
      _cargandoPdf = false;
      if (documento == null) {
        _errorCarga = true;
      } else {
        _documento = documento;
        _totalPaginasPdf = documento.pagesCount;
        _pdfController = PdfControllerPinch(document: Future.value(documento));
      }
    });
  }

  Future<PdfDocument?> _abrirDocumento(Himno himno) async {
    try {
      final bytes = await DownloadService.obtenerPdf(himno);
      return await PdfDocument.openData(bytes);
    } catch (e) {
      debugPrint('Error al cargar PDF del himno ${himno.numero}: $e');
      return null;
    }
  }

  // PdfControllerPinch.dispose() no cierra el documento, hay que cerrarlo
  // aparte. Se espera al siguiente frame porque PdfViewPinch sigue montado
  // con el controlador viejo hasta que la pantalla se reconstruye.
  void _liberarDespuesDelFrame(
    PdfControllerPinch? controller,
    PdfDocument? documento,
  ) {
    if (controller == null && documento == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller?.dispose();
      documento?.close();
    });
  }

  void _cambiarHimno(int offset) {
    final int nuevoIndice = _indiceActual + offset;
    if (nuevoIndice >= 0 && nuevoIndice < widget.listaHimnos.length) {
      _abrirHimno(widget.listaHimnos[nuevoIndice]);
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _documento?.close();
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

  Widget _construirCuerpo() {
    if (_cargandoPdf) return _indicadorCarga;

    final PdfControllerPinch? controller = _pdfController;
    if (_errorCarga || controller == null) return _construirError();

    return PdfViewPinch(
      key: ObjectKey(controller),
      controller: controller,
      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) => _indicadorCarga,
        pageLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) {
          debugPrint(
              'Error al mostrar PDF del himno ${_himnoActual.numero}: $error');
          return _construirError();
        },
      ),
      onPageChanged: (page) {
        setState(() {
          _paginaActualPdf = page;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int indice = _indiceActual;
    final bool hayAnterior = indice > 0;
    final bool haySiguiente =
        indice >= 0 && indice < widget.listaHimnos.length - 1;
    final bool mostrarPaginas = _pdfController != null && _totalPaginasPdf > 1;

    return Scaffold(
      // --- TOP BAR ---
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Himno #${_himnoActual.numero}'),
        centerTitle: true,
      ),

      // --- CENTRO (VISOR PDF) ---
      body: _construirCuerpo(),

      // --- BOTTOM BAR ---
      bottomNavigationBar: Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BARRA HORIZONTAL DE PÁGINAS (Solo si el PDF tiene más de 1 página)
            if (mostrarPaginas)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  itemCount: _totalPaginasPdf,
                  itemBuilder: (context, index) {
                    int numPagina = index + 1;
                    bool esSeleccionada = numPagina == _paginaActualPdf;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text('Pág $numPagina'),
                        selected: esSeleccionada,
                        onSelected: (bool selected) {
                          if (selected) {
                            _pdfController?.animateToPage(
                                pageNumber: numPagina);
                          }
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
