import 'package:flutter/material.dart';

class AyudaScreen extends StatelessWidget {
  const AyudaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ayuda',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _Seccion(
            icono: Icons.install_mobile,
            titulo: '¿Utilizar en el Navegador o como App?',
            contenido: [
              _Texto(
                  'Es el mismo himnario de las dos formas, pero como App funciona mejor sin internet.'),
              _Subtitulo('Como App (recomendado)'),
              _Punto(
                  'Tiene su propio ícono y se abre en pantalla completa, sin la barra del navegador.'),
              _Punto(
                  'Los himnos descargados quedan mejor protegidos: en iPad no se borran al limpiar Safari, y en Android el navegador no los borra cuando falta espacio.'),
              _Punto('Se actualiza sola cuando hay internet.'),
              _Subtitulo('En el Navegador'),
              _Punto('No hay que instalar nada: sirve para consultar algo rápido.'),
              _Punto(
                  'Si se borran los datos o el historial del navegador, se borran también los himnos descargados.'),
              _Punto(
                  'En iPad, Safari puede borrarlos si no abres el himnario en 7 días.'),
              _Subtitulo('Cómo instalarla'),
              _Punto(
                  'Android (Chrome): menú ⋮ del himnario → "Instalar APP", o menú ⋮ de Chrome → "Instalar aplicación".'),
              _Punto(
                  'iPad o iPhone (Safari): botón Compartir → "Agregar a pantalla de inicio".'),
              _Punto(
                  'Después ábrela desde su ícono y descarga ahí el himnario: la app instalada guarda sus propios datos.'),
            ],
          ),
          _Seccion(
            icono: Icons.save_alt,
            titulo: 'Respaldo del himnario',
            contenido: [
              _Subtitulo('Guardar respaldo'),
              _Punto(
                  'Crea un archivo con todos los himnos (HIMNARIOS-IBEFI-fecha.zip, cerca de 170 MB) sin usar internet.'),
              _Punto(
                  'En Android queda en la carpeta Descargas; en iPad eliges dónde guardarlo, por ejemplo en Archivos.'),
              _Punto(
                  'Ese archivo queda fuera del navegador: aunque se borren sus datos, el respaldo sigue ahí.'),
              _Subtitulo('Restaurar desde archivo'),
              _Punto(
                  'Vuelve a cargar los himnos desde el respaldo, sin internet, para usarlos sin conexión.'),
              _Subtitulo('¿Cuándo sirve?'),
              _Punto(
                  'Si se borraron los datos del navegador y estás donde no hay internet.'),
              _Punto(
                  'Para pasar el himnario a otra tablet sin gastar datos: copia el archivo por cable, Bluetooth o Drive y restáuralo allá.'),
              _Punto(
                  'Si el respaldo es viejo no pasa nada: con internet se bajan solo las hojas que cambiaron.'),
            ],
          ),
          _Seccion(
            icono: Icons.keyboard,
            titulo: 'Pedal para pasar páginas',
            contenido: [
              _Subtitulo('Conectarlo'),
              _Punto(
                  'Empareja el pedal por Bluetooth desde los ajustes del dispositivo: funciona como un teclado.'),
              _Punto(
                  'Ponlo en el modo Re Pág/Av Pág, ←/→ o ↑/↓ (el manual del pedal dice cómo cambiar de modo).'),
              _Subtitulo('Cómo funciona'),
              _Punto(
                  'Pedal derecho: siguiente. Pedal izquierdo: anterior. Pasa las hojas del himno y después al himno siguiente, como un libro.'),
              _Punto('Con ←/→ o ↑/↓ cambia de hoja directamente.'),
              _Punto(
                  'Con Re Pág/Av Pág, si la hoja no cabe completa en la pantalla, primero la recorre y después pasa a la siguiente.'),
              _Punto(
                  'Después de cada pisada espera 2 segundos antes de aceptar otra, para no pasar dos páginas por accidente.'),
              _Punto('Funciona dentro de un himno, no en la lista.'),
              _Subtitulo('Si deja de aparecer el teclado en pantalla'),
              _Punto(
                  'Android lo oculta porque cree que tienes un teclado físico conectado (el pedal). Se arregla una sola vez:'),
              _Punto(
                  'Samsung: Ajustes → Administración general → Teclado físico → activa "Mostrar teclado en pantalla".'),
              _Punto(
                  'Otros Android: busca "Teclado físico" en los Ajustes y activa la opción de mostrar el teclado en pantalla.'),
            ],
          ),
          _Seccion(
            icono: Icons.cloud_download_outlined,
            titulo: 'Sin internet y actualizaciones',
            contenido: [
              _Subtitulo('Descargar el himnario'),
              _Punto(
                  '"Descargar Himnario Localmente" guarda los himnos en el dispositivo (cerca de 170 MB, mejor con Wi-Fi). Después funciona sin internet.'),
              _Subtitulo('Verificar descargas (menú ⋮)'),
              _Punto(
                  'Si todavía no descargaste el himnario, te ofrece descargarlo.'),
              _Punto(
                  'Si ya lo descargaste, revisa con internet que no falte ninguna hoja en el dispositivo (el navegador puede borrar algunas si se queda sin espacio) y que cada hoja sea la versión más nueva publicada.'),
              _Punto(
                  'Si falta alguna o hay hojas nuevas o corregidas, te dice cuántas son y cuánto pesan, y baja solo esas.'),
              _Punto(
                  'Si todo está completo, te avisa: "Todo el himnario está descargado y al día".'),
              _Punto(
                  'Úsala antes de salir a un lugar sin internet, para asegurarte de tener todo.'),
              _Subtitulo('Actualizaciones'),
              _Punto(
                  'Cuando se corrige o se agrega una hoja, aparece un aviso para bajar solo esas hojas.'),
              _Punto(
                  'Cuando hay una versión nueva de la app aparece un aviso. Si eliges "Después", queda la opción "Actualizar APP" en el menú ⋮.'),
            ],
          ),
          _Seccion(
            icono: Icons.menu_book,
            titulo: 'Leer los himnos',
            contenido: [
              _Punto(
                  'Busca por número o por título; no importan los acentos. Ordena la lista por número o por nombre.'),
              _Punto(
                  'Dentro de un himno, desliza a los lados o usa < > para pasar de hoja o de himno. El buscador de arriba abre cualquier otro.'),
              _Punto('Junta o separa dos dedos para hacer zoom.'),
              _Punto(
                  'Con la tablet en horizontal la hoja se ve completa. Arrastra las barras de los costados para hacerla más grande o más chica; el tamaño se recuerda.'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final List<Widget> contenido;

  const _Seccion({
    required this.icono,
    required this.titulo,
    required this.contenido,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icono),
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      children: contenido,
    );
  }
}

class _Subtitulo extends StatelessWidget {
  final String texto;

  const _Subtitulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        texto,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _Texto extends StatelessWidget {
  final String texto;

  const _Texto(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(texto),
    );
  }
}

class _Punto extends StatelessWidget {
  final String texto;

  const _Punto(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
