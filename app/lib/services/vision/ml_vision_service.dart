import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:navia/services/vision/models/detected_object.dart';
import 'package:navia/services/vision/models/sensor_frame.dart';
import 'package:navia/services/vision/model_manager_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ---------------------------------------------------------------------------
// Constantes del modelo SSD MobileNet (COCO)
// ---------------------------------------------------------------------------

// Eliminamos _kInputSize y _kMaxDetections constantes.
// Seran determinados de forma dinamica al cargar el modelo.

/// Subconjunto de clases COCO relevantes para navegacion accesible.
///
/// IMPORTANTE: Los IDs son 1-indexed para coincidir con el archivo
/// coco_labels.txt (person=1, bicycle=2, car=3, etc.).
/// El modelo SSD MobileNet COCO devuelve IDs 1-indexed.
const Map<int, String> _kNavLabels = {
  // Personas y vehiculos (peligro inmediato)
  1: 'persona',
  2: 'bicicleta',
  3: 'auto',
  4: 'motocicleta',
  6: 'autobus',
  8: 'camion',

  // Senalizacion y seguridad vial
  10: 'semaforo',
  11: 'hidrante',
  13: 'senal de alto',
  14: 'parquimetro',
  15: 'banca',

  // Animales (posible obstaculo)
  17: 'gato',
  18: 'perro',

  // Objetos personales (posible obstaculo en piso)
  27: 'mochila',
  28: 'paraguas',
  33: 'maleta',

  // Comida / contenedores (objetos sobre mesa)
  44: 'botella',
  47: 'taza',

  // Mobiliario (obstaculos interiores)
  62: 'silla',
  63: 'sofa',
  64: 'maceta',
  65: 'cama',
  67: 'mesa',

  // Electronica / monitores (proxy para puertas con senaletica)
  70: 'bano',
  72: 'pantalla',
  73: 'laptop',
  76: 'teclado',
  77: 'celular',

  // Electrodomesticos
  82: 'refrigerador',

  // Libros / reloj
  84: 'libro',
  85: 'reloj',

  // Extensiones personalizadas para modelos afinados (fine-tuned)
  86: 'pared',
  87: 'escaleras',
  88: 'escalones',
  89: 'puerta',
  90: 'ventana',
  91: 'bardas',
  92: 'jardin',
  93: 'terreno elevado',
  94: 'terreno muy elevado',
};

// ---------------------------------------------------------------------------
// Contrato base (interfaz)
// ---------------------------------------------------------------------------

/// Contrato para el servicio de inferencia ML.
///
/// El [CameraFeedHandler] envia fotogramas procesados ([SensorFrame]) a
/// cualquier implementacion de esta interfaz.
abstract class MlVisionService {
  /// Ejecuta la inferencia sobre un fotograma ya convertido a RGB.
  Future<void> processFrame(SensorFrame frame);

  /// Libera recursos del modelo (interpretes, buffers, etc.).
  void dispose();
}

// ---------------------------------------------------------------------------
// Callback para notificar al VisionProvider
// ---------------------------------------------------------------------------

/// Firma del callback que el servicio usa para actualizar el estado.
///
/// - [objects]: lista de detecciones del frame actual.
/// - Devuelve `true` si el provider acepto la actualizacion.
typedef OnDetectionResult = void Function(List<DetectedObject> objects);

/// Firma del callback para notificar errores criticos.
///
/// Permite al orquestador activar el modo "Solo Voz" como respaldo
/// cuando el interprete TFLite falla de forma irrecuperable.
typedef OnVisionError = void Function(String errorMessage);

// ---------------------------------------------------------------------------
// Implementacion concreta: TFLite Obstacle Detector
// ---------------------------------------------------------------------------

/// Orquestador de inferencia TFLite para deteccion de obstaculos en NAVIA.
///
/// Responsabilidades:
/// 1. Carga del modelo `obstacles_detector.tflite` con gestion de errores.
/// 2. Pre-procesamiento: escala el [SensorFrame] a 300x300 y normaliza
///    los pixeles al rango [0, 1] (float) o [0, 255] (uint8).
/// 3. Inferencia SSD MobileNet y post-procesamiento de las salidas.
/// 4. Calculo de heuristica de distancia basada en area relativa del
///    bounding-box respecto a la resolucion del frame original.
/// 5. Despacho de resultados al [VisionProvider] solo si hay cambios
///    significativos (gracias a Equatable en [DetectedObject]).
///
/// Ciclo de vida: `initialize()` -> (recibe frames via `processFrame()`)
/// -> `dispose()`.
class TfliteObstacleDetector implements MlVisionService {
  // -- Dependencias ----------------------------------------------------------

  /// Callback para enviar detecciones al VisionProvider.
  final OnDetectionResult _onResult;

  /// Callback para notificar errores criticos (activa modo Solo Voz).
  final OnVisionError _onError;

  // -- Estado interno --------------------------------------------------------

  Interpreter? _interpreter;
  bool _mounted = false;

  /// true si el modelo espera input uint8 (0-255) en lugar de float (0-1).
  bool _isQuantized = false;

  /// Parametros extraidos del modelo
  int _inputSizeWidth = 300;
  int _inputSizeHeight = 300;
  int _maxDetections = 10;
  static const int _kNumChannels = 3;
  static const double _kConfidenceThreshold = 0.30;

  /// Cache de la ultima lista de detecciones para evitar rebuilds
  /// innecesarios. Solo se notifica al provider si cambio.
  List<DetectedObject> _lastDetections = const [];

  /// Contador de frames sin detecciones (para limpiar UI).
  int _emptyFrameCount = 0;
  static const int _kEmptyFrameThreshold = 5;

  // -- Constructor -----------------------------------------------------------

  TfliteObstacleDetector({
    required OnDetectionResult onResult,
    required OnVisionError onError,
  })  : _onResult = onResult,
        _onError = onError;

  // -- Getters ---------------------------------------------------------------

  /// `true` si el interprete esta cargado y listo.
  bool get isReady => _interpreter != null && _mounted;

  // -- Ciclo de vida ---------------------------------------------------------

  /// Carga el modelo TFLite delegado al [ModelManagerService].
  ///
  /// Si falla, notifica al VisionProvider para activar el modo Solo Voz
  /// como respaldo seguro para el usuario invidente.
  Future<bool> initialize(ModelManagerService modelManager) async {
    try {
      _interpreter = await modelManager.loadModel('obstacles_detector.tflite');

      if (_interpreter == null) {
        throw Exception('El servicio devolvio null al cargar el modelo.');
      }

      _mounted = true;

      // Detectar si el modelo espera input uint8 o float32, y su tamaño
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

      // Detectar cuantas detecciones devuelve el modelo
      final outputTensors = _interpreter!.getOutputTensors();
      if (outputTensors.isNotEmpty) {
        final outputShape = outputTensors.first.shape;
        if (outputShape.length >= 2) {
          _maxDetections = outputShape[1];
        }
      }

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
    if (!_mounted || _interpreter == null) return;

    try {
      // 1. Pre-procesamiento: RGB -> tensor 300x300.
      final input =
          _isQuantized ? _preprocessUint8(frame) : _preprocessFloat(frame);
      if (!_mounted) return;

      // 2. Preparar buffers de salida del modelo SSD.
      //    El modelo SSD MobileNet produce 4 tensores de salida:
      //    [0] locations  : [1][N][4] (top, left, bottom, right) normalizados
      //    [1] classes    : [1][N]    indices de clase COCO
      //    [2] scores     : [1][N]    confianza por deteccion
      //    [3] numDetections: [1]     numero real de detecciones
      final outputLocations = List.generate(
        1,
        (_) => List.generate(
          _maxDetections,
          (_) => List<double>.filled(4, 0),
        ),
      );
      final outputClasses = List.generate(
        1,
        (_) => List<double>.filled(_maxDetections, 0),
      );
      final outputScores = List.generate(
        1,
        (_) => List<double>.filled(_maxDetections, 0),
      );
      final outputNumDetections = List<double>.filled(1, 0);

      final outputs = <int, Object>{
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: outputNumDetections,
      };

      // 3. Inferencia.
      _interpreter!.runForMultipleInputs([input], outputs);
      if (!_mounted) return;

      // 4. Post-procesamiento: convertir salidas a DetectedObject.
      final detections = _postprocess(
        locations: outputLocations[0],
        classes: outputClasses[0],
        scores: outputScores[0],
        numDetections: outputNumDetections[0].toInt(),
        frameWidth: frame.width.toDouble(),
        frameHeight: frame.height.toDouble(),
      );

      // 5. Despacho condicional: solo notificar si hay cambio real.
      if (!_mounted) return;

      if (detections.isEmpty) {
        _emptyFrameCount++;
        // Solo limpiar detecciones despues de N frames vacios consecutivos
        // para evitar parpadeo en la UI.
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
      // Un error puntual no activa modo Solo Voz; se reintenta en el
      // siguiente frame. Solo errores de carga activan el fallback.
    }
  }

  @override
  void dispose() {
    _mounted = false;
    _interpreter?.close();
    _interpreter = null;
    _lastDetections = const [];
    debugPrint('TfliteObstacleDetector: recursos liberados.');
  }

  // -- Pre-procesamiento (float32) -------------------------------------------

  /// Escala el frame RGB a [_inputSizeHeight]x[_inputSizeWidth] y normaliza
  /// los valores de pixel al rango [0.0, 1.0].
  List<List<List<List<double>>>> _preprocessFloat(SensorFrame frame) {
    final srcW = frame.width;
    final srcH = frame.height;
    final bytes = frame.bytes;

    final tensor = List.generate(
      1,
      (_) => List.generate(
        _inputSizeHeight,
        (y) {
          final srcY = (y * srcH) ~/ _inputSizeHeight;
          return List.generate(
            _inputSizeWidth,
            (x) {
              final srcX = (x * srcW) ~/ _inputSizeWidth;
              final srcIdx = (srcY * srcW + srcX) * _kNumChannels;

              // Bounds check para evitar RangeError
              if (srcIdx + 2 >= bytes.length) {
                return [0.0, 0.0, 0.0];
              }

              return [
                bytes[srcIdx] / 255.0,
                bytes[srcIdx + 1] / 255.0,
                bytes[srcIdx + 2] / 255.0,
              ];
            },
          );
        },
      ),
    );

    return tensor;
  }

  // -- Pre-procesamiento (uint8) ---------------------------------------------

  /// Escala el frame RGB a [_inputSizeHeight]x[_inputSizeWidth] sin normalizar
  /// (mantiene valores 0-255 como uint8).
  List<List<List<List<int>>>> _preprocessUint8(SensorFrame frame) {
    final srcW = frame.width;
    final srcH = frame.height;
    final bytes = frame.bytes;

    final tensor = List.generate(
      1,
      (_) => List.generate(
        _inputSizeHeight,
        (y) {
          final srcY = (y * srcH) ~/ _inputSizeHeight;
          return List.generate(
            _inputSizeWidth,
            (x) {
              final srcX = (x * srcW) ~/ _inputSizeWidth;
              final srcIdx = (srcY * srcW + srcX) * _kNumChannels;

              if (srcIdx + 2 >= bytes.length) {
                return [0, 0, 0];
              }

              return [
                bytes[srcIdx],
                bytes[srcIdx + 1],
                bytes[srcIdx + 2],
              ];
            },
          );
        },
      ),
    );

    return tensor;
  }

  // -- Post-procesamiento ----------------------------------------------------

  /// Convierte las salidas crudas del modelo SSD a una lista
  /// de [DetectedObject] filtrada y con heuristica de distancia.
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
      final score = scores[i];
      if (score < _kConfidenceThreshold) continue;

      // El modelo SSD MobileNet COCO devuelve IDs 1-indexed.
      // Sumamos 1 si el modelo devuelve 0-indexed, pero la mayoria
      // de modelos SSD MobileNet v1/v2 COCO devuelven 1-indexed directamente.
      final classIndex = classes[i].toInt();

      // Intentar buscar directamente y tambien con offset +1
      String? label = _kNavLabels[classIndex];
      label ??= _kNavLabels[classIndex + 1];

      // Ignorar clases que no son relevantes para navegacion accesible.
      if (label == null) continue;

      // Coordenadas normalizadas [0..1] -> pixeles del frame original.
      // SSD MobileNet devuelve [top, left, bottom, right].
      final top = (locations[i][0] * frameHeight).clamp(0.0, frameHeight);
      final left = (locations[i][1] * frameWidth).clamp(0.0, frameWidth);
      final bottom = (locations[i][2] * frameHeight).clamp(0.0, frameHeight);
      final right = (locations[i][3] * frameWidth).clamp(0.0, frameWidth);

      // Validar que el bounding box tenga dimensiones validas
      if (right <= left || bottom <= top) continue;
      if ((right - left) < 2 || (bottom - top) < 2) continue;

      final boundingBox = Rect.fromLTRB(left, top, right, bottom);

      // Heuristica de distancia usando la funcion de DetectedObject.
      final distance = DetectedObject.estimateDistance(
        boundingBox,
        frameWidth,
        frameHeight,
      );

      results.add(DetectedObject(
        label: label,
        confidence: score,
        boundingBox: boundingBox,
        distance: distance,
      ));
    }

    // Ordenar por distancia (mas cercano primero = mayor area).
    results.sort((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });

    return results;
  }

  // -- Utilidades ------------------------------------------------------------

  /// Compara dos listas de detecciones por valor usando Equatable.
  ///
  /// Esto evita notificar al VisionProvider (y por tanto reconstruir
  /// widgets) cuando los resultados no cambiaron entre frames.
  bool _areDetectionsEqual(
    List<DetectedObject> a,
    List<DetectedObject> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
