import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// Fotograma convertido a formato RGB listo para inferencia TFLite.
///
/// Es un DTO ligero que viaja del [CameraFeedHandler] al [MlVisionService].
/// No extiende Equatable porque es un objeto transitorio de alto volumen
/// y comparar megabytes de bytes por frame seria contraproducente.
@immutable
class SensorFrame {
  /// Buffer RGB de 3 canales (R, G, B) sin alfa.
  /// Tamanio esperado: [width] * [height] * 3 bytes.
  final Uint8List bytes;

  /// Ancho del fotograma en pixeles.
  final int width;

  /// Alto del fotograma en pixeles.
  final int height;

  /// Marca temporal del fotograma original (microsegundos).
  final int timestampMicros;

  const SensorFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.timestampMicros,
  });
}
