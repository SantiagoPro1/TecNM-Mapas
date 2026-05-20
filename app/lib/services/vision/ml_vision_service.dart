import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:navia/services/vision/models/detected_object.dart';
import 'package:navia/services/vision/models/sensor_frame.dart';
import 'package:navia/services/vision/model_manager_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ---------------------------------------------------------------------------
// Constantes del modelo SSD MobileNet (COCO)
// ---------------------------------------------------------------------------

/// Subconjunto de clases COCO relevantes para navegacion accesible en escuela.
///
/// IMPORTANTE: Los IDs son 1-indexed para coincidir con el archivo
/// coco_labels.txt (person=1, bicycle=2, car=3, etc.).
const Map<int, String> _kNavLabels = {
  1: 'persona',
  2: 'bicicleta',
  3: 'automóvil',
  4: 'motocicleta',
  6: 'autobús',
  8: 'camión',
  10: 'semáforo',
  11: 'hidrante',
  13: 'señal de alto',
  14: 'parquímetro',
  15: 'banca',
  17: 'gato',
  18: 'perro',
  27: 'mochila',
  28: 'paraguas',
  31: 'bolso o mochila',
  33: 'maleta o mochila',
  37: 'balón o pelota',
  44: 'botella de agua',
  47: 'taza o termo',
  62: 'silla o banco',
  63: 'sillón o sofá',
  64: 'planta o maceta',
  65: 'camilla o cama',
  67: 'mesa o escritorio',
  70: 'baño',
  72: 'pantalla o proyector',
  73: 'computadora portátil',
  74: 'mouse de computadora',
  75: 'control remoto',
  76: 'teclado de computadora',
  77: 'teléfono celular',
  78: 'microondas',
  81: 'lavabo',
  82: 'casillero o archivero', // REFRIGERADOR -> CASILLERO
  84: 'libro o libreta',
  85: 'reloj de pared',
  86: 'florero',
  87: 'tijeras',

  // Clases personalizadas (fine-tuned)
  88: 'pared',
  89: 'escaleras',
  90: 'escalones',
  91: 'puerta',
  92: 'ventana',
  93: 'bardas',
  94: 'jardin',
  95: 'terreno elevado',
  96: 'terreno muy elevado',
};

// ---------------------------------------------------------------------------
// Contrato base (interfaz)
// ---------------------------------------------------------------------------

/// Contrato para el servicio de inferencia ML.
abstract class MlVisionService {
  /// Ejecuta la inferencia sobre un fotograma ya convertido a RGB.
  Future<void> processFrame(SensorFrame frame);

  /// Libera recursos del modelo (interpretes, buffers, etc.).
  void dispose();
}

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

typedef OnDetectionResult = void Function(List<DetectedObject> objects);
typedef OnVisionError = void Function(String errorMessage);

// ---------------------------------------------------------------------------
// Implementacion concreta: TFLite Obstacle Detector
// ---------------------------------------------------------------------------

/// Orquestador de inferencia TFLite para deteccion de obstaculos en NAVIA.
class TfliteObstacleDetector implements MlVisionService {
  // -- Dependencias ----------------------------------------------------------

  final OnDetectionResult _onResult;
  final OnVisionError _onError;

  // -- Estado interno --------------------------------------------------------

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  bool _mounted = false;
  bool _isQuantized = false;

  int _inputSizeWidth = 300;
  int _inputSizeHeight = 300;
  int _maxDetections = 10;
  static const int _kNumChannels = 3;

  /// Umbral dinámico que se modifica adaptativamente según el aprendizaje
  double dynamicConfidenceThreshold = 0.30;

  List<DetectedObject> _lastDetections = const [];
  int _emptyFrameCount = 0;
  static const int _kEmptyFrameThreshold = 5;

  // -- Constructor -----------------------------------------------------------

  TfliteObstacleDetector({
    required OnDetectionResult onResult,
    required OnVisionError onError,
  })  : _onResult = onResult,
        _onError = onError;

  // -- Getters ---------------------------------------------------------------

  bool get isReady => _interpreter != null && _mounted;
  int get inputSizeWidth => _inputSizeWidth;
  int get inputSizeHeight => _inputSizeHeight;

  // -- Ciclo de vida ---------------------------------------------------------

  Future<bool> initialize(ModelManagerService modelManager) async {
    try {
      _interpreter = await modelManager.loadModel('obstacles_detector.tflite');

      if (_interpreter == null) {
        throw Exception('El servicio devolvio null al cargar el modelo.');
      }

      _mounted = true;

      // Configurar parámetros del modelo
      final inputTensors = _interpreter!.getInputTensors();
      if (inputTensors.isNotEmpty) {
        final inputType = inputTensors.first.type;
        _isQuantized = inputType.toString().toLowerCase().contains('uint8');

        final inputShape = inputTensors.first.shape;
        if (inputShape.length >= 3) {
          _inputSizeHeight = inputShape[1];
          _inputSizeWidth = inputShape[2];
        }
      }

      final outputTensors = _interpreter!.getOutputTensors();
      if (outputTensors.isNotEmpty) {
        final outputShape = outputTensors.first.shape;
        if (outputShape.length >= 2) {
          _maxDetections = outputShape[1];
        }
      }

      // Crear intérprete asíncrono para ejecutar la inferencia en un isolate de fondo
      _isolateInterpreter = await IsolateInterpreter.create(address: _interpreter!.address);

      debugPrint(
        'TfliteObstacleDetector: modelo cargado '
        '(quantized: $_isQuantized, '
        'input: ${_interpreter!.getInputTensors()}, '
        'output: ${_interpreter!.getOutputTensors()})',
      );
      return true;
    } catch (e) {
      debugPrint('TfliteObstacleDetector: error cargando modelo - $e');
      _onError(
        'No se pudo cargar el modelo de deteccion. '
        'Activando modo Solo Voz como respaldo.',
      );
      return false;
    }
  }

  // -- MlVisionService -------------------------------------------------------

  @override
  Future<void> processFrame(SensorFrame frame) async {
    if (!_mounted || _interpreter == null || _isolateInterpreter == null) return;

    try {
      // 1. Pre-procesamiento veloz usando listas planas (Float32List/Uint8List)
      final input =
          _isQuantized ? _preprocessUint8Fast(frame) : _preprocessFloatFast(frame);
      if (!_mounted) return;

      // 2. Preparar buffers de salida para el modelo SSD
      final outputLocations = [List.generate(_maxDetections, (_) => List<double>.filled(4, 0.0))];
      final outputClasses = [List<double>.filled(_maxDetections, 0.0)];
      final outputScores = [List<double>.filled(_maxDetections, 0.0)];
      final outputNumDetections = List<double>.filled(1, 0.0);

      final outputs = <int, Object>{
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: outputNumDetections,
      };

      // 3. Inferencia asíncrona en el Isolate nativo
      await _isolateInterpreter!.runForMultipleInputs([input], outputs);
      if (!_mounted) return;

      // 4. Post-procesamiento: mapear a DetectedObject escalando al frame original
      final detections = _postprocess(
        locations: outputLocations[0],
        classes: outputClasses[0],
        scores: outputScores[0],
        numDetections: outputNumDetections[0].toInt(),
        frameWidth: frame.originalWidth.toDouble(),
        frameHeight: frame.originalHeight.toDouble(),
      );

      // 5. Despacho condicional
      if (!_mounted) return;

      if (detections.isEmpty) {
        _emptyFrameCount++;
        if (_emptyFrameCount >= _kEmptyFrameThreshold &&
            _lastDetections.isNotEmpty) {
          _lastDetections = const [];
          _onResult(const []);
        }
      } else {
        _emptyFrameCount = 0;
        if (!_areDetectionsEqual(detections, _lastDetections)) {
          _lastDetections = detections;
          _onResult(detections);
        }
      }
    } catch (e) {
      debugPrint('TfliteObstacleDetector: error en inferencia - $e');
    }
  }

  @override
  void dispose() {
    _mounted = false;
    if (_isolateInterpreter != null) {
      _isolateInterpreter!.close();
      _isolateInterpreter = null;
      // El isolate interpreter destruye el intérprete nativo al cerrarse.
      _interpreter = null;
    } else {
      _interpreter?.close();
      _interpreter = null;
    }
    _lastDetections = const [];
    debugPrint('TfliteObstacleDetector: recursos liberados.');
  }

  // -- Pre-procesamiento plano optimizado -------------------------------------

  Float32List _preprocessFloatFast(SensorFrame frame) {
    final bytes = frame.bytes;
    final totalSize = _inputSizeHeight * _inputSizeWidth * _kNumChannels;
    final tensor = Float32List(totalSize);

    // Si ya viene redimensionado desde el isolate de conversión
    if (frame.width == _inputSizeWidth && frame.height == _inputSizeHeight) {
      final len = bytes.length;
      for (int i = 0; i < len; i++) {
        tensor[i] = bytes[i] / 255.0;
      }
    } else {
      final srcW = frame.width;
      final srcH = frame.height;
      int dstIdx = 0;
      for (int y = 0; y < _inputSizeHeight; y++) {
        final srcY = (y * srcH) ~/ _inputSizeHeight;
        final rowOffset = srcY * srcW * _kNumChannels;
        for (int x = 0; x < _inputSizeWidth; x++) {
          final srcX = (x * srcW) ~/ _inputSizeWidth;
          final srcIdx = rowOffset + srcX * _kNumChannels;

          if (srcIdx + 2 < bytes.length) {
            tensor[dstIdx] = bytes[srcIdx] / 255.0;
            tensor[dstIdx + 1] = bytes[srcIdx + 1] / 255.0;
            tensor[dstIdx + 2] = bytes[srcIdx + 2] / 255.0;
          }
          dstIdx += 3;
        }
      }
    }
    return tensor;
  }

  Uint8List _preprocessUint8Fast(SensorFrame frame) {
    final bytes = frame.bytes;
    if (frame.width == _inputSizeWidth && frame.height == _inputSizeHeight) {
      return bytes;
    }
    final srcW = frame.width;
    final srcH = frame.height;
    final totalSize = _inputSizeHeight * _inputSizeWidth * _kNumChannels;
    final tensor = Uint8List(totalSize);
    int dstIdx = 0;
    for (int y = 0; y < _inputSizeHeight; y++) {
      final srcY = (y * srcH) ~/ _inputSizeHeight;
      final rowOffset = srcY * srcW * _kNumChannels;
      for (int x = 0; x < _inputSizeWidth; x++) {
        final srcX = (x * srcW) ~/ _inputSizeWidth;
        final srcIdx = rowOffset + srcX * _kNumChannels;

        if (srcIdx + 2 < bytes.length) {
          tensor[dstIdx] = bytes[srcIdx];
          tensor[dstIdx + 1] = bytes[srcIdx + 1];
          tensor[dstIdx + 2] = bytes[srcIdx + 2];
        }
        dstIdx += 3;
      }
    }
    return tensor;
  }

  // -- Post-procesamiento ----------------------------------------------------

  List<DetectedObject> _postprocess({
    required List<List<double>> locations,
    required List<double> classes,
    required List<double> scores,
    required int numDetections,
    required double frameWidth,
    required double frameHeight,
  }) {
    final results = <DetectedObject>[];
    final count = numDetections.clamp(0, _maxDetections);

    for (int i = 0; i < count; i++) {
      final classIndex = classes[i].toInt();

      String? label = _kNavLabels[classIndex];
      label ??= _kNavLabels[classIndex + 1];
      label ??= 'objeto';

      // Auto-tuning adaptativo para umbrales de confianza por clase
      double threshold = dynamicConfidenceThreshold;
      if (label == 'silla o banco' ||
          label == 'mesa o escritorio' ||
          label == 'persona' ||
          label == 'mochila' ||
          label == 'puerta' ||
          label == 'libro o libreta' ||
          label == 'pantalla o proyector' ||
          label == 'escaleras' ||
          label == 'escalones') {
        threshold = 0.25; // Reducido para facilitar detección de objetos escolares comunes
      } else if (label == 'automóvil' || label == 'camión' || label == 'motocicleta') {
        threshold = 0.40; // Más alto para reducir falsos positivos en objetos vehiculares
      }

      final score = scores[i];
      if (score < threshold) continue;

      final top = (locations[i][0] * frameHeight).clamp(0.0, frameHeight);
      final left = (locations[i][1] * frameWidth).clamp(0.0, frameWidth);
      final bottom = (locations[i][2] * frameHeight).clamp(0.0, frameHeight);
      final right = (locations[i][3] * frameWidth).clamp(0.0, frameWidth);

      if (right <= left || bottom <= top) continue;
      if ((right - left) < 2 || (bottom - top) < 2) continue;

      final boundingBox = Rect.fromLTRB(left, top, right, bottom);

      final distance = DetectedObject.estimateDistance(
        boundingBox,
        frameWidth,
        frameHeight,
        label: label,
      );

      results.add(DetectedObject(
        label: label,
        confidence: score,
        boundingBox: boundingBox,
        distance: distance,
      ));
    }

    results.sort((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });

    return results;
  }

  bool _areDetectionsEqual(List<DetectedObject> a, List<DetectedObject> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
