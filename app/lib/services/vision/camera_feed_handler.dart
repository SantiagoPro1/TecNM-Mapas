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
  final int targetWidth;
  final int targetHeight;

  const _ConversionPayload({
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.width,
    required this.height,
    required this.timestampMicros,
    required this.isBgra,
    required this.targetWidth,
    required this.targetHeight,
  });
}

/// Funcion top-level ejecutada en Isolate separado.
///
/// Convierte los planos crudos del sensor (YUV420 / BGRA8888) a un
/// buffer RGB de 3 canales para inferencia TFLite, redimensionándolo al mismo tiempo.
SensorFrame _convertFrameInIsolate(_ConversionPayload p) {
  final targetW = p.targetWidth > 0 ? p.targetWidth : p.width;
  final targetH = p.targetHeight > 0 ? p.targetHeight : p.height;
  final rgbBytes = Uint8List(targetW * targetH * 3);

  if (p.isBgra) {
    _convertBgraResized(p.planes[0], rgbBytes, p.width, p.height, targetW, targetH);
  } else {
    _convertYuv420Resized(
      p.planes,
      p.rowStrides,
      p.pixelStrides,
      rgbBytes,
      p.width,
      p.height,
      targetW,
      targetH,
    );
  }

  return SensorFrame(
    bytes: rgbBytes,
    width: targetW,
    height: targetH,
    timestampMicros: p.timestampMicros,
    originalWidth: p.width,
    originalHeight: p.height,
  );
}

/// BGRA8888 (iOS) -> RGB con redimensionamiento.
void _convertBgraResized(
  Uint8List plane,
  Uint8List rgb,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  final maxBgra = plane.length;
  int dstIdx = 0;
  for (int y = 0; y < dstH; y++) {
    final srcY = (y * srcH) ~/ dstH;
    final rowOffset = srcY * srcW * 4;
    for (int x = 0; x < dstW; x++) {
      final srcX = (x * srcW) ~/ dstW;
      final bgraIdx = rowOffset + srcX * 4;

      if (bgraIdx + 2 < maxBgra) {
        rgb[dstIdx] = plane[bgraIdx + 2]; // R
        rgb[dstIdx + 1] = plane[bgraIdx + 1]; // G
        rgb[dstIdx + 2] = plane[bgraIdx]; // B
      }
      dstIdx += 3;
    }
  }
}

/// YUV420 (Android) -> RGB via BT.601 con redimensionamiento integrado.
void _convertYuv420Resized(
  List<Uint8List> planes,
  List<int> rowStrides,
  List<int> pixelStrides,
  Uint8List rgb,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];

  final yRowStride = rowStrides[0];
  final uvRowStride = rowStrides[1];
  final uvPixelStride = pixelStrides[1];

  int dstIdx = 0;
  for (int y = 0; y < dstH; y++) {
    final srcY = (y * srcH) ~/ dstH;
    final yRowOffset = srcY * yRowStride;
    final uvRowOffset = (srcY ~/ 2) * uvRowStride;
    for (int x = 0; x < dstW; x++) {
      final srcX = (x * srcW) ~/ dstW;
      final yIndex = yRowOffset + srcX;
      final uvIndex = uvRowOffset + (srcX ~/ 2) * uvPixelStride;

      if (yIndex < yPlane.length &&
          uvIndex < uPlane.length &&
          uvIndex < vPlane.length) {
        final yVal = yPlane[yIndex];
        final uVal = uPlane[uvIndex];
        final vVal = vPlane[uvIndex];

        // ITU-R BT.601
        final r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
        final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
            .round()
            .clamp(0, 255);
        final b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

        rgb[dstIdx] = r;
        rgb[dstIdx + 1] = g;
        rgb[dstIdx + 2] = b;
      }
      dstIdx += 3;
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

  // -- Dimensiones objetivo de redimensionamiento --
  final int targetWidth;
  final int targetHeight;

  // -- Estado interno --------------------------------------------------------

  CameraController? _controller;
  bool _mounted = false;
  int _frameCount = 0;
  bool _isProcessingFrame = false;
  bool _isStreaming = false;
  int _lastFrameTimestampMs = 0;

  /// Procesar 1 de cada [_kFrameSkip] fotogramas.
  static const int _kFrameSkip = 6;

  /// Intervalo mínimo entre frames procesados (ms) — limita a ~2 fps de inferencia.
  static const int _kMinFrameGapMs = 500;

  // -- Constructor -----------------------------------------------------------

  CameraFeedHandler({
    required CameraDescription camera,
    required bool Function() isDetectionActive,
    MlVisionService? mlService,
    this.targetWidth = 0,
    this.targetHeight = 0,
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
  /// Usa `ResolutionPreset.low` y desactiva audio.
  /// En Android fuerza YUV420; en iOS usa BGRA8888.
  Future<void> initialize() async {
    final imageFormat = defaultTargetPlatform == TargetPlatform.android
        ? ImageFormatGroup.yuv420
        : ImageFormatGroup.bgra8888;

    _controller = CameraController(
      _camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: imageFormat,
    );

    await _controller!.initialize();
    
    // Configurar auto-enfoque continuo para evitar imagen borrosa/desenfocada
    try {
      await _controller!.setFocusMode(FocusMode.auto);
      debugPrint('CameraFeedHandler: Enfoque auto activado correctamente.');
    } catch (e) {
      debugPrint('CameraFeedHandler: No se pudo establecer el enfoque auto: $e');
    }

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
    if (!_mounted) return;

    _frameCount++;
    if (_frameCount % _kFrameSkip != 0) return;
    if (_frameCount > 1000000) _frameCount = 0;

    // Throttle por tiempo: máximo ~2 inferencias por segundo.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameTimestampMs < _kMinFrameGapMs) return;
    _lastFrameTimestampMs = now;

    if (!_isDetectionActive()) return;
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
        targetWidth: targetWidth,
        targetHeight: targetHeight,
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
