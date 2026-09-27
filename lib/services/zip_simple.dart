import 'dart:convert';
import 'dart:typed_data';

/// Lo mínimo de ZIP que necesita el respaldo del himnario: escribir sin
/// comprimir (las imágenes WebP ya vienen comprimidas) y leer el índice de un
/// ZIP, también de uno que alguien haya vuelto a comprimir con otra herramienta.
class EntradaZip {
  final String nombre;
  final int metodo; // 0 = sin comprimir, 8 = deflate
  final int crc;
  final int tamanoComprimido;
  final int tamano;
  final int inicioCabecera;

  const EntradaZip({
    required this.nombre,
    required this.metodo,
    required this.crc,
    required this.tamanoComprimido,
    required this.tamano,
    required this.inicioCabecera,
  });
}

class IndiceZip {
  final int inicio;
  final int tamano;

  const IndiceZip(this.inicio, this.tamano);
}

class EscritorZip {
  final BytesBuilder _indice = BytesBuilder(copy: false);
  int _desplazamiento = 0;
  int _cantidad = 0;
  final int _hora;
  final int _fecha;

  EscritorZip(DateTime ahora)
      : _hora = (ahora.hour << 11) | (ahora.minute << 5) | (ahora.second ~/ 2),
        _fecha =
            ((ahora.year - 1980) << 9) | (ahora.month << 5) | ahora.day;

  /// Cabecera local de un archivo; los datos van justo después, tal cual.
  Uint8List cabecera(String nombre, Uint8List datos) {
    final List<int> nombreUtf8 = utf8.encode(nombre);
    final int crc = crc32(datos);

    final ByteData local = ByteData(30);
    local.setUint32(0, 0x04034b50, Endian.little);
    _comunes(local, 4, crc, datos.length, nombreUtf8.length);

    final ByteData central = ByteData(46);
    central.setUint32(0, 0x02014b50, Endian.little);
    central.setUint16(4, 20, Endian.little);
    _comunes(central, 6, crc, datos.length, nombreUtf8.length);
    central.setUint32(42, _desplazamiento, Endian.little);
    _indice
      ..add(central.buffer.asUint8List())
      ..add(nombreUtf8);

    _desplazamiento += 30 + nombreUtf8.length + datos.length;
    _cantidad++;
    return (BytesBuilder(copy: false)
          ..add(local.buffer.asUint8List())
          ..add(nombreUtf8))
        .takeBytes();
  }

  // Campos iguales en la cabecera local y en la del índice: versión, bandera
  // de nombres UTF-8, método 0, fecha, CRC, tamaños y largo del nombre.
  void _comunes(ByteData d, int i, int crc, int tamano, int largoNombre) {
    d
      ..setUint16(i, 20, Endian.little)
      ..setUint16(i + 2, 0x0800, Endian.little)
      ..setUint16(i + 4, 0, Endian.little)
      ..setUint16(i + 6, _hora, Endian.little)
      ..setUint16(i + 8, _fecha, Endian.little)
      ..setUint32(i + 10, crc, Endian.little)
      ..setUint32(i + 14, tamano, Endian.little)
      ..setUint32(i + 18, tamano, Endian.little)
      ..setUint16(i + 22, largoNombre, Endian.little);
  }

  /// Índice y fin del archivo: lo último que se escribe.
  Uint8List cierre() {
    final Uint8List indice = _indice.takeBytes();
    final ByteData fin = ByteData(22);
    fin
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, _cantidad, Endian.little)
      ..setUint16(10, _cantidad, Endian.little)
      ..setUint32(12, indice.length, Endian.little)
      ..setUint32(16, _desplazamiento, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(indice)
          ..add(fin.buffer.asUint8List()))
        .takeBytes();
  }
}

/// Busca el registro final en los últimos bytes del archivo (hasta 64 KB de
/// comentario) y devuelve dónde está el índice. Null si no parece un ZIP.
IndiceZip? buscarIndice(Uint8List cola) {
  final ByteData d = ByteData.sublistView(cola);
  for (int i = cola.length - 22; i >= 0; i--) {
    if (d.getUint32(i, Endian.little) != 0x06054b50) continue;
    final int tamano = d.getUint32(i + 12, Endian.little);
    final int inicio = d.getUint32(i + 16, Endian.little);
    if (tamano == 0xFFFFFFFF || inicio == 0xFFFFFFFF) return null; // ZIP64
    return IndiceZip(inicio, tamano);
  }
  return null;
}

List<EntradaZip> leerIndice(Uint8List indice) {
  final ByteData d = ByteData.sublistView(indice);
  final List<EntradaZip> entradas = [];
  int i = 0;
  while (i + 46 <= indice.length && d.getUint32(i, Endian.little) == 0x02014b50) {
    final int largoNombre = d.getUint16(i + 28, Endian.little);
    final int largoExtra = d.getUint16(i + 30, Endian.little);
    final int largoComentario = d.getUint16(i + 32, Endian.little);
    entradas.add(EntradaZip(
      nombre: utf8.decode(indice.sublist(i + 46, i + 46 + largoNombre),
          allowMalformed: true),
      metodo: d.getUint16(i + 10, Endian.little),
      crc: d.getUint32(i + 16, Endian.little),
      tamanoComprimido: d.getUint32(i + 20, Endian.little),
      tamano: d.getUint32(i + 24, Endian.little),
      inicioCabecera: d.getUint32(i + 42, Endian.little),
    ));
    i += 46 + largoNombre + largoExtra + largoComentario;
  }
  return entradas;
}

/// Dónde empiezan los datos de una entrada, a partir de su cabecera local
/// (sus 30 primeros bytes).
int inicioDatos(EntradaZip entrada, Uint8List cabeceraLocal) {
  final ByteData d = ByteData.sublistView(cabeceraLocal);
  return entrada.inicioCabecera +
      30 +
      d.getUint16(26, Endian.little) +
      d.getUint16(28, Endian.little);
}

final Uint32List _tablaCrc = () {
  final Uint32List tabla = Uint32List(256);
  for (int n = 0; n < 256; n++) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    tabla[n] = c;
  }
  return tabla;
}();

int crc32(Uint8List datos) {
  int crc = 0xFFFFFFFF;
  for (final int byte in datos) {
    crc = _tablaCrc[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}
