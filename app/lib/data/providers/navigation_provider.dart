import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/services/navigation/navigation_service.dart';

// ─── Estado de navegación ─────────────────────────────────────

/// Estados del módulo de navegación.
enum NavStatus {
  uninitialized, // Grafo no cargado
  ready, // Listo para navegar (sin ruta activa)
  calculating, // Calculando ruta
  navigating, // Navegación activa con instrucciones
  arrived, // Llegó al destino
  error, // Error
}

/// Estado inmutable de la navegación.
class NavigationState extends Equatable {
  final NavStatus status;
  final CampusNode? currentNode;
  final NavRoute? activeRoute;
  final int currentStepIndex;
  final bool accessibleOnly;
  final String? errorMessage;
  /// Cuando es true, las pantallas deben navegar al NAVIA AR automáticamente.
  /// Se consume con [NavigationNotifier.consumeARNavigation].
  final bool pendingARNavigation;

  const NavigationState({
    this.status = NavStatus.uninitialized,
    this.currentNode,
    this.activeRoute,
    this.currentStepIndex = 0,
    this.accessibleOnly = false,
    this.errorMessage,
    this.pendingARNavigation = false,
  });

  /// Instrucción de voz del paso actual.
  String? get currentInstruction {
    if (activeRoute == null || currentStepIndex >= activeRoute!.steps.length) {
      return null;
    }
    return activeRoute!.steps[currentStepIndex].voiceInstruction;
  }

  /// Progreso (0.0 a 1.0).
  double get progress {
    if (activeRoute == null || activeRoute!.steps.isEmpty) return 0;
    return currentStepIndex / activeRoute!.steps.length;
  }

  /// ¿Hay ruta activa?
  bool get hasActiveRoute =>
      status == NavStatus.navigating || status == NavStatus.arrived;

  NavigationState copyWith({
    NavStatus? status,
    CampusNode? currentNode,
    NavRoute? activeRoute,
    int? currentStepIndex,
    bool? accessibleOnly,
    String? errorMessage,
    bool? pendingARNavigation,
  }) {
    return NavigationState(
      status: status ?? this.status,
      currentNode: currentNode ?? this.currentNode,
      activeRoute: activeRoute ?? this.activeRoute,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      accessibleOnly: accessibleOnly ?? this.accessibleOnly,
      errorMessage: errorMessage,
      pendingARNavigation: pendingARNavigation ?? this.pendingARNavigation,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentNode,
        activeRoute,
        currentStepIndex,
        accessibleOnly,
        errorMessage,
        pendingARNavigation,
      ];
}

// ─── StateNotifier ────────────────────────────────────────────

class NavigationNotifier extends StateNotifier<NavigationState> {
  final NavigationService _navService;

  NavigationNotifier(this._navService) : super(const NavigationState());

  /// Inicializa el servicio (carga el grafo del campus).
  Future<void> initialize() async {
    try {
      await _navService.initialize();
      state = const NavigationState(status: NavStatus.ready);
    } catch (e) {
      state = NavigationState(
        status: NavStatus.error,
        errorMessage: 'Error cargando el mapa: $e',
      );
    }
  }

  /// Establece la posición actual por ID de nodo (escaneo QR).
  void setPosition(String nodeId) {
    final node = _navService.setCurrentPosition(nodeId);
    if (node != null) {
      state = state.copyWith(
        status: NavStatus.ready,
        currentNode: node,
      );
    } else {
      state = state.copyWith(
        errorMessage: 'Ubicación no reconocida: $nodeId',
      );
    }
  }

  /// Limpia la posición manual para volver al modo GPS.
  void clearManualPosition() {
    _navService.resetManualPosition();
    state = state.copyWith(status: NavStatus.ready);
  }

  /// Establece la posición actual por coordenadas GPS.
  void setPositionByCoordinates(double lat, double lng) {
    final node = _navService.setPositionByCoordinates(lat, lng);
    if (node != null) {
      state = state.copyWith(
        status: NavStatus.ready,
        currentNode: node,
      );
    } else {
      state = state.copyWith(
        errorMessage:
            'No se encontró un punto de navegación cercano a tu ubicación GPS.',
      );
    }
  }

  /// Calcula y activa la navegación a un destino por texto.
  void navigateTo(String destinationQuery) {
    state = state.copyWith(status: NavStatus.calculating);

    final route = _navService.calculateRoute(
      destinationQuery,
      accessibleOnly: state.accessibleOnly,
    );

    if (route != null) {
      state = state.copyWith(
        status: NavStatus.navigating,
        activeRoute: route,
        currentStepIndex: 0,
        pendingARNavigation: true,
      );
    } else {
      // Intentar sin filtro de accesibilidad si falló
      if (state.accessibleOnly) {
        final fallback = _navService.calculateRoute(destinationQuery);
        if (fallback != null) {
          state = state.copyWith(
            status: NavStatus.error,
            errorMessage:
                'No hay ruta accesible. ¿Deseas usar la ruta con escaleras?',
          );
          return;
        }
      }

      state = state.copyWith(
        status: NavStatus.error,
        errorMessage: 'No se encontró ruta a "$destinationQuery"',
      );
    }
  }

  /// Avanza al siguiente paso de la ruta.
  void nextStep() {
    if (state.activeRoute == null) return;

    final newIndex = state.currentStepIndex + 1;
    if (newIndex >= state.activeRoute!.steps.length) {
      state = state.copyWith(
        status: NavStatus.arrived,
        currentStepIndex: newIndex - 1,
      );
    } else {
      state = state.copyWith(currentStepIndex: newIndex);
    }
  }

  /// Retrocede al paso anterior.
  void previousStep() {
    if (state.currentStepIndex > 0) {
      state = state.copyWith(currentStepIndex: state.currentStepIndex - 1);
    }
  }

  /// Cancela la navegación activa.
  void cancelNavigation() {
    state = state.copyWith(
      status: NavStatus.ready,
      activeRoute: null,
      currentStepIndex: 0,
      pendingARNavigation: false,
    );
  }

  /// Consume el flag de navegación a AR (llamar justo antes de hacer push).
  void consumeARNavigation() {
    if (state.pendingARNavigation) {
      state = state.copyWith(pendingARNavigation: false);
    }
  }

  /// Alterna el filtro de accesibilidad.
  void toggleAccessible() {
    state = state.copyWith(accessibleOnly: !state.accessibleOnly);
  }

  /// Obtiene los destinos más cercanos.
  List<NavRoute> getNearbyDestinations({int limit = 5}) {
    return _navService.nearestDestinations(
      limit: limit,
      accessibleOnly: state.accessibleOnly,
    );
  }

  /// Busca un destino por texto.
  CampusNode? findDestination(String query) {
    return _navService.findDestination(query);
  }

  /// Lista todos los destinos disponibles.
  List<CampusNode> get allDestinations => _navService.allDestinations;
}

// ─── Providers ────────────────────────────────────────────────

/// Provider del servicio de navegación (singleton).
final navigationServiceProvider = Provider<NavigationService>((ref) {
  return NavigationService();
});

/// Provider principal de navegación.
final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>((ref) {
  final navService = ref.watch(navigationServiceProvider);
  return NavigationNotifier(navService);
});

/// Provider de conveniencia: ¿hay ruta activa?
final hasActiveRouteProvider = Provider<bool>((ref) {
  return ref.watch(navigationProvider).hasActiveRoute;
});

/// Provider de conveniencia: nodo actual.
final currentNodeProvider = Provider<CampusNode?>((ref) {
  return ref.watch(navigationProvider).currentNode;
});
