import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/services/vision/models/detected_object.dart';
import 'package:navia/services/vision/models/recognized_marker.dart';

// --- Estado del modulo de vision -------------------------------------------

/// Fase operativa del pipeline de vision asistida.
enum VisionStatus {
  /// Pipeline no inicializado (modelo no cargado).
  uninitialized,

  /// Modelo cargado, listo para procesar fotogramas.
  ready,

  /// Procesando un fotograma activamente.
  processing,

  /// Pausado por el usuario o por politica de bateria.
  paused,

  /// Error irrecuperable (modelo corrupto, permisos, etc.).
  error,

  /// Modo de respaldo: el modelo TFLite no cargo y NAVIA opera
  /// unicamente con guia de voz (sin deteccion visual).
  voiceOnlyFallback,
}

/// Estado inmutable del modulo de vision asistida NAVIA.
///
/// Sigue el mismo patron que [NavigationState]: clase `extends Equatable`
/// con `copyWith` para actualizaciones parciales sin romper la inmutabilidad.
class VisionState extends Equatable {
  /// Fase actual del pipeline.
  final VisionStatus status;

  /// Objetos detectados en el fotograma mas reciente.
  final List<DetectedObject> detectedObjects;

  /// Marcadores reconocidos en el fotograma mas reciente.
  final List<RecognizedMarker> recognizedMarkers;

  /// Mensaje de error (solo cuando [status] es error o voiceOnlyFallback).
  final String? errorMessage;

  const VisionState({
    this.status = VisionStatus.uninitialized,
    this.detectedObjects = const [],
    this.recognizedMarkers = const [],
    this.errorMessage,
  });

  /// `true` si el pipeline acepta fotogramas (ready o processing).
  /// Usado por [CameraFeedHandler] para decidir si enviar frames.
  bool get isActive =>
      status == VisionStatus.ready || status == VisionStatus.processing;

  /// `true` si el pipeline esta procesando fotogramas activamente.
  bool get isProcessing => status == VisionStatus.processing;

  /// `true` si el pipeline esta pausado.
  bool get isPaused => status == VisionStatus.paused;

  /// `true` si hay al menos una deteccion vigente.
  bool get hasDetections =>
      detectedObjects.isNotEmpty || recognizedMarkers.isNotEmpty;

  /// `true` si el sistema opero en modo Solo Voz (sin modelo ML).
  bool get isVoiceOnlyMode => status == VisionStatus.voiceOnlyFallback;

  VisionState copyWith({
    VisionStatus? status,
    List<DetectedObject>? detectedObjects,
    List<RecognizedMarker>? recognizedMarkers,
    String? errorMessage,
  }) {
    return VisionState(
      status: status ?? this.status,
      detectedObjects: detectedObjects ?? this.detectedObjects,
      recognizedMarkers: recognizedMarkers ?? this.recognizedMarkers,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        detectedObjects,
        recognizedMarkers,
        errorMessage,
      ];
}

// --- StateNotifier ---------------------------------------------------------

/// Notifier del modulo de vision.
///
/// Gestiona las transiciones de estado del pipeline incluyendo:
/// - Carga exitosa del modelo -> [VisionStatus.ready]
/// - Fallo de carga -> [VisionStatus.voiceOnlyFallback]
/// - Actualizacion de detecciones desde [TfliteObstacleDetector]
/// - Pausa/reanudacion por el usuario o politica de bateria
class VisionNotifier extends StateNotifier<VisionState> {
  VisionNotifier() : super(const VisionState());

  /// Marca el pipeline como listo (modelo cargado exitosamente).
  void markReady() {
    state = state.copyWith(status: VisionStatus.ready);
  }

  /// Activa el modo Solo Voz cuando el modelo TFLite no pudo cargarse.
  ///
  /// En este modo NAVIA sigue funcional con navegacion GPS y guia
  /// por voz, pero sin deteccion visual de obstaculos.
  void activateVoiceOnlyFallback(String reason) {
    state = state.copyWith(
      status: VisionStatus.voiceOnlyFallback,
      errorMessage: reason,
      detectedObjects: const [],
      recognizedMarkers: const [],
    );
  }

  /// Actualiza las detecciones del fotograma mas reciente.
  ///
  /// Llamado por [TfliteObstacleDetector.onResult] cuando hay
  /// cambios significativos (la comparacion Equatable ya fue hecha
  /// en el detector antes de invocar este callback).
  void updateDetections({
    required List<DetectedObject> objects,
    List<RecognizedMarker> markers = const [],
  }) {
    state = state.copyWith(
      status: VisionStatus.processing,
      detectedObjects: objects,
      recognizedMarkers: markers,
    );
  }

  /// Limpia todas las detecciones (ej. al cambiar de pantalla).
  void clearDetections() {
    state = state.copyWith(
      detectedObjects: const [],
      recognizedMarkers: const [],
    );
  }

  /// Pausa el procesamiento de fotogramas.
  void pause() {
    state = state.copyWith(status: VisionStatus.paused);
  }

  /// Reanuda el procesamiento de fotogramas.
  void resume() {
    if (state.status == VisionStatus.paused) {
      state = state.copyWith(status: VisionStatus.ready);
    }
  }

  /// Registra un error irrecuperable.
  void setError(String message) {
    state = state.copyWith(
      status: VisionStatus.error,
      errorMessage: message,
    );
  }

  /// Reinicia el estado completo.
  void reset() {
    state = const VisionState();
  }
}

// --- Providers -------------------------------------------------------------

/// Provider principal del modulo de vision.
final visionProvider =
    StateNotifierProvider<VisionNotifier, VisionState>((ref) {
  return VisionNotifier();
});

/// Provider de conveniencia: lista de objetos detectados.
final detectedObjectsProvider = Provider<List<DetectedObject>>((ref) {
  return ref.watch(visionProvider).detectedObjects;
});

/// Provider de conveniencia: lista de marcadores reconocidos.
final recognizedMarkersProvider = Provider<List<RecognizedMarker>>((ref) {
  return ref.watch(visionProvider).recognizedMarkers;
});

/// Provider de conveniencia: esta procesando fotogramas.
final visionIsProcessingProvider = Provider<bool>((ref) {
  return ref.watch(visionProvider).isProcessing;
});

/// Provider de conveniencia: modo Solo Voz activo.
final isVoiceOnlyModeProvider = Provider<bool>((ref) {
  return ref.watch(visionProvider).isVoiceOnlyMode;
});

/// Provider de conveniencia: pipeline acepta fotogramas.
final visionIsActiveProvider = Provider<bool>((ref) {
  return ref.watch(visionProvider).isActive;
});
