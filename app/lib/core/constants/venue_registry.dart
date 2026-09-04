import 'package:flutter/material.dart';
import 'package:navia/data/models/venue.dart';

/// Registro central de todas las sedes navegables en NAVIA.
///
/// Reemplaza las listas de archivos de mapa que antes estaban duplicadas en
/// `campus_graph.dart`, `map_cache_service.dart`, `place_repository.dart` y
/// la tupla hardcodeada de tarjetas en `home_screen.dart`.
///
/// TecNM Colima usa datos reales y su grafo caminable viene empaquetado en
/// `assets/maps/tec_colima_map.json`. Las 8 sedes del Evento Nacional
/// Deportivo del TecNM 2026 ya tienen coordenadas reales (confirmadas por el
/// usuario), pero todavía no tienen POIs ni grafo caminable — solo se les
/// muestra un pin genérico en su centro hasta que el editor de admin permita
/// levantarlas. El ícono/deporte y el conteo de canchas de cada una vienen de
/// la tabla "Canchas x Unidad Deportiva" del LXVIII Evento Nacional Deportivo
/// del TecNM 2026: se usa el deporte con más canchas en esa sede (o
/// "Multideporte" cuando está muy repartido entre varias disciplinas, como
/// Morelos o IMSS).
///
/// Sendera y Zentralia (centros comerciales, sin relación con el evento
/// deportivo) se sacaron del alcance de la app a petición del usuario — sus
/// JSON siguen en `assets/maps/` por si se retoman más adelante, pero ya no
/// se registran aquí ni se cargan en ningún lado.
class VenueRegistry {
  VenueRegistry._();

  static const Venue tecColima = Venue(
    id: 'tec_colima',
    label: 'TecNM Colima',
    shortDescription: '30+ edificios',
    mapAssetPath: 'assets/maps/tec_colima_map.json',
    centerLat: 19.2628,
    centerLng: -103.7233,
    boundsSouthLat: 19.2380,
    boundsWestLng: -103.7330,
    boundsNorthLat: 19.2710,
    boundsEastLng: -103.7050,
    defaultZoom: 17.0,
    icon: Icons.school_rounded,
    color: Color(0xFF38BDF8),
  );

  // Morelos: 10 canchas repartidas (vóleibol, básquet, béisbol, atletismo,
  // natación, tenis de mesa) — única sede con alberca.
  static const Venue unidadMorelos = Venue(
    id: 'unidad_morelos',
    label: 'Unidad Morelos',
    shortDescription: '10 canchas · Multideporte',
    centerLat: 19.249242,
    centerLng: -103.703654,
    boundsSouthLat: 19.243242,
    boundsWestLng: -103.710654,
    boundsNorthLat: 19.255242,
    boundsEastLng: -103.696654,
    defaultZoom: 16.0,
    icon: Icons.pool_rounded,
    color: Color(0xFF00E676),
  );

  // Gil Cabrera: 4 de 6 canchas son de Tochito.
  static const Venue gilCabrera = Venue(
    id: 'gil_cabrera',
    label: 'Gil Cabrera',
    shortDescription: 'Tochito · 4 canchas',
    centerLat: 19.267265,
    centerLng: -103.740571,
    boundsSouthLat: 19.261265,
    boundsWestLng: -103.747571,
    boundsNorthLat: 19.273265,
    boundsEastLng: -103.733571,
    defaultZoom: 16.0,
    icon: Icons.sports_football_rounded,
    color: Color(0xFF00BCD4),
  );

  // IMSS: 5 canchas, una para cada disciplina — sin deporte dominante.
  static const Venue imss = Venue(
    id: 'imss',
    label: 'IMSS',
    shortDescription: '5 canchas · Multideporte',
    centerLat: 19.238240,
    centerLng: -103.736741,
    boundsSouthLat: 19.232240,
    boundsWestLng: -103.743741,
    boundsNorthLat: 19.244240,
    boundsEastLng: -103.729741,
    defaultZoom: 16.0,
    icon: Icons.sports_rounded,
    color: Color(0xFFFF7043),
  );

  // Coquimatlán: 3 de 4 canchas son de Fútbol Soccer. Municipio distinto a
  // Colima capital.
  static const Venue coquimatlan = Venue(
    id: 'coquimatlan',
    label: 'Coquimatlán',
    shortDescription: 'Fútbol · 3 canchas',
    centerLat: 19.216703,
    centerLng: -103.804600,
    boundsSouthLat: 19.210703,
    boundsWestLng: -103.811600,
    boundsNorthLat: 19.222703,
    boundsEastLng: -103.797600,
    defaultZoom: 16.0,
    icon: Icons.sports_soccer_rounded,
    color: Color(0xFFAB47BC),
  );

  // Gustavo Vázquez: 2 de 4 canchas son de Sóftbol.
  static const Venue gustavoVazquez = Venue(
    id: 'gustavo_vazquez',
    label: 'Gustavo Vázquez',
    shortDescription: 'Sóftbol · 2 canchas',
    centerLat: 19.291975,
    centerLng: -103.729561,
    boundsSouthLat: 19.285975,
    boundsWestLng: -103.736561,
    boundsNorthLat: 19.297975,
    boundsEastLng: -103.722561,
    defaultZoom: 16.0,
    icon: Icons.sports_baseball_rounded,
    color: Color(0xFFFFCA28),
  );

  // Sur: sus 2 canchas son de Tenis.
  static const Venue sur = Venue(
    id: 'sur',
    label: 'Sur',
    shortDescription: 'Tenis · 2 canchas',
    centerLat: 19.216721,
    centerLng: -103.725576,
    boundsSouthLat: 19.210721,
    boundsWestLng: -103.732576,
    boundsNorthLat: 19.222721,
    boundsEastLng: -103.718576,
    defaultZoom: 16.0,
    icon: Icons.sports_tennis_rounded,
    color: Color(0xFF5C6BC0),
  );

  // UDIF: su única cancha es de Sóftbol.
  static const Venue udif = Venue(
    id: 'udif',
    label: 'UDIF',
    shortDescription: 'Sóftbol · 1 cancha',
    centerLat: 19.235040,
    centerLng: -103.705402,
    boundsSouthLat: 19.229040,
    boundsWestLng: -103.712402,
    boundsNorthLat: 19.241040,
    boundsEastLng: -103.698402,
    defaultZoom: 16.0,
    icon: Icons.sports_baseball_rounded,
    color: Color(0xFFEC407A),
  );

  // Ezona Militar (Complejo Galván): su única cancha es de Béisbol.
  static const Venue ezonaMilitar = Venue(
    id: 'ezona_militar',
    label: 'Ezona Militar',
    shortDescription: 'Béisbol · 1 cancha',
    centerLat: 19.243554,
    centerLng: -103.712445,
    boundsSouthLat: 19.237554,
    boundsWestLng: -103.719445,
    boundsNorthLat: 19.249554,
    boundsEastLng: -103.705445,
    defaultZoom: 16.0,
    icon: Icons.sports_baseball_rounded,
    color: Color(0xFF26A69A),
  );

  /// Todas las sedes registradas.
  static const List<Venue> all = [
    tecColima,
    unidadMorelos,
    gilCabrera,
    imss,
    coquimatlan,
    gustavoVazquez,
    sur,
    udif,
    ezonaMilitar,
  ];

  /// Solo las sedes con grafo empaquetado en assets (por ahora, solo TecNM
  /// Colima — Sendera/Zentralia se sacaron del alcance de la app).
  static List<Venue> get bundledVenues => all.where((v) => v.isBundled).toList();

  static Venue byId(String id) =>
      all.firstWhere((v) => v.id == id, orElse: () => tecColima);
}
