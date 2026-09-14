import 'package:equatable/equatable.dart';

/// Representa una conexión entre dos nodos del grafo del campus.
/// Las aristas son bidireccionales: si A->B existe, B->A también.
class CampusEdge extends Equatable {
  /// Sede a la que pertenece esta arista.
  final String zoneId;

  /// ID del nodo de origen.
  final String from;

  /// ID del nodo de destino.
  final String to;

  /// Distancia en metros entre ambos nodos.
  final double distance;

  /// ¿Es accesible? (sin escaleras, con rampa o elevador).
  final bool accessible;

  /// Instrucción de dirección para guía por voz (ej. "Gira a la derecha").
  final String direction;

  /// Puntos intermedios de la ruta (curvas/caminos reales) decodificados.
  final List<List<double>>? polylinePoints;

  const CampusEdge({
    required this.zoneId,
    required this.from,
    required this.to,
    required this.distance,
    required this.accessible,
    required this.direction,
    this.polylinePoints,
  });

  /// Id determinístico para usar como id de documento en Firestore
  /// (las aristas no tienen una llave natural propia).
  String get docId => buildDocId(from, to);

  static String buildDocId(String from, String to) => '${from}__$to';

  factory CampusEdge.fromJson(Map<String, dynamic> json, {String zoneId = ''}) {
    List<List<double>>? points;
    if (json['polylinePoints'] != null) {
      points = (json['polylinePoints'] as List)
          .map((e) => (e as List).map((n) => (n as num).toDouble()).toList())
          .toList();
    }
    return CampusEdge(
      zoneId: (json['zoneId'] as String?) ?? zoneId,
      from: (json['from'] as String?) ?? '',
      to: (json['to'] as String?) ?? '',
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      accessible: (json['accessible'] as bool?) ?? true,
      direction: (json['direction'] as String?) ??
          (json['description'] as String?) ??
          '',
      polylinePoints: points,
    );
  }

  /// Deserializa desde un documento de Firestore (`venues/{zoneId}/edges/{docId}`).
  factory CampusEdge.fromFirestoreMap(String zoneId, Map<String, dynamic> data) {
    List<List<double>>? points;
    if (data['polylinePoints'] != null) {
      points = (data['polylinePoints'] as List)
          .map((e) => (e as List).map((n) => (n as num).toDouble()).toList())
          .toList();
    }
    return CampusEdge(
      zoneId: zoneId,
      from: (data['from'] as String?) ?? '',
      to: (data['to'] as String?) ?? '',
      distance: (data['distance'] as num?)?.toDouble() ?? 0.0,
      accessible: (data['accessible'] as bool?) ?? true,
      direction: (data['direction'] as String?) ?? '',
      polylinePoints: points,
    );
  }

  Map<String, dynamic> toJson() => {
        'zoneId': zoneId,
        'from': from,
        'to': to,
        'distance': distance,
        'accessible': accessible,
        'direction': direction,
        if (polylinePoints != null) 'polylinePoints': polylinePoints,
      };

  /// Serializa a un Map para Firestore (sin `zoneId`: ya está en la ruta de la colección).
  Map<String, dynamic> toFirestoreMap() => {
        'from': from,
        'to': to,
        'distance': distance,
        'accessible': accessible,
        'direction': direction,
        if (polylinePoints != null) 'polylinePoints': polylinePoints,
      };

  @override
  List<Object?> get props => [zoneId, from, to];

  @override
  String toString() => 'CampusEdge($from → $to, ${distance}m)';
}
