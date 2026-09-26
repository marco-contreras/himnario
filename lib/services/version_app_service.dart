import 'red_web.dart';

/// Detecta si se publicó una versión nueva de la app. Cada publicación compila
/// la app con su commit (DESPLIEGUE) y deja el mismo valor en despliegue.txt
/// (ver .github/workflows/deploy.yml): si el publicado es otro, esta quedó
/// vieja. Sirve sobre todo para la app instalada que se queda abierta en
/// segundo plano, que no vuelve a cargar su código por sí sola.
class VersionAppService {
  static const String _despliegue = String.fromEnvironment('DESPLIEGUE');

  static Future<bool> hayVersionNueva() async {
    // Compilación local, sin commit: no hay con qué comparar.
    if (_despliegue.isEmpty) return false;
    final String? publicado =
        await RedWeb.leerSinCache(RedWeb.urlDelSitio('despliegue.txt'));
    final String? commit = publicado?.trim();
    return commit != null && commit.isNotEmpty && commit != _despliegue;
  }
}
