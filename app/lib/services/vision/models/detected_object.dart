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
  /// bounding-box y el tamanio total del fotograma, adaptándolo según la categoría del objeto.
  static String estimateDistance(
      Rect box, double frameWidth, double frameHeight, {String? label}) {
    if (frameWidth <= 0 || frameHeight <= 0) return 'desconocido';

    final boxArea = box.width * box.height;
    final frameArea = frameWidth * frameHeight;
    final ratio = boxArea / frameArea;

    final lowerLabel = label?.toLowerCase() ?? '';

    // Categoría: Objetos Pequeños (mochilas, botellas, termos, celulares, laptops, libros, tijeras, etc.)
    if (lowerLabel == 'mochila' ||
        lowerLabel == 'paraguas' ||
        lowerLabel == 'bolso o mochila' ||
        lowerLabel == 'maleta o mochila' ||
        lowerLabel == 'botella de agua' ||
        lowerLabel == 'taza o termo' ||
        lowerLabel == 'laptop' ||
        lowerLabel == 'mouse de computadora' ||
        lowerLabel == 'control remoto' ||
        lowerLabel == 'teclado de computadora' ||
        lowerLabel == 'teléfono celular' ||
        lowerLabel == 'libro o libreta' ||
        lowerLabel == 'reloj de pared' ||
        lowerLabel == 'florero' ||
        lowerLabel == 'tijeras' ||
        lowerLabel == 'botella' ||
        lowerLabel == 'taza' ||
        lowerLabel == 'libro' ||
        lowerLabel == 'reloj') {
      if (ratio > 0.04) return 'inmediato';
      if (ratio > 0.015) return 'cercano';
      if (ratio > 0.005) return 'medio';
      return 'lejano';
    }

    // Categoría: Objetos Medianos (sillas, mesas, bancos, lavabos, etc.)
    if (lowerLabel == 'silla o banco' ||
        lowerLabel == 'sillón o sofá' ||
        lowerLabel == 'planta o maceta' ||
        lowerLabel == 'camilla o cama' ||
        lowerLabel == 'mesa o escritorio' ||
        lowerLabel == 'lavabo' ||
        lowerLabel == 'baño' ||
        lowerLabel == 'banca' ||
        lowerLabel == 'hidrante' ||
        lowerLabel == 'semáforo' ||
        lowerLabel == 'señal de alto' ||
        lowerLabel == 'silla' ||
        lowerLabel == 'sofa' ||
        lowerLabel == 'maceta' ||
        lowerLabel == 'cama' ||
        lowerLabel == 'mesa' ||
        lowerLabel == 'balón o pelota' ||
        lowerLabel == 'patineta') {
      if (ratio > 0.15) return 'inmediato';
      if (ratio > 0.06) return 'cercano';
      if (ratio > 0.02) return 'medio';
      return 'lejano';
    }

    // Categoría: Objetos Grandes / Estándar (personas, puertas, escaleras, barda, pared, etc.)
    if (ratio > 0.35) return 'inmediato';
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
