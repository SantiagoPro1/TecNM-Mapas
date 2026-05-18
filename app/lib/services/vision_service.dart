import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class VisionService {
  late ImageLabeler _imageLabeler;
  bool _isInitialized = false;

  VisionService() {
    // Inicialización del etiquetador de imágenes base (On-Device, Offline)
    // El umbral (confidenceThreshold) a 0.65 asegura que solo detecte con alta seguridad
    final options = ImageLabelerOptions(confidenceThreshold: 0.65);
    _imageLabeler = ImageLabeler(options: options);
    _isInitialized = true;
  }

  /// Procesa un InputImage (Fotograma de la cámara) y retorna la lista de etiquetas.
  /// En el entorno de producción (TRL 5), esto se conectará al Stream de la cámara.
  Future<List<ImageLabel>> analyzeCameraFrame(InputImage inputImage) async {
    if (!_isInitialized) return [];

    try {
      final List<ImageLabel> labels =
          await _imageLabeler.processImage(inputImage);

      for (ImageLabel label in labels) {
        final text = label.label.toLowerCase();

        // Filtramos etiquetas que sean muy relevantes para la navegación accesible
        if (text.contains('door') || text.contains('stairs')) {
          debugPrint('¡ALERTA CRÍTICA: ${label.label} detectada!');
        } else if (text.contains('elevator') || text.contains('building')) {
          debugPrint('Info: ${label.label} en vista.');
        }
      }
      return labels;
    } catch (e) {
      debugPrint('Error en analyzeCameraFrame (ML Kit): $e');
      return [];
    }
  }

  void dispose() {
    if (_isInitialized) {
      _imageLabeler.close();
      _isInitialized = false;
    }
  }
}
