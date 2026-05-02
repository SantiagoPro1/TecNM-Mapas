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
    final jsonStr =
        await rootBundle.loadString('assets/maps/tec_colima_map.json', cache: false);
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final nodes = data['nodes'] as List<dynamic>;
    return nodes
        .where((n) => n['type'] != 'corridor')
        .map((n) => PlaceNode(
              id: n['id'] as String,
              name: n['name'] as String,
              latitude: (n['lat'] as num).toDouble(),
              longitude: (n['lng'] as num).toDouble(),
              type: _resolveType(n['id'] as String, n['type'] as String),
              accessibilityLevel:
                  (n['accessible'] as bool? ?? true) ? 'alto' : 'medio',
            ))
        .toList();
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
