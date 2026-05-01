import 'package:cloud_firestore/cloud_firestore.dart';

class PlaceNode {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String type; // ej. 'edificio', 'cafeteria', 'parque', 'salon'
  final String accessibilityLevel; // ej. 'alto', 'medio', 'bajo'

  PlaceNode({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.accessibilityLevel,
  });

  // Factory para parsear los documentos desde Firestore
  factory PlaceNode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    return PlaceNode(
      id: doc.id,
      name: data?['name'] ?? 'Sin nombre',
      latitude: (data?['latitude'] ?? 0.0).toDouble(),
      longitude: (data?['longitude'] ?? 0.0).toDouble(),
      type: data?['type'] ?? 'desconocido',
      accessibilityLevel: data?['accessibilityLevel'] ?? 'desconocido',
    );
  }

  // Útil para inicializaciones temporales o subidas de prueba
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'accessibilityLevel': accessibilityLevel,
    };
  }
}
