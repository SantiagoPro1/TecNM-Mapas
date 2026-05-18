import 'dart:ui' show Rect;

import 'package:equatable/equatable.dart';

/// Marcador reconocido (QR, ArUco, senalizacion) por el modulo NAVIA.
///
/// Extiende [Equatable] para evitar ciclos de renderizado en widgets
/// que observan la lista de marcadores via Riverpod.
class RecognizedMarker extends Equatable {
  /// Etiqueta o payload decodificado del marcador.
  final String label;

  /// Nivel de confianza de la deteccion (0.0 - 1.0).
  final double confidence;

  /// Rectangulo delimitador en coordenadas de la imagen de entrada.
  final Rect boundingBox;

  /// Tipo de marcador reconocido.
  final MarkerType type;

  const RecognizedMarker({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    this.type = MarkerType.unknown,
  });

  RecognizedMarker copyWith({
    String? label,
    double? confidence,
    Rect? boundingBox,
    MarkerType? type,
  }) {
    return RecognizedMarker(
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      boundingBox: boundingBox ?? this.boundingBox,
      type: type ?? this.type,
    );
  }

  @override
  List<Object?> get props => [label, confidence, boundingBox, type];

  @override
  String toString() =>
      'RecognizedMarker($label, ${type.name}, ${(confidence * 100).toStringAsFixed(1)}%)';
}

/// Tipos de marcador soportados por NAVIA.
enum MarkerType {
  qr,
  aruco,
  signage,
  unknown,
}
