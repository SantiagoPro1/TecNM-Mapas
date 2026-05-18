import 'package:flutter_svg/flutter_svg.dart';

/// Precarga todos los SVG del mapa en memoria para evitar parpadeos
/// al abrir el mapa. Debe llamarse en main.dart antes de runApp.
class PrecacheSvg {
  PrecacheSvg._();

  /// Lista de todos los assets SVG de marcadores del mapa.
  static const List<String> _allSvgAssets = [
    'assets/icons/svg/building.svg',
    'assets/icons/svg/entrance.svg',
    'assets/icons/svg/cafeteria.svg',
    'assets/icons/svg/park.svg',
    'assets/icons/svg/library.svg',
    'assets/icons/svg/lab.svg',
    'assets/icons/svg/sports.svg',
    'assets/icons/svg/parking.svg',
    'assets/icons/svg/cinema.svg',
    'assets/icons/svg/store.svg',
    'assets/icons/svg/gym.svg',
    'assets/icons/svg/medical.svg',
  ];

  /// Precarga todos los SVGs en caché durante el arranque de la app.
  /// Esto elimina el parpadeo de primer render en la pantalla del mapa.
  static Future<void> precacheAll() async {
    for (final path in _allSvgAssets) {
      final svgLoader = SvgAssetLoader(path);
      await svg.cache.putIfAbsent(
        svgLoader.cacheKey(null),
        () => svgLoader.loadBytes(null),
      );
    }
  }
}

/// Resuelve qué SVG usar según el ID y tipo del POI.
///
/// Reglas de resolución (de más específico a más genérico):
///  1. IDs que contengan patrones conocidos (cinemex, cinepolis, smartfit, etc.)
///  2. IDs de edificios especiales (edificio_b → biblioteca, edificio_c → cafetería)
///  3. Tipo del nodo (entrance, area, building)
class SvgMarkerHelper {
  SvgMarkerHelper._();

  /// Retorna la ruta del asset SVG apropiada para el POI dado.
  static String svgAssetForPoi({
    required String id,
    required String type,
    required String name,
  }) {
    final lid = id.toLowerCase();
    final ltype = type.toLowerCase();
    final lname = name.toLowerCase();

    // ── 1. Coincidencias por ID específico ──────────────────────────────────

    // Cines
    if (lid.contains('cinemex') || lid.contains('cinepolis')) {
      return 'assets/icons/svg/cinema.svg';
    }

    // Gimnasio
    if (lid.contains('smartfit') || lid.contains('smart_fit')) {
      return 'assets/icons/svg/gym.svg';
    }

    // Torre Médica
    if (lid.contains('torre_medica')) {
      return 'assets/icons/svg/medical.svg';
    }

    // Estacionamientos
    if (lid.contains('estacionamiento')) {
      return 'assets/icons/svg/parking.svg';
    }

    // Canchas / Campo de Fútbol
    if (lid.contains('campo_futbol') || lid.contains('canchas')) {
      return 'assets/icons/svg/sports.svg';
    }

    // Biblioteca (edificio_b → Centro de Información)
    if (lid == 'edificio_b' || lid.contains('biblioteca')) {
      return 'assets/icons/svg/library.svg';
    }

    // Cafeterías (edificio_c y c1)
    if (lid == 'edificio_c' ||
        lid == 'edificio_c1' ||
        lid.contains('starbucks')) {
      return 'assets/icons/svg/cafeteria.svg';
    }

    // Laboratorios (por nombre o por IDs de lab conocidos)
    if (lname.contains('lab') ||
        lname.contains('laboratorio') ||
        lid == 'edificio_e' || // Lab. Microbiología
        lid == 'edificio_g' || // Lab. Química
        lid == 'edificio_j' || // Lab. Bioquímica
        lid == 'edificio_l' || // Lab. Química Orgánica
        lid == 'edificio_m' || // Lab. Operaciones Unitarias
        lid == 'edificio_x' || // Lab. Ambiental
        lid == 'edificio_y' || // Lab. Mecatrónica
        lid == 'edificio_z') {
      // Banco de Reactivos
      return 'assets/icons/svg/lab.svg';
    }

    // ── 2. Coincidencias por tipo ──────────────────────────────────────────

    if (ltype == 'entrance' || ltype == 'entrada' || ltype == 'servicios') {
      return 'assets/icons/svg/entrance.svg';
    }
    if (ltype == 'cafetería' || ltype == 'cafeteria') {
      return 'assets/icons/svg/cafeteria.svg';
    }
    if (ltype == 'parque' || ltype == 'area') {
      return 'assets/icons/svg/park.svg';
    }

    // ── 3. Plazas comerciales → icono de tienda por defecto si es building
    //       dentro de Sendera o Zentralia
    if (lid.contains('sendera') || lid.contains('zentralia')) {
      return 'assets/icons/svg/store.svg';
    }

    // ── 4. Edificio genérico (fallback) ────────────────────────────────────
    return 'assets/icons/svg/building.svg';
  }
}
