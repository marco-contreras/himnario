class Himno {
  final String nombre;
  final int numero;

  Himno({
    required this.nombre,
    required this.numero,
  });

  factory Himno.fromJson(Map<String, dynamic> json) {
    return Himno(
      nombre: json['nombre'] as String,
      numero: json['numero'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'numero': numero,
    };
  }
}