import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/models/venue.dart';
import 'package:navia/data/repositories/venue_bundle.dart';

class PlaceRepository {
  final FirebaseFirestore _firestore;

  PlaceRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _placesCol(String zoneId) =>
      _firestore.collection('venues').doc(zoneId).collection('places');

  /// Stream en tiempo real de los POIs de una sede.
  ///
  /// Sedes empaquetadas (por ahora, solo TecNM Colima): si Firestore aún
  /// no tiene datos para la sede (o no hay conexión), cae de vuelta al mapa
  /// local en assets/caché Hive — igual que el comportamiento offline-first
  /// del resto de la app.
  /// Sedes del Evento Nacional Deportivo (sin JSON empaquetado): mientras el
  /// admin no coloque POIs reales, se muestra un pin genérico en el centro
  /// de la sede (mejor que un mapa vacío) — desaparece solo en cuanto haya
  /// datos reales en Firestore.
  Stream<List<PlaceNode>> watchPlaces(String zoneId) async* {
    final venue = VenueRegistry.byId(zoneId);
    final delPaquete = await VenueBundle.places(zoneId);
    if (delPaquete.isNotEmpty) {
      yield delPaquete;
    }
    yield* _escucharFirestore(zoneId, venue);
  }

  /// Puntos en vivo desde Firestore, combinados de forma segura con el paquete
  /// local para garantizar que todas las canchas y edificios estén visibles.
  Stream<List<PlaceNode>> _escucharFirestore(String zoneId, Venue venue) async* {
    try {
      await for (final snapshot in _placesCol(zoneId).snapshots()) {
        final bundlePlaces = await VenueBundle.places(zoneId);
        final map = <String, PlaceNode>{};
        for (final p in bundlePlaces) {
          map[p.id] = p;
        }
        for (final d in snapshot.docs) {
          final data = d.data();
          if (data['deleted'] == true) {
            map.remove(d.id);
            continue;
          }
          final p = PlaceNode.fromFirestore(d, zoneId: zoneId);
          map[p.id] = p;
        }
        if (map.isNotEmpty) {
          yield map.values.toList();
        } else if (venue.isBundled) {
          yield await _loadLocalPlaces(venue);
        } else {
          yield [_genericVenuePin(venue)];
        }
      }
    } catch (e) {
      debugPrint('PlaceRepository: error leyendo Firestore ($zoneId) → $e');
      final respaldo = await VenueBundle.places(zoneId);
      if (respaldo.isNotEmpty) {
        yield respaldo;
      } else {
        yield venue.isBundled
            ? await _loadLocalPlaces(venue)
            : [_genericVenuePin(venue)];
      }
    }
  }

  /// Pin de respaldo para una sede que todavía no tiene POIs reales en
  /// Firestore — un solo marcador con el nombre de la sede en su centro.
  PlaceNode _genericVenuePin(Venue venue) => PlaceNode(
        id: '${venue.id}_centro',
        zoneId: venue.id,
        name: venue.label,
        latitude: venue.centerLat,
        longitude: venue.centerLng,
        type: 'Sede',
        accessibilityLevel: 'desconocido',
      );

  /// Carga los POIs de una sede empaquetada desde su JSON de assets
  /// (fallback offline/pre-siembra).
  Future<List<PlaceNode>> _loadLocalPlaces(Venue venue) async {
    try {
      final jsonStr = await rootBundle.loadString(venue.mapAssetPath!, cache: false);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      return _parseNodesFromMapData(venue.id, data);
    } catch (e) {
      debugPrint('PlaceRepository: error leyendo assets de ${venue.id} → $e');
      return const [];
    }
  }

  /// Parsea nodos-no-corredor desde el formato combinado { nodes: [...] }
  /// como POIs para mostrar en el mapa.
  List<PlaceNode> _parseNodesFromMapData(String zoneId, Map<String, dynamic> data) {
    final nodes = (data['nodes'] as List<dynamic>?) ?? [];
    return nodes
        .where((n) => (n as Map<String, dynamic>)['type'] != 'corridor')
        .map((n) {
      final node = n as Map<String, dynamic>;
      return PlaceNode(
        id: (node['id'] as String?) ?? '',
        zoneId: zoneId,
        name: (node['name'] as String?) ?? '',
        latitude: (node['lat'] as num?)?.toDouble() ?? 0.0,
        longitude: (node['lng'] as num?)?.toDouble() ?? 0.0,
        type: _resolveType(
          (node['id'] as String?) ?? '',
          (node['type'] as String?) ?? '',
        ),
        accessibilityLevel:
            (node['accessible'] as bool? ?? true) ? 'alto' : 'medio',
        letter: node['letter'] as String?,
      );
    }).toList();
  }

  static String _resolveType(String id, String nodeType) {
    if (id == 'edificio_c' || id == 'edificio_c1') return 'Cafetería';
    if (nodeType == 'building') return 'Edificio';
    if (nodeType == 'entrance') return 'Servicios';
    if (nodeType == 'area') return 'Parque';
    if (nodeType == 'service') return 'Servicios';
    return 'Edificio';
  }

  // ──────────────────────────────────────────────────────────
  //  Escritura (usada por el futuro editor de administrador)
  // ──────────────────────────────────────────────────────────

  // Cada escritura sube `dataVersion`: mientras no supere la del APK,
  // `watchPlaces` ignora Firestore y el cambio no se vería fuera del editor.
  Future<void> _publicar(Future<void> escritura) async {
    await escritura;
    await VenueDataVersion.publicarCambio(_firestore);
  }

  Future<void> createPlace(PlaceNode place) =>
      _publicar(_placesCol(place.zoneId).doc(place.id).set(place.toMap()));

  Future<void> updatePlace(PlaceNode place) =>
      _publicar(_placesCol(place.zoneId).doc(place.id).update(place.toMap()));

  /// Actualización parcial de solo lat/lng — para el arrastre en el editor,
  /// sin pisar el resto de los campos del punto.
  Future<void> movePlace(
    String zoneId,
    String placeId, {
    required double lat,
    required double lng,
  }) =>
      _publicar(_placesCol(zoneId)
          .doc(placeId)
          .update({'latitude': lat, 'longitude': lng}));

  /// Actualización parcial de solo el nombre — igual que [movePlace], sin
  /// pisar el resto de los campos.
  Future<void> renamePlace(String zoneId, String placeId, String name) =>
      _publicar(_placesCol(zoneId).doc(placeId).update({'name': name}));

  Future<void> deletePlace(String zoneId, String placeId) =>
      _publicar(_placesCol(zoneId).doc(placeId).set({'deleted': true}, SetOptions(merge: true)));

  /// Descarga una vez los POIs de TODAS las sedes para dejarlos en la caché
  /// local de Firestore.
  ///
  /// Sin esto, quien llega a una sede que nunca abrió con internet no ve
  /// nada si la red falla — justo el escenario del evento: 4000 personas
  /// saturando la red celular en una unidad deportiva. Con la caché tibia,
  /// `watchPlaces` sigue sirviendo datos aunque no haya señal.
  Future<void> prefetchAllVenuesForOffline() async {
    // Con el paquete vigente los datos ya están en el APK: bajarlos otra vez
    // sería pagar lecturas por algo que ya se tiene.
    if (await VenueDataVersion.paqueteVigente()) {
      debugPrint('PlaceRepository: precarga omitida (datos del APK vigentes)');
      return;
    }
    for (final venue in VenueRegistry.all) {
      try {
        await _placesCol(venue.id).get();
      } catch (e) {
        debugPrint('PlaceRepository: precarga falló para ${venue.id} → $e');
      }
    }
  }

  /// Siembra Firestore con los POIs de una sede (usado para migrar los datos
  /// locales de las 3 sedes empaquetadas la primera vez que se despliega
  /// esta versión, y por el editor de administrador para poblar sedes nuevas
  /// en bloque si hace falta).
  Future<void> seedPlacesForVenue(String zoneId, List<PlaceNode> places) async {
    final batch = _firestore.batch();
    for (final place in places) {
      batch.set(_placesCol(zoneId).doc(place.id), place.toMap());
    }
    await batch.commit();
  }

  /// Siembra Firestore con los POIs derivados de los mapas empaquetados
  /// (por ahora, solo TecNM Colima). Pensado para correrse una sola vez al
  /// migrar a esta versión, para que esas sedes empiecen con datos reales
  /// en Firestore en vez de depender solo del fallback local en cada carga.
  Future<void> seedBundledVenuesFromAssets() async {
    for (final venue in VenueRegistry.bundledVenues) {
      final places = await _loadLocalPlaces(venue);
      if (places.isNotEmpty) {
        await seedPlacesForVenue(venue.id, places);
        debugPrint(
            'PlaceRepository: ${places.length} POIs sembrados para "${venue.id}"');
      }
    }
  }
}
