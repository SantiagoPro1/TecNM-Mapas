import 'package:equatable/equatable.dart';

/// Representa una conexión entre dos nodos del grafo del campus.
/// Las aristas son bidireccionales: si A->B existe, B->A también.
class CampusEdge extends Equatable {
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

  const CampusEdge({
    required this.from,
    required this.to,
    required this.distance,
    required this.accessible,
    required this.direction,
  });

  factory CampusEdge.fromJson(Map<String, dynamic> json) {
    return CampusEdge(
      from: json['from'] as String,
      to: json['to'] as String,
      distance: (json['distance'] as num).toDouble(),
      accessible: json['accessible'] as bool,
      direction: json['direction'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'distance': distance,
        'accessible': accessible,
        'direction': direction,
      };

  @override
  List<Object?> get props => [from, to];

  @override
  String toString() => 'CampusEdge($from → $to, ${distance}m)';
}
