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
  );

  // Morelos: 10 canchas repartidas (vóleibol, básquet, béisbol, atletismo,
  // natación, tenis de mesa) — única sede con alberca.
  static const Venue unidadMorelos = Venue(
    id: 'unidad_morelos',
    label: 'Unidad Morelos',
    shortDescription: '10 canchas · Multideporte',
    centerLat: 19.248455,
    centerLng: -103.702158,
    boundsSouthLat: 19.243196,
    boundsWestLng: -103.70773,
    boundsNorthLat: 19.253714,
    boundsEastLng: -103.696586,
    defaultZoom: 16.5,
    icon: Icons.pool_rounded,
  );

  // Gil Cabrera: 4 de 6 canchas son de Tochito.
  static const Venue gilCabrera = Venue(
    id: 'gil_cabrera',
    label: 'Gil Cabrera',
    shortDescription: 'Tochito · 4 canchas',
    centerLat: 19.267959,
    centerLng: -103.740471,
    boundsSouthLat: 19.263505,
    boundsWestLng: -103.745007,
    boundsNorthLat: 19.272414,
    boundsEastLng: -103.735936,
    defaultZoom: 17.0,
    icon: Icons.sports_football_rounded,
  );

  // IMSS: 5 canchas, una para cada disciplina — sin deporte dominante.
  static const Venue imss = Venue(
    id: 'imss',
    label: 'IMSS',
    shortDescription: '5 canchas · Multideporte',
    centerLat: 19.237561,
    centerLng: -103.737301,
    boundsSouthLat: 19.233069,
    boundsWestLng: -103.741478,
    boundsNorthLat: 19.242054,
    boundsEastLng: -103.733124,
    defaultZoom: 17.0,
    icon: Icons.sports_rounded,
  );

  // Coquimatlán: 3 de 4 canchas son de Fútbol Soccer. Municipio distinto a
  // Colima capital.
  static const Venue coquimatlan = Venue(
    id: 'coquimatlan',
    label: 'Coquimatlán',
    shortDescription: 'Fútbol · 3 canchas',
    centerLat: 19.217095,
    centerLng: -103.804856,
    boundsSouthLat: 19.213,
    boundsWestLng: -103.809441,
    boundsNorthLat: 19.22119,
    boundsEastLng: -103.80027,
    defaultZoom: 17.0,
    icon: Icons.sports_soccer_rounded,
  );

  // Gustavo Vázquez: 2 de 4 canchas son de Sóftbol.
  static const Venue gustavoVazquez = Venue(
    id: 'gustavo_vazquez',
    label: 'Gustavo Vázquez',
    shortDescription: 'Sóftbol · 2 canchas',
    centerLat: 19.290478,
    centerLng: -103.728803,
    boundsSouthLat: 19.285303,
    boundsWestLng: -103.734927,
    boundsNorthLat: 19.295653,
    boundsEastLng: -103.72268,
    defaultZoom: 16.0,
    icon: Icons.sports_baseball_rounded,
  );

  // Sur: sus 2 canchas son de Tenis.
  static const Venue sur = Venue(
    id: 'sur',
    label: 'Sur',
    shortDescription: 'Tenis · 2 canchas',
    centerLat: 19.217443,
    centerLng: -103.725445,
    boundsSouthLat: 19.213577,
    boundsWestLng: -103.729565,
    boundsNorthLat: 19.221309,
    boundsEastLng: -103.721324,
    defaultZoom: 17.5,
    icon: Icons.sports_tennis_rounded,
  );

  // UDIF: su única cancha es de Sóftbol.
  static const Venue udif = Venue(
    id: 'udif',
    label: 'UDIF',
    shortDescription: 'Sóftbol · 1 cancha',
    centerLat: 19.23583,
    centerLng: -103.705444,
    boundsSouthLat: 19.230978,
    boundsWestLng: -103.712024,
    boundsNorthLat: 19.240681,
    boundsEastLng: -103.698864,
    defaultZoom: 16.0,
    icon: Icons.sports_baseball_rounded,
  );

  // Ezona Militar (Complejo Galván, antes XX Zona Militar): su única cancha
  // es de Béisbol. Coordenadas verificadas contra Google Places API
  // ("Complejo Galván (Ex-Zona Militar)" → 19.243554, -103.712445), que
  // coincide exacto con lo que ya estaba aquí. OJO: OpenStreetMap ubica el
  // polígono de este complejo ~220m al sur; ese dato es el que está mal, no
  // este. Google no tiene ninguna instalación deportiva registrada dentro
  // del complejo, así que sus canchas (incluida la de béisbol) hay que
  // pinearlas a mano con el editor de admin.
  static const Venue ezonaMilitar = Venue(
    id: 'ezona_militar',
    label: 'Ezona Militar',
    shortDescription: 'Béisbol · 1 cancha',
    centerLat: 19.24196,
    centerLng: -103.712067,
    boundsSouthLat: 19.237223,
    boundsWestLng: -103.718143,
    boundsNorthLat: 19.246698,
    boundsEastLng: -103.705991,
    defaultZoom: 16.0,
    icon: Icons.sports_baseball_rounded,
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

  /// Punto medio de la caja que contiene a las 9 sedes, para encuadrar el
  /// mapa abierto de forma que todas queden a la vista al entrar.
  ///
  /// Es el centro de la caja envolvente, no el promedio de los centros: con
  /// 4 sedes juntas al norte y 1 sola en Coquimatlán (a ~9.5 km), el promedio
  /// se recarga al norte y deja Coquimatlán fuera de pantalla.
  static (double lat, double lng) centroDeTodasLasSedes() {
    var minLat = all.first.centerLat, maxLat = all.first.centerLat;
    var minLng = all.first.centerLng, maxLng = all.first.centerLng;
    for (final v in all) {
      if (v.centerLat < minLat) minLat = v.centerLat;
      if (v.centerLat > maxLat) maxLat = v.centerLat;
      if (v.centerLng < minLng) minLng = v.centerLng;
      if (v.centerLng > maxLng) maxLng = v.centerLng;
    }
    return ((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }
}
