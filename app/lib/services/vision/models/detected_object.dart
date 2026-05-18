import 'dart:ui' show Rect;

import 'package:equatable/equatable.dart';

/// Objeto detectado por el pipeline de vision asistida NAVIA.
///
/// Extiende [Equatable] para que Riverpod/Flutter no dispare
/// rebuilds innecesarios cuando los valores no cambian.
class DetectedObject extends Equatable {
  /// Etiqueta legible del objeto (ej. "puerta", "escalera").
  final String label;

  /// Nivel de confianza del modelo (0.0 - 1.0).
  final double confidence;

  /// Rectangulo delimitador en coordenadas de la imagen de entrada.
  final Rect boundingBox;

  /// Distancia heuristica estimada al objeto.
  ///
  /// Se calcula a partir del area relativa del bounding-box
  /// respecto al tamanio del fotograma. Los valores posibles son:
  /// - `"inmediato"` : > 40 % del area del fotograma
  /// - `"cercano"`   : 15 % - 40 %
  /// - `"medio"`     : 5 % - 15 %
  /// - `"lejano"`    : < 5 %
  /// - `"desconocido"` : no se pudo calcular
  final String distance;

  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    this.distance = 'desconocido',
  });

  /// Calcula la distancia heuristica a partir de las dimensiones del
  /// bounding-box y el tamanio total del fotograma.
  static String estimateDistance(
      Rect box, double frameWidth, double frameHeight) {
    if (frameWidth <= 0 || frameHeight <= 0) return 'desconocido';

    final boxArea = box.width * box.height;
    final frameArea = frameWidth * frameHeight;
    final ratio = boxArea / frameArea;

    if (ratio > 0.40) return 'inmediato';
    if (ratio > 0.15) return 'cercano';
    if (ratio > 0.05) return 'medio';
    return 'lejano';
  }

  DetectedObject copyWith({
    String? label,
    double? confidence,
    Rect? boundingBox,
    String? distance,
  }) {
    return DetectedObject(
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      boundingBox: boundingBox ?? this.boundingBox,
      distance: distance ?? this.distance,
    );
  }

  @override
  List<Object?> get props => [label, confidence, boundingBox, distance];

  @override
  String toString() =>
      'DetectedObject($label, ${(confidence * 100).toStringAsFixed(1)}%, $distance)';
}
