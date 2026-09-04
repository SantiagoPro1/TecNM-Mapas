import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Representa un punto de interés (POI) visible en el mapa.
///
/// Extiende [Equatable] para garantizar inmutabilidad semántica
/// y comparaciones por valor sin overhead de hashCode manual.
class PlaceNode extends Equatable {
  final String id;
  final String zoneId;
  final String name;
  final double latitude;
  final double longitude;
  final String type; // ej. 'Edificio', 'Cafetería', 'Parque', 'Servicios'
  final String accessibilityLevel; // ej. 'alto', 'medio', 'bajo'
  final String? letter; // Letra de identificación del edificio

  const PlaceNode({
    required this.id,
    this.zoneId = '',
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.accessibilityLevel,
    this.letter,
  });

  /// Factory para parsear documentos desde Firestore.
  ///
  /// [zoneId] es el default inyectado por el repositorio (la sede de la
  /// subcolección leída); un `zoneId` explícito en el propio documento
  /// tiene prioridad si existe.
  factory PlaceNode.fromFirestore(DocumentSnapshot doc, {String zoneId = ''}) {
    final data = doc.data() as Map<String, dynamic>?;

    return PlaceNode(
      id: doc.id,
      zoneId: data?['zoneId'] as String? ?? zoneId,
      name: data?['name'] as String? ?? 'Sin nombre',
      latitude: (data?['latitude'] as num? ?? 0.0).toDouble(),
      longitude: (data?['longitude'] as num? ?? 0.0).toDouble(),
      type: data?['type'] as String? ?? 'desconocido',
      accessibilityLevel:
          data?['accessibilityLevel'] as String? ?? 'desconocido',
      letter: data?['letter'] as String?,
    );
  }

  /// Serializa el nodo a un Map compatible con Firestore.
  Map<String, dynamic> toMap() {
    return {
      'zoneId': zoneId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'accessibilityLevel': accessibilityLevel,
      'letter': letter,
    };
  }

  PlaceNode copyWith({
    String? name,
    double? latitude,
    double? longitude,
    String? type,
    String? accessibilityLevel,
    String? letter,
  }) {
    return PlaceNode(
      id: id,
      zoneId: zoneId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      accessibilityLevel: accessibilityLevel ?? this.accessibilityLevel,
      letter: letter ?? this.letter,
    );
  }

  @override
  List<Object?> get props =>
      [id, zoneId, name, latitude, longitude, type, accessibilityLevel, letter];
}
