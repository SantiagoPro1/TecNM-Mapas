import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Representa un punto de interés (POI) visible en el mapa.
///
/// Extiende [Equatable] para garantizar inmutabilidad semántica
/// y comparaciones por valor sin overhead de hashCode manual.
class PlaceNode extends Equatable {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String type; // ej. 'Edificio', 'Cafetería', 'Parque', 'Servicios'
  final String accessibilityLevel; // ej. 'alto', 'medio', 'bajo'
  final String? letter; // Letra de identificación del edificio

  const PlaceNode({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.accessibilityLevel,
    this.letter,
  });

  /// Factory para parsear documentos desde Firestore.
  factory PlaceNode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    return PlaceNode(
      id: doc.id,
      name: data?['name'] as String? ?? 'Sin nombre',
      latitude: (data?['latitude'] as num? ?? 0.0).toDouble(),
      longitude: (data?['longitude'] as num? ?? 0.0).toDouble(),
      type: data?['type'] as String? ?? 'desconocido',
      accessibilityLevel:
          data?['accessibilityLevel'] as String? ?? 'desconocido',
    );
  }

  /// Serializa el nodo a un Map compatible con Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'accessibilityLevel': accessibilityLevel,
    };
  }

  @override
  List<Object?> get props =>
      [id, name, latitude, longitude, type, accessibilityLevel, letter];
}
