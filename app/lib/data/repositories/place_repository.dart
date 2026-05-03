import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sinait/data/models/place_node.dart';

class PlaceRepository {
  final FirebaseFirestore _firestore;

  PlaceRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Carga los lugares desde el JSON local del campus como fuente primaria.
  /// Si Firestore tiene datos, los superpone encima del local.
  Stream<List<PlaceNode>> watchPlaces() async* {
    final localPlaces = await _loadLocalPlaces();
    yield localPlaces;

  }

  Future<List<PlaceNode>> _loadLocalPlaces() async {
    final mapFiles = [
      'assets/maps/tec_colima_map.json',
      'assets/maps/sendera_map.json',
      'assets/maps/zentralia_map.json',
    ];

    final allPlaces = <PlaceNode>[];

    for (final file in mapFiles) {
      try {
        final jsonStr = await rootBundle.loadString(file, cache: false);
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        final nodes = (data['nodes'] as List<dynamic>?) ?? [];
        final places = nodes
            .where((n) => (n as Map<String, dynamic>)['type'] != 'corridor')
            .map((n) {
              final node = n as Map<String, dynamic>;
              return PlaceNode(
                  id: (node['id'] as String?) ?? '',
                  name: (node['name'] as String?) ?? '',
                  latitude: (node['lat'] as num?)?.toDouble() ?? 0.0,
                  longitude: (node['lng'] as num?)?.toDouble() ?? 0.0,
                  type: _resolveType((node['id'] as String?) ?? '', (node['type'] as String?) ?? ''),
                  accessibilityLevel:
                      (node['accessible'] as bool? ?? true) ? 'alto' : 'medio',
                  letter: node['letter'] as String?,
                );
            })
            .toList();
        allPlaces.addAll(places);
      } catch (e) {
        // Si un archivo falla, continúa con los demás
        continue;
      }
    }

    return allPlaces;
  }

  static String _resolveType(String id, String nodeType) {
    if (id == 'edificio_c' || id == 'edificio_c1') return 'Cafetería';
    if (nodeType == 'building') return 'Edificio';
    if (nodeType == 'entrance') return 'Servicios';
    if (nodeType == 'area') return 'Parque';
    if (nodeType == 'service') return 'Servicios';
    return 'Edificio';
  }

  // Método para poblar la base de datos (Seeding)
  Future<void> seedData() async {
    final List<Map<String, dynamic>> places = [
      {
        "id": "tec_p",
        "name": "Edificio P (Académico)",
        "latitude": 19.2438,
        "longitude": -103.7037,
        "type": "Edificio",
        "accessibilityLevel": "alto",
        "audioDescription": "Edificio P. Cuenta con rampas de acceso y pasillos amplios."
      },
      {
        "id": "tec_a",
        "name": "Edificio A (Administrativo)",
        "latitude": 19.2432,
        "longitude": -103.7035,
        "type": "Edificio",
        "accessibilityLevel": "alto",
        "audioDescription": "Edificio A. Oficinas administrativas con acceso nivelado."
      },
      {
        "id": "tec_biblioteca",
        "name": "Biblioteca Central",
        "latitude": 19.2441,
        "longitude": -103.7039,
        "type": "Edificio",
        "accessibilityLevel": "alto",
        "audioDescription": "Biblioteca Central. Punto de referencia con elevador y rampas."
      },
      {
        "id": "tec_cafeteria",
        "name": "Cafetería Norte",
        "latitude": 19.2443,
        "longitude": -103.7042,
        "type": "Cafetería",
        "accessibilityLevel": "medio",
        "audioDescription": "Cafetería Norte. Acceso lateral recomendado para sillas de ruedas."
      },
      {
        "id": "tec_computo",
        "name": "Laboratorio de Cómputo",
        "latitude": 19.2445,
        "longitude": -103.7035,
        "type": "Edificio",
        "accessibilityLevel": "alto",
        "audioDescription": "Centro de Cómputo. Instalaciones modernas y accesibles."
      },
      {
        "id": "tec_canchas",
        "name": "Canchas Techadas",
        "latitude": 19.2446,
        "longitude": -103.7040,
        "type": "Parque",
        "accessibilityLevel": "alto",
        "audioDescription": "Área deportiva. Superficie plana ideal para tránsito libre."
      },
      {
        "id": "tec_direccion",
        "name": "Dirección General",
        "latitude": 19.2430,
        "longitude": -103.7038,
        "type": "Servicios",
        "accessibilityLevel": "alto",
        "audioDescription": "Dirección. Entrada principal con rampa reglamentaria."
      }
    ];

    final batch = _firestore.batch();
    for (var place in places) {
      final docRef = _firestore.collection('places').doc(place['id']);
      batch.set(docRef, place);
    }
    await batch.commit();
  }
}
