// Identidad visual de cada punto del mapa: qué ícono le toca, de qué color, y
// qué imagen real lo representa.
//
// El ícono NO sale del campo `type` de Firestore, porque ese campo es muy
// grueso ("Cancha" cubre básquetbol, fútbol, tenis, voleibol y frontón por
// igual). Se deduce del nombre, que es donde realmente está la información
// ("Alberca Olímpica", "Cancha de Voleibol de Playa", "Pista de Atletismo").
// `type` queda como respaldo cuando el nombre no dice nada.
//
// La foto de cada punto la toma el comité y viaja dentro del APK
// (assets/places/<id del punto>.jpg). No se usan imágenes de Google: cada
// ficha abierta sería una llamada facturable, y sus términos no permiten
// guardarlas ni redistribuirlas. Ver assets/places/README.md.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/models/place_node.dart';

/// Categoría visual de un punto. Es una capa de presentación: agrupa los
/// muchos `type`/nombres posibles en los pocos grupos que de verdad se
/// distinguen de un vistazo en el mapa.
enum PlaceCategory {
  swimming,
  basketball,
  football,
  soccerSmall,
  baseball,
  volleyball,
  tennis,
  athletics,
  gym,
  martialArts,
  archery,
  cycling,
  generalSport,
  auditorium,
  building,
  food,
  medical,
  restroom,
  lockerRoom,
  water,
  registration,
  info,
  security,
  parking,
  transit,
  entrance,
  podium,
  park,
  generic,
}

class PlaceVisuals {
  PlaceVisuals._();

  /// Reglas nombre → categoría, en orden: la primera que coincide gana, así
  /// que lo específico va antes que lo genérico ("voleibol de playa" antes
  /// que "cancha", "fútbol rápido" antes que "fútbol").
  static const List<(List<String>, PlaceCategory)> _nameRules = [
    (['alberca', 'natacion', 'natación', 'clavados', 'piscina'],
        PlaceCategory.swimming),
    (['basquet', 'básquet', 'basquetbol', 'baloncesto', 'basketball'],
        PlaceCategory.basketball),
    (['beisbol', 'béisbol', 'baseball', 'softbol', 'sóftbol'],
        PlaceCategory.baseball),
    (['voleibol', 'volibol', 'voley', 'volley'], PlaceCategory.volleyball),
    (['tenis de mesa'], PlaceCategory.generalSport),
    (['tenis', 'fronton', 'frontón', 'frontenis', 'squash', 'raqueta'],
        PlaceCategory.tennis),
    (['futbol rapido', 'fútbol rápido', 'futbol rápido', 'soccer7', 'fut7',
      'sintetico', 'sintético'], PlaceCategory.soccerSmall),
    (['futbol', 'fútbol', 'soccer', 'rugby', 'americano'],
        PlaceCategory.football),
    // Ciclismo antes que atletismo: "Pista De Ciclismo" contiene "pista".
    (['ciclismo', 'bicicross', 'bmx'], PlaceCategory.cycling),
    (['atletismo', 'pista'], PlaceCategory.athletics),
    (['arqueria', 'arquería', 'tiro con arco'], PlaceCategory.archery),
    (['karate', 'taekwondo', 'judo', 'lucha', 'box', 'artes marciales'],
        PlaceCategory.martialArts),
    (['gimnasio', 'gym', 'halterofilia', 'pesas'], PlaceCategory.gym),
    (['auditorio', 'teatro', 'sala', 'pabellon', 'pabellón', 'domo'],
        PlaceCategory.auditorium),
    (['primeros auxilios', 'enfermeria', 'enfermería', 'medic', 'ambulancia',
      'cruz roja'], PlaceCategory.medical),
    (['cafeteria', 'cafetería', 'comedor', 'comida', 'cocina', 'restaurante'],
        PlaceCategory.food),
    (['hidratacion', 'hidratación', 'bebederos', 'agua'], PlaceCategory.water),
    (['bano', 'baño', 'sanitario', 'wc'], PlaceCategory.restroom),
    (['vestidor', 'regadera', 'duchas'], PlaceCategory.lockerRoom),
    (['registro', 'acreditacion', 'acreditación', 'inscripcion', 'inscripción'],
        PlaceCategory.registration),
    (['informacion', 'información', 'modulo', 'módulo'], PlaceCategory.info),
    (['seguridad', 'vigilancia', 'policia', 'policía'], PlaceCategory.security),
    (['estacionamiento', 'parking'], PlaceCategory.parking),
    (['transporte', 'abordaje', 'camion', 'camión', 'autobus', 'autobús',
      'parada'], PlaceCategory.transit),
    (['entrada', 'acceso', 'puerta', 'ingreso'], PlaceCategory.entrance),
    (['podio', 'premiacion', 'premiación'], PlaceCategory.podium),
    (['jardin', 'jardín', 'parque', 'plaza'], PlaceCategory.park),
    (['cancha', 'campo', 'estadio', 'deportiv', 'unidad'],
        PlaceCategory.generalSport),
    (['edificio', 'aula', 'laboratorio', 'biblioteca'], PlaceCategory.building),
  ];

  /// Respaldo por `type` de Firestore cuando el nombre no alcanzó.
  static const Map<String, PlaceCategory> _typeRules = {
    'cafetería': PlaceCategory.food,
    'cafeteria': PlaceCategory.food,
    'primeros auxilios': PlaceCategory.medical,
    'hidratación': PlaceCategory.water,
    'hidratacion': PlaceCategory.water,
    'baños': PlaceCategory.restroom,
    'banos': PlaceCategory.restroom,
    'vestidores': PlaceCategory.lockerRoom,
    'podio': PlaceCategory.podium,
    'estacionamiento': PlaceCategory.parking,
    'transporte': PlaceCategory.transit,
    'entrada': PlaceCategory.entrance,
    'registro': PlaceCategory.registration,
    'información': PlaceCategory.info,
    'informacion': PlaceCategory.info,
    'seguridad': PlaceCategory.security,
    'cancha': PlaceCategory.generalSport,
    'edificio': PlaceCategory.building,
  };

  /// Quita acentos para que "Básquetbol" y "Basquetbol" caigan en la misma
  /// regla — los datos vienen de fuentes distintas y no son consistentes.
  static String _normalize(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      buf.write(i >= 0 ? to[i] : ch);
    }
    return buf.toString();
  }

  static PlaceCategory categoryOf(PlaceNode place) =>
      categoryFor(name: place.name, type: place.type);

  static PlaceCategory categoryFor({required String name, String type = ''}) {
    final n = _normalize(name);
    for (final (keys, cat) in _nameRules) {
      for (final k in keys) {
        if (n.contains(_normalize(k))) return cat;
      }
    }
    final byType = _typeRules[_normalize(type)];
    if (byType != null) return byType;
    return PlaceCategory.generic;
  }

  static IconData iconOf(PlaceNode place) => iconFor(categoryOf(place));

  static IconData iconFor(PlaceCategory c) {
    switch (c) {
      case PlaceCategory.swimming:
        return Icons.pool_rounded;
      case PlaceCategory.basketball:
        return Icons.sports_basketball_rounded;
      case PlaceCategory.football:
        return Icons.sports_soccer_rounded;
      case PlaceCategory.soccerSmall:
        return Icons.sports_soccer_rounded;
      case PlaceCategory.baseball:
        return Icons.sports_baseball_rounded;
      case PlaceCategory.volleyball:
        return Icons.sports_volleyball_rounded;
      case PlaceCategory.tennis:
        return Icons.sports_tennis_rounded;
      case PlaceCategory.athletics:
        return Icons.directions_run_rounded;
      case PlaceCategory.gym:
        return Icons.fitness_center_rounded;
      case PlaceCategory.martialArts:
        return Icons.sports_mma_rounded;
      case PlaceCategory.archery:
        return Icons.my_location_rounded;
      case PlaceCategory.cycling:
        return Icons.directions_bike_rounded;
      case PlaceCategory.generalSport:
        return Icons.sports_rounded;
      case PlaceCategory.auditorium:
        return Icons.stadium_rounded;
      case PlaceCategory.building:
        return Icons.apartment_rounded;
      case PlaceCategory.food:
        return Icons.restaurant_rounded;
      case PlaceCategory.medical:
        return Icons.medical_services_rounded;
      case PlaceCategory.restroom:
        return Icons.wc_rounded;
      case PlaceCategory.lockerRoom:
        return Icons.checkroom_rounded;
      case PlaceCategory.water:
        return Icons.water_drop_rounded;
      case PlaceCategory.registration:
        return Icons.how_to_reg_rounded;
      case PlaceCategory.info:
        return Icons.info_rounded;
      case PlaceCategory.security:
        return Icons.security_rounded;
      case PlaceCategory.parking:
        return Icons.local_parking_rounded;
      case PlaceCategory.transit:
        return Icons.directions_bus_rounded;
      case PlaceCategory.entrance:
        return Icons.meeting_room_rounded;
      case PlaceCategory.podium:
        return Icons.workspace_premium_rounded;
      case PlaceCategory.park:
        return Icons.park_rounded;
      case PlaceCategory.generic:
        return Icons.place_rounded;
    }
  }

  static Color colorOf(PlaceNode place) => colorFor(categoryOf(place));

  static Color colorFor(PlaceCategory c) {
    switch (c) {
      case PlaceCategory.swimming:
      case PlaceCategory.basketball:
      case PlaceCategory.football:
      case PlaceCategory.soccerSmall:
      case PlaceCategory.baseball:
      case PlaceCategory.volleyball:
      case PlaceCategory.tennis:
      case PlaceCategory.athletics:
      case PlaceCategory.gym:
      case PlaceCategory.martialArts:
      case PlaceCategory.archery:
      case PlaceCategory.cycling:
      case PlaceCategory.generalSport:
      case PlaceCategory.park:
        return AppMapColors.poiSport;
      case PlaceCategory.food:
      case PlaceCategory.water:
        return AppMapColors.poiFood;
      case PlaceCategory.medical:
        return AppMapColors.poiMedical;
      case PlaceCategory.parking:
      case PlaceCategory.transit:
        return AppMapColors.poiTransit;
      case PlaceCategory.auditorium:
      case PlaceCategory.building:
      case PlaceCategory.restroom:
      case PlaceCategory.lockerRoom:
      case PlaceCategory.registration:
      case PlaceCategory.info:
      case PlaceCategory.security:
      case PlaceCategory.entrance:
      case PlaceCategory.podium:
      case PlaceCategory.generic:
        return AppMapColors.poiService;
    }
  }

  /// Etiqueta corta de la categoría, para mostrarla junto al nombre.
  static String labelOf(PlaceNode place) {
    switch (categoryOf(place)) {
      case PlaceCategory.swimming:
        return 'Alberca';
      case PlaceCategory.basketball:
        return 'Básquetbol';
      case PlaceCategory.football:
        return 'Fútbol';
      case PlaceCategory.soccerSmall:
        return 'Fútbol rápido';
      case PlaceCategory.baseball:
        return 'Béisbol';
      case PlaceCategory.volleyball:
        return 'Voleibol';
      case PlaceCategory.tennis:
        return 'Raqueta';
      case PlaceCategory.athletics:
        return 'Atletismo';
      case PlaceCategory.gym:
        return 'Gimnasio';
      case PlaceCategory.martialArts:
        return 'Artes marciales';
      case PlaceCategory.archery:
        return 'Tiro con arco';
      case PlaceCategory.cycling:
        return 'Ciclismo';
      case PlaceCategory.generalSport:
        return 'Área deportiva';
      case PlaceCategory.auditorium:
        return 'Auditorio';
      case PlaceCategory.building:
        return 'Edificio';
      case PlaceCategory.food:
        return 'Comida';
      case PlaceCategory.medical:
        return 'Primeros auxilios';
      case PlaceCategory.restroom:
        return 'Baños';
      case PlaceCategory.lockerRoom:
        return 'Vestidores';
      case PlaceCategory.water:
        return 'Hidratación';
      case PlaceCategory.registration:
        return 'Registro';
      case PlaceCategory.info:
        return 'Información';
      case PlaceCategory.security:
        return 'Seguridad';
      case PlaceCategory.parking:
        return 'Estacionamiento';
      case PlaceCategory.transit:
        return 'Transporte';
      case PlaceCategory.entrance:
        return 'Acceso';
      case PlaceCategory.podium:
        return 'Premiación';
      case PlaceCategory.park:
        return 'Área verde';
      case PlaceCategory.generic:
        return 'Punto de interés';
    }
  }
}

/// Foto propia de cada punto, empaquetada dentro del APK.
///
/// POR QUÉ NO SON DE GOOGLE
///
/// La primera versión traía la vista de Street View/satelital pidiéndosela en
/// vivo a las APIs estáticas de Google. Se ve bien, pero cada ficha abierta es
/// una llamada facturable: con 40,000 asistentes son cientos de dólares. Y las
/// imágenes de Google no se pueden guardar ni redistribuir, así que tampoco se
/// podían meter al APK para evitar el cobro.
///
/// La salida es usar fotos tomadas por el comité: viajan dentro de la app,
/// cuestan cero, funcionan sin señal y son legalmente propias. Ver
/// `assets/places/README.md` para la lista de archivos esperados.
class PlacePhoto {
  PlacePhoto._();

  static const String _carpeta = 'assets/places';
  static const String _carpetaCategorias = 'assets/categories';

  static Future<Set<String>>? _disponibles;

  /// Qué fotos trae realmente este APK. Se lee del manifiesto de assets una
  /// sola vez: así se pueden ir agregando fotos sin tocar nada de código, y
  /// un punto sin foto simplemente no la muestra.
  static Future<Set<String>> _rutasDisponibles() {
    return _disponibles ??= () async {
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        return manifest
            .listAssets()
            .where((a) =>
                a.startsWith('$_carpeta/') ||
                a.startsWith('$_carpetaCategorias/'))
            .toSet();
      } catch (e) {
        debugPrint('PlacePhoto: no se pudo leer el manifiesto de assets ($e)');
        return <String>{};
      }
    }();
  }

  /// Imagen que encabeza la ficha del punto, en orden de preferencia:
  ///
  ///  1. La foto real de ESE lugar, si el comité ya la tomó
  ///     (`assets/places/<id>.jpg`).
  ///  2. La ilustración de su categoría (`assets/categories/<categoría>.png`),
  ///     que dibuja el trazado de esa cancha — el diamante del béisbol, los
  ///     carriles de la alberca, el óvalo de la pista.
  ///
  /// Así la app se ve completa desde hoy, y cada foto real que llegue después
  /// reemplaza a su ilustración sin tocar una línea de código.
  static Future<String?> assetParaPunto(String placeId,
      [PlaceCategory? categoria]) async {
    final rutas = await _rutasDisponibles();
    for (final ext in const ['jpg', 'jpeg', 'png', 'webp']) {
      final ruta = '$_carpeta/$placeId.$ext';
      if (rutas.contains(ruta)) return ruta;
    }
    if (categoria != null) {
      for (final ext in const ['png', 'webp', 'jpg']) {
        final rutaCat = '$_carpetaCategorias/${categoria.name}.$ext';
        if (rutas.contains(rutaCat)) return rutaCat;
      }
    }
    return null;
  }
}

/// Banda con la foto del punto, para encabezar su ficha.
///
/// Nunca deja un hueco en blanco: si el punto todavía no tiene foto, muestra
/// el ícono de su categoría, que es información útil por sí sola.
class PlacePhotoBanner extends StatefulWidget {
  final PlaceNode place;
  final double height;

  const PlacePhotoBanner({super.key, required this.place, this.height = 150});

  @override
  State<PlacePhotoBanner> createState() => _PlacePhotoBannerState();
}

class _PlacePhotoBannerState extends State<PlacePhotoBanner> {
  late Future<String?> _asset;

  @override
  void initState() {
    super.initState();
    _asset = PlacePhoto.assetParaPunto(
        widget.place.id, PlaceVisuals.categoryOf(widget.place));
  }

  @override
  void didUpdateWidget(covariant PlacePhotoBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id) {
      _asset = PlacePhoto.assetParaPunto(
          widget.place.id, PlaceVisuals.categoryOf(widget.place));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final category = PlaceVisuals.categoryOf(widget.place);
    final accent = PlaceVisuals.colorFor(category);

    Widget sinFoto() => Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(PlaceVisuals.iconFor(category),
              size: 40, color: accent.withValues(alpha: 0.45)),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: widget.place.imageUrl != null
            ? Image.network(
                widget.place.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) => sinFoto(),
              )
            : FutureBuilder<String?>(
                future: _asset,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return sinFoto();
                  final ruta = snap.data;
                  if (ruta == null) return sinFoto();
                  return Image.asset(
                    ruta,
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => sinFoto(),
                  );
                },
              ),
      ),
    );
  }
}
