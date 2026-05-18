import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/voice_provider.dart';

// ---------------------------------------------------------------------------
// Estado del reconocimiento de marcadores (Equatable)
// ---------------------------------------------------------------------------

/// Estado del ultimo marcador procesado por [MarkerRecognizer].
///
/// Extiende [Equatable] para evitar reconstrucciones infinitas cuando
/// widgets observan este estado via Riverpod.
class MarkerRecognitionState extends Equatable {
  /// ID del ultimo marcador reconocido (clave del mapa, ej. 'BIBLIOTECA').
  final String? lastMarkerId;

  /// Node ID del grafo de Dijkstra correspondiente (ej. 'edificio_b').
  final String? resolvedNodeId;

  /// Nombre legible del punto para retroalimentacion de voz.
  final String? displayName;

  /// Marca temporal del ultimo reconocimiento exitoso.
  final DateTime? lastRecognizedAt;

  /// `true` si el ultimo intento de reconocimiento fue exitoso.
  final bool wasRecognized;

  /// Mensaje de error del ultimo intento fallido.
  final String? errorMessage;

  const MarkerRecognitionState({
    this.lastMarkerId,
    this.resolvedNodeId,
    this.displayName,
    this.lastRecognizedAt,
    this.wasRecognized = false,
    this.errorMessage,
  });

  MarkerRecognitionState copyWith({
    String? lastMarkerId,
    String? resolvedNodeId,
    String? displayName,
    DateTime? lastRecognizedAt,
    bool? wasRecognized,
    String? errorMessage,
  }) {
    return MarkerRecognitionState(
      lastMarkerId: lastMarkerId ?? this.lastMarkerId,
      resolvedNodeId: resolvedNodeId ?? this.resolvedNodeId,
      displayName: displayName ?? this.displayName,
      lastRecognizedAt: lastRecognizedAt ?? this.lastRecognizedAt,
      wasRecognized: wasRecognized ?? this.wasRecognized,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        lastMarkerId,
        resolvedNodeId,
        displayName,
        lastRecognizedAt,
        wasRecognized,
        errorMessage,
      ];
}

// ---------------------------------------------------------------------------
// Mapeo geografico: Marker ID -> Node ID del grafo de Dijkstra
// ---------------------------------------------------------------------------

/// Registro de un punto del campus con su nodeId y nombre legible.
class _CampusPoint {
  final String nodeId;
  final String displayName;

  const _CampusPoint(this.nodeId, this.displayName);
}

/// Mapeo de marcadores fisicos del campus a nodos del grafo de navegacion.
///
/// Las claves son los IDs impresos en la senaletica del campus
/// (codigos QR, placas ArUco, o identificadores textuales).
/// Los valores mapean al `nodeId` del grafo de Dijkstra cargado
/// desde `tec_colima_map.json`.
const Map<String, _CampusPoint> _kMarkerToNode = {
  // -- Accesos y entrada --
  'ENTRADA': _CampusPoint('tec_entrada', 'Acceso Principal'),
  'ENTRADA-PRINCIPAL': _CampusPoint('tec_entrada', 'Acceso Principal'),

  // -- Edificios principales --
  'EDIFICIO-A': _CampusPoint('edificio_a', 'Edificio A - Direccion'),
  'DIRECCION': _CampusPoint('edificio_a', 'Direccion Administrativa'),
  'EDIFICIO-B':
      _CampusPoint('edificio_b', 'Edificio B - Centro de Informacion'),
  'BIBLIOTECA': _CampusPoint('edificio_b', 'Biblioteca'),
  'EDIFICIO-C': _CampusPoint('edificio_c', 'Edificio C - Cafeteria Norte'),
  'CAFETERIA-NORTE': _CampusPoint('edificio_c', 'Cafeteria Norte'),
  'EDIFICIO-C1': _CampusPoint('edificio_c1', 'Edificio C1 - Cafeteria Sur'),
  'CAFETERIA-SUR': _CampusPoint('edificio_c1', 'Cafeteria Sur'),

  // -- Edificios academicos --
  'EDIFICIO-D': _CampusPoint('edificio_d', 'Edificio D - Aulas'),
  'D1': _CampusPoint('edificio_d', 'Edificio D - Aulas'),
  'EDIFICIO-E': _CampusPoint('edificio_e', 'Edificio E - Lab. Microbiologia'),
  'EDIFICIO-F': _CampusPoint('edificio_f', 'Edificio F - Ciencias Basicas'),
  'EDIFICIO-G': _CampusPoint('edificio_g', 'Edificio G - Lab. Quimica'),
  'EDIFICIO-H': _CampusPoint('edificio_h', 'Edificio H - Centro de Computo'),
  'COMPUTO': _CampusPoint('edificio_h', 'Centro de Computo'),
  'EDIFICIO-I': _CampusPoint('edificio_i', 'Edificio I - Arquitectura'),
  'EDIFICIO-J': _CampusPoint('edificio_j', 'Edificio J - Lab. Bioquimica'),
  'EDIFICIO-K': _CampusPoint('edificio_k', 'Edificio K - Aulas'),

  // -- Edificios especializados --
  'EDIFICIO-L':
      _CampusPoint('edificio_l', 'Edificio L - Lab. Quimica Organica'),
  'EDIFICIO-M':
      _CampusPoint('edificio_m', 'Edificio M - Operaciones Unitarias'),
  'EDIFICIO-N':
      _CampusPoint('edificio_n', 'Edificio N - Ciencias de la Tierra'),
  'EDIFICIO-O': _CampusPoint('edificio_o', 'Edificio O - Cubiculos Docentes'),
  'EDIFICIO-P':
      _CampusPoint('edificio_p', 'Edificio P - Taller de Manufactura'),
  'EDIFICIO-Q': _CampusPoint('edificio_q', 'Edificio Q - Recursos Materiales'),
  'EDIFICIO-R':
      _CampusPoint('edificio_r', 'Edificio R - Sistemas y Computacion'),
  'SISTEMAS': _CampusPoint('edificio_r', 'Sistemas y Computacion'),
};

// ---------------------------------------------------------------------------
// MarkerRecognizer (Mock / Puente simulado)
// ---------------------------------------------------------------------------

/// Puente simulado de reconocimiento de marcadores para NAVIA.
///
/// Esta clase **no** utiliza TFLite ni ningun motor de ML. Su proposito
/// es servir como interfaz entre la deteccion visual (futura) y la logica
/// de navegacion de Riverpod, permitiendo que la demostracion en vivo
/// funcione con marcadores simulados.
///
/// Flujo:
/// 1. Se invoca [simulateMarkerDetection] con un `markerId` visible.
/// 2. El reconocedor busca el `nodeId` correspondiente en [_kMarkerToNode].
/// 3. Si existe, actualiza la posicion en el [NavigationNotifier] y
///    anuncia por voz al usuario.
/// 4. Si no existe, anuncia el error por voz para retroalimentacion.
///
/// Cuando el modelo TFLite de marcadores personalizados este listo,
/// esta clase se reemplazara por una implementacion real que procese
/// [SensorFrame] y detecte marcadores ArUco/QR desde el feed de camara.
class MarkerRecognizer {
  /// Estado actual del reconocimiento (inmutable, Equatable).
  MarkerRecognitionState _state = const MarkerRecognitionState();

  /// Ultimo estado del reconocimiento (lectura publica).
  MarkerRecognitionState get state => _state;

  /// Verifica si un `markerId` tiene un nodo conocido en el grafo.
  bool isKnownMarker(String markerId) {
    return _kMarkerToNode.containsKey(markerId.toUpperCase().trim());
  }

  /// Retorna la lista de todos los marker IDs registrados.
  List<String> get registeredMarkerIds => _kMarkerToNode.keys.toList();

  /// Simula el reconocimiento de un marcador y dispara las acciones
  /// de navegacion y voz correspondientes.
  ///
  /// - [markerId]: Identificador del marcador fisico (ej. 'BIBLIOTECA').
  /// - [ref]: Referencia de Riverpod para acceder a los providers.
  ///
  /// El metodo es seguro ante desmontaje asincrono: verifica el estado
  /// del widget despues de cada operacion `await`.
  Future<void> simulateMarkerDetection(
    String markerId,
    WidgetRef ref,
  ) async {
    final normalizedId = markerId.toUpperCase().trim();
    final campusPoint = _kMarkerToNode[normalizedId];

    if (campusPoint == null) {
      // Marcador no reconocido: retroalimentacion de voz.
      _state = _state.copyWith(
        lastMarkerId: normalizedId,
        wasRecognized: false,
        errorMessage: 'Marcador no registrado: $normalizedId',
        lastRecognizedAt: DateTime.now(),
      );

      debugPrint(
        'MarkerRecognizer: marcador desconocido "$normalizedId"',
      );

      // Verificar contexto antes de operar con providers.
      if (!ref.context.mounted) return;

      await ref.read(voiceProvider.notifier).speakAnnouncement(
            'Marcador no reconocido. '
            'Intenta con otro punto del campus.',
          );
      return;
    }

    // Marcador valido: actualizar estado interno.
    _state = _state.copyWith(
      lastMarkerId: normalizedId,
      resolvedNodeId: campusPoint.nodeId,
      displayName: campusPoint.displayName,
      wasRecognized: true,
      lastRecognizedAt: DateTime.now(),
      errorMessage: null,
    );

    debugPrint(
      'MarkerRecognizer: "$normalizedId" -> '
      '${campusPoint.nodeId} (${campusPoint.displayName})',
    );

    // 1. Actualizar posicion en el grafo de Dijkstra.
    if (!ref.context.mounted) return;
    ref.read(navigationProvider.notifier).setPosition(campusPoint.nodeId);

    // 2. Retroalimentacion de voz al usuario.
    if (!ref.context.mounted) return;
    await ref.read(voiceProvider.notifier).speakAnnouncement(
          'Has llegado a ${campusPoint.displayName}.',
        );
  }

  /// Limpia el estado del reconocedor.
  void reset() {
    _state = const MarkerRecognitionState();
  }

  /// Libera recursos. No-op en la implementacion mock,
  /// pero mantiene la simetria con otros servicios del pipeline.
  void dispose() {
    reset();
    debugPrint('MarkerRecognizer: recursos liberados (mock).');
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provider del servicio de reconocimiento de marcadores.
final markerRecognizerProvider = Provider<MarkerRecognizer>((ref) {
  final recognizer = MarkerRecognizer();
  ref.onDispose(recognizer.dispose);
  return recognizer;
});

/// Provider de conveniencia: estado del ultimo reconocimiento.
final markerRecognitionStateProvider = Provider<MarkerRecognitionState>((ref) {
  return ref.watch(markerRecognizerProvider).state;
});
