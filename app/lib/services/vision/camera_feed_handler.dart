import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:navia/services/vision/ml_vision_service.dart';
import 'package:navia/services/vision/models/sensor_frame.dart';

// ---------------------------------------------------------------------------
// Payload para el Isolate (debe ser top-level para `compute`)
// ---------------------------------------------------------------------------

/// Datos necesarios para la conversion YUV/BGRA -> RGB en un Isolate.
class _ConversionPayload {
  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final int width;
  final int height;
  final int timestampMicros;
  final bool isBgra;

  const _ConversionPayload({
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.width,
    required this.height,
    required this.timestampMicros,
    required this.isBgra,
  });
}

/// Funcion top-level ejecutada en Isolate separado.
///
/// Convierte los planos crudos del sensor (YUV420 / BGRA8888) a un
/// buffer RGB de 3 canales para inferencia TFLite.
SensorFrame _convertFrameInIsolate(_ConversionPayload p) {
  final rgbBytes = Uint8List(p.width * p.height * 3);

  if (p.isBgra) {
    _convertBgra(p.planes[0], rgbBytes, p.width, p.height);
  } else {
    _convertYuv420(
      p.planes,
      p.rowStrides,
      p.pixelStrides,
      rgbBytes,
      p.width,
      p.height,
    );
  }

  return SensorFrame(
    bytes: rgbBytes,
    width: p.width,
    height: p.height,
    timestampMicros: p.timestampMicros,
  );
}

/// BGRA8888 (iOS) -> RGB.
void _convertBgra(
  Uint8List plane,
  Uint8List rgb,
  int width,
  int height,
) {
  final pixelCount = width * height;
  final maxBgra = plane.length;
  for (int i = 0; i < pixelCount; i++) {
    final bgraIdx = i * 4;
    if (bgraIdx + 2 >= maxBgra) break;
    final rgbIdx = i * 3;
    rgb[rgbIdx] = plane[bgraIdx + 2]; // R
    rgb[rgbIdx + 1] = plane[bgraIdx + 1]; // G
    rgb[rgbIdx + 2] = plane[bgraIdx]; // B
  }
}

/// YUV420 (Android) -> RGB via BT.601.
/// Optimizado con clamp inline para mejor performance.
void _convertYuv420(
  List<Uint8List> planes,
  List<int> rowStrides,
  List<int> pixelStrides,
  Uint8List rgb,
  int width,
  int height,
) {
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];

  final yRowStride = rowStrides[0];
  final uvRowStride = rowStrides[1];
  final uvPixelStride = pixelStrides[1];

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      // Bounds check para evitar RangeError en frames truncados
      if (yIndex >= yPlane.length ||
          uvIndex >= uPlane.length ||
          uvIndex >= vPlane.length) {
        continue;
      }

      final yVal = yPlane[yIndex];
      final uVal = uPlane[uvIndex];
      final vVal = vPlane[uvIndex];

      // ITU-R BT.601
      final r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
      final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
          .round()
          .clamp(0, 255);
      final b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

      final rgbIdx = (y * width + x) * 3;
      rgb[rgbIdx] = r;
      rgb[rgbIdx + 1] = g;
      rgb[rgbIdx + 2] = b;
    }
  }
}

// ---------------------------------------------------------------------------
// CameraFeedHandler
// ---------------------------------------------------------------------------

/// Gestor del flujo de fotogramas de la camara para NAVIA.
///
/// Responsabilidades:
/// - Configura [CameraController] con `ResolutionPreset.medium`.
/// - Aplica logica de *frame skip* (1 de cada [_kFrameSkip] frames).
/// - Convierte `CameraImage` a [SensorFrame] en un **Isolate separado**
///   para no bloquear los 60 fps de la UI.
/// - Solo envia frames al [MlVisionService] si la deteccion esta activa.
///
/// Ciclo de vida: `initialize()` -> `startStream()` -> `stopStream()` ->
/// `dispose()`.
class CameraFeedHandler {
  // -- Dependencias ----------------------------------------------------------

  final CameraDescription _camera;

  /// Callback que consulta el estado del [VisionProvider].
  /// Retorna `true` si la deteccion esta activa (ready | processing).
  final bool Function() _isDetectionActive;

  /// Servicio de inferencia ML (inyeccion opcional; puede ser null
  /// durante tests o antes de cargar el modelo).
  final MlVisionService? _mlService;

  // -- Estado interno --------------------------------------------------------

  CameraController? _controller;
  bool _mounted = false;
  int _frameCount = 0;
  bool _isProcessingFrame = false;
  bool _isStreaming = false;

  /// Procesar 1 de cada [_kFrameSkip] fotogramas.
  /// Valor 2 = procesar cada 2do frame (mejor deteccion, aun buen rendimiento).
  static const int _kFrameSkip = 2;

  // -- Constructor -----------------------------------------------------------

  CameraFeedHandler({
    required CameraDescription camera,
    required bool Function() isDetectionActive,
    MlVisionService? mlService,
  })  : _camera = camera,
        _isDetectionActive = isDetectionActive,
        _mlService = mlService;

  // -- Getters publicos ------------------------------------------------------

  /// Controlador de camara subyacente (para el widget `CameraPreview`).
  CameraController? get controller => _controller;

  /// `true` si el controlador esta inicializado y listo.
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// `true` si el stream de imagenes esta activo.
  bool get isStreaming => _isStreaming;

  // -- Ciclo de vida ---------------------------------------------------------

  /// Inicializa el [CameraController].
  ///
  /// Usa `ResolutionPreset.medium` y desactiva audio.
  /// En Android fuerza YUV420; en iOS usa BGRA8888.
  Future<void> initialize() async {
    final imageFormat = defaultTargetPlatform == TargetPlatform.android
        ? ImageFormatGroup.yuv420
        : ImageFormatGroup.bgra8888;

    _controller = CameraController(
      _camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: imageFormat,
    );

    await _controller!.initialize();
    _mounted = true;

    debugPrint(
      'CameraFeedHandler: camara inicializada '
      '(${_controller!.value.previewSize})',
    );
  }

  /// Inicia el stream de fotogramas con frame-skip y conversion en Isolate.
  void startStream() {
    if (!_mounted || _controller == null || _isStreaming) return;
    if (!_controller!.value.isInitialized) return;

    _frameCount = 0;
    _isStreaming = true;
    _controller!.startImageStream(_onCameraFrame);
    debugPrint('CameraFeedHandler: stream de frames iniciado.');
  }

  /// Detiene el stream de fotogramas.
  Future<void> stopStream() async {
    if (_controller != null &&
        _controller!.value.isInitialized &&
        _isStreaming) {
      try {
        await _controller!.stopImageStream();
      } catch (e) {
        debugPrint('CameraFeedHandler: error deteniendo stream - $e');
      }
    }
    _isStreaming = false;
  }

  /// Libera todos los recursos. Despues de esto el handler no es reutilizable.
  Future<void> dispose() async {
    _mounted = false;
    await stopStream();
    try {
      await _controller?.dispose();
    } catch (e) {
      debugPrint('CameraFeedHandler: error liberando controller - $e');
    }
    _controller = null;
  }

  // -- Procesamiento de frames -----------------------------------------------

  /// Callback del stream de camara.
  void _onCameraFrame(CameraImage image) {
    // Guardia de seguridad: no procesar si el handler fue disposed.
    if (!_mounted) return;

    // Frame skip: solo procesamos 1 de cada [_kFrameSkip].
    _frameCount++;
    if (_frameCount % _kFrameSkip != 0) return;

    // Evitar overflow del contador en sesiones muy largas.
    if (_frameCount > 1000000) _frameCount = 0;

    // No procesar si la deteccion no esta activa en el VisionProvider.
    if (!_isDetectionActive()) return;

    // No apilar tareas de conversion si la anterior no ha terminado.
    if (_isProcessingFrame) return;

    _processFrame(image);
  }

  /// Convierte [CameraImage] a [SensorFrame] en un Isolate y lo envia
  /// al [MlVisionService].
  Future<void> _processFrame(CameraImage image) async {
    if (!_mounted) return;

    _isProcessingFrame = true;

    try {
      // Extraemos los bytes crudos antes de enviar al Isolate.
      // CameraImage no es transferible directamente entre Isolates.
      final planes = image.planes
          .map((p) => Uint8List.fromList(p.bytes))
          .toList(growable: false);

      final rowStrides =
          image.planes.map((p) => p.bytesPerRow).toList(growable: false);

      final pixelStrides =
          image.planes.map((p) => p.bytesPerPixel ?? 1).toList(growable: false);

      final isBgra = defaultTargetPlatform != TargetPlatform.android;

      final payload = _ConversionPayload(
        planes: planes,
        rowStrides: rowStrides,
        pixelStrides: pixelStrides,
        width: image.width,
        height: image.height,
        timestampMicros: DateTime.now().microsecondsSinceEpoch,
        isBgra: isBgra,
      );

      // Conversion pesada en Isolate separado (no bloquea la UI).
      final sensorFrame = await compute(_convertFrameInIsolate, payload);

      // Guardia post-isolate: el handler pudo ser disposed mientras esperabamos.
      if (!_mounted) return;

      // Enviar al servicio de inferencia ML (si existe).
      await _mlService?.processFrame(sensorFrame);
    } catch (e) {
      debugPrint('CameraFeedHandler: error procesando frame - $e');
    } finally {
      _isProcessingFrame = false;
    }
  }
}
