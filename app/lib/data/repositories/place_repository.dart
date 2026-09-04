import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/models/venue.dart';

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
    try {
      await for (final snapshot in _placesCol(zoneId).snapshots()) {
        final places = snapshot.docs
            .map((d) => PlaceNode.fromFirestore(d, zoneId: zoneId))
            .toList();
        if (places.isNotEmpty) {
          yield places;
        } else if (venue.isBundled) {
          yield await _loadLocalPlaces(venue);
        } else {
          yield [_genericVenuePin(venue)];
        }
      }
    } catch (e) {
      debugPrint('PlaceRepository: error leyendo Firestore ($zoneId) → $e');
      yield venue.isBundled ? await _loadLocalPlaces(venue) : [_genericVenuePin(venue)];
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

  Future<void> createPlace(PlaceNode place) =>
      _placesCol(place.zoneId).doc(place.id).set(place.toMap());

  Future<void> updatePlace(PlaceNode place) =>
      _placesCol(place.zoneId).doc(place.id).update(place.toMap());

  /// Actualización parcial de solo lat/lng — para el arrastre en el editor,
  /// sin pisar el resto de los campos del punto.
  Future<void> movePlace(
    String zoneId,
    String placeId, {
    required double lat,
    required double lng,
  }) =>
      _placesCol(zoneId).doc(placeId).update({'latitude': lat, 'longitude': lng});

  /// Actualización parcial de solo el nombre — igual que [movePlace], sin
  /// pisar el resto de los campos.
  Future<void> renamePlace(String zoneId, String placeId, String name) =>
      _placesCol(zoneId).doc(placeId).update({'name': name});

  Future<void> deletePlace(String zoneId, String placeId) =>
      _placesCol(zoneId).doc(placeId).delete();

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
            'PlaceRepository: ${places.length} POIs sembrados para "${venue.id}" ✓');
      }
    }
  }
}
