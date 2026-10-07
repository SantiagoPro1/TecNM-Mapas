import 'dart:async';
import 'package:geolocator/geolocator.dart';
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
  /// Cuando es true, las pantallas deben navegar al NAVIA AR automaticamente.
  /// Se consume con [NavigationNotifier.consumeARNavigation].
  final bool pendingARNavigation;

  /// Puntos de la polilínea calculada por Google Routes API.
  /// Cuando no es null, el mini-mapa de NAVIA AR usa estos puntos
  /// en lugar de (o ademas de) los pasos del grafo Dijkstra.
  final List<List<double>>? routePolylinePoints;

  /// Nombre del destino actual (para mostrar en el mini-mapa).
  final String? destinationName;

  /// Distancia total de la ruta en metros (Google Routes API).
  final int? routeDistanceMeters;

  /// Id de la sede (venue) a la que pertenece [activeRoute]. Se usa para
  /// detectar y descartar una ruta "fantasma": si el usuario cancela la
  /// ruta pero abre el mapa de otra sede antes de que el estado se limpie
  /// (o si nunca canceló y solo cambió de sede), no debe reaparecer una
  /// ruta calculada para una sede distinta a la que se está viendo.
  final String? routeVenueId;

  /// `true` mientras la posición está fijada a mano ("Estoy Aquí" en un
  /// lugar, o un QR escaneado) en vez de seguir el GPS en tiempo real.
  /// Antes esto solo vivía dentro de [NavigationService] (invisible para
  /// la UI): si alguien tocaba "Estoy Aquí" no había ninguna señal
  /// reactiva de que el GPS se había "congelado" ahí a propósito, ni una
  /// forma obvia de quitarlo — solo funcionaba si sabías que el botón de
  /// centrar ubicación también lo hacía por dentro.
  final bool isManualPosition;

  /// Nombre del lugar fijado manualmente (para mostrarlo en el aviso).
  final String? manualPositionLabel;

  const NavigationState({
    this.status = NavStatus.uninitialized,
    this.currentNode,
    this.activeRoute,
    this.currentStepIndex = 0,
    this.accessibleOnly = false,
    this.errorMessage,
    this.pendingARNavigation = false,
    this.routePolylinePoints,
    this.destinationName,
    this.routeDistanceMeters,
    this.routeVenueId,
    this.isManualPosition = false,
    this.manualPositionLabel,
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

  /// true si hay una ruta Google Routes activa (polyline directa).
  bool get hasGoogleRoute => routePolylinePoints != null && routePolylinePoints!.isNotEmpty;

  NavigationState copyWith({
    NavStatus? status,
    CampusNode? currentNode,
    NavRoute? activeRoute,
    int? currentStepIndex,
    bool? accessibleOnly,
    String? errorMessage,
    bool? pendingARNavigation,
    List<List<double>>? routePolylinePoints,
    String? destinationName,
    int? routeDistanceMeters,
    String? routeVenueId,
    bool? isManualPosition,
    String? manualPositionLabel,
    bool clearRoutePolyline = false,
    bool clearDestinationName = false,
    bool clearActiveRoute = false,
    bool clearManualPositionLabel = false,
    bool clearCurrentNode = false,
  }) {
    return NavigationState(
      status: status ?? this.status,
      currentNode: clearCurrentNode ? null : (currentNode ?? this.currentNode),
      activeRoute: clearActiveRoute ? null : (activeRoute ?? this.activeRoute),
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      accessibleOnly: accessibleOnly ?? this.accessibleOnly,
      errorMessage: errorMessage,
      pendingARNavigation: pendingARNavigation ?? this.pendingARNavigation,
      routePolylinePoints: clearRoutePolyline ? null : (routePolylinePoints ?? this.routePolylinePoints),
      destinationName: clearDestinationName ? null : (destinationName ?? this.destinationName),
      routeDistanceMeters: routeDistanceMeters ?? this.routeDistanceMeters,
      routeVenueId: clearActiveRoute ? null : (routeVenueId ?? this.routeVenueId),
      isManualPosition: isManualPosition ?? this.isManualPosition,
      manualPositionLabel: clearManualPositionLabel
          ? null
          : (manualPositionLabel ?? this.manualPositionLabel),
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
        routePolylinePoints,
        destinationName,
        routeDistanceMeters,
        routeVenueId,
        isManualPosition,
        manualPositionLabel,
      ];
}

// ─── StateNotifier ────────────────────────────────────────────

class NavigationNotifier extends StateNotifier<NavigationState> {
  final NavigationService _navService;

  NavigationNotifier(this._navService) : super(const NavigationState());

  /// Cierra sola la navegación un rato después de llegar, si nadie tocó
  /// nada. Antes, llegar al destino solo cambiaba `status` a `arrived` y
  /// listo — la ruta se quedaba viva (y con ella la tarjeta "RUTA A ..." en
  /// Inicio, con su botón FINALIZAR) hasta que alguien la tocara a mano.
  /// Se cancela si el estado cambia antes de que se cumpla el plazo (p. ej.
  /// si arranca una ruta nueva), para no cerrar por accidente algo que ya
  /// no es la llegada que la programó.
  Timer? _autoFinishTimer;
  static const _autoFinishDelay = Duration(seconds: 6);

  void _scheduleAutoFinishIfArrived() {
    _autoFinishTimer?.cancel();
    if (state.status != NavStatus.arrived) return;
    _autoFinishTimer = Timer(_autoFinishDelay, () {
      if (state.status == NavStatus.arrived) {
        cancelNavigation();
      }
    });
  }

  @override
  void dispose() {
    _autoFinishTimer?.cancel();
    super.dispose();
  }

  /// Inicializa el servicio (carga el grafo del campus).
  Future<void> initialize() async {
    if (state.status != NavStatus.uninitialized) {
      return;
    }
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

  /// Establece la posición actual por ID de nodo ("Estoy Aquí" en un lugar,
  /// o escaneo QR). [label] es el nombre a mostrar en el aviso de posición
  /// manual (ver [NavigationState.isManualPosition]) — opcional porque el
  /// escaneo de QR no siempre tiene un nombre bonito a la mano.
  void setPosition(String nodeId, {String? label}) {
    final node = _navService.setCurrentPosition(nodeId);
    if (node != null) {
      NavStatus newStatus = state.status;
      int newStepIndex = state.currentStepIndex;

      if (state.activeRoute != null) {
        final idx = state.activeRoute!.steps.indexWhere((s) => s.node.id == node.id);
        if (idx != -1) {
          newStepIndex = idx;
          if (idx == state.activeRoute!.steps.length - 1) {
            newStatus = NavStatus.arrived;
          } else {
            newStatus = NavStatus.navigating;
          }
        } else {
          newStatus = NavStatus.navigating;
        }
      } else {
        newStatus = NavStatus.ready;
      }

      state = state.copyWith(
        status: newStatus,
        currentNode: node,
        currentStepIndex: newStepIndex,
        isManualPosition: true,
        manualPositionLabel: label ?? node.name,
      );
    } else {
      state = state.copyWith(
        errorMessage: 'Ubicación no reconocida: $nodeId',
      );
    }
  }

  /// Limpia la posición manual para volver al modo GPS — es la acción que
  /// dispara el botón "Quitar" del aviso de posición manual en el mapa.
  void clearManualPosition() {
    final wasManual = state.isManualPosition;
    _navService.resetManualPosition();
    state = state.copyWith(
      status: NavStatus.ready,
      isManualPosition: false,
      clearManualPositionLabel: true,
      // `currentNode` es el nodo fijado por "Estoy Aquí" — si no se limpia
      // aquí, se queda pegado (el chip "Edificio R · CAMBIAR" de Inicio lo
      // lee directo de `currentNode`, no de `isManualPosition`) hasta que
      // llegue una lectura de GPS nueva que lo reemplace. Solo se limpia si
      // de verdad era manual — si `clearManualPosition()` se llama estando
      // en modo GPS normal (p. ej. desde el botón de centrar ubicación),
      // no hay nada que limpiar.
      clearCurrentNode: wasManual,
    );
  }

  /// Establece la posición actual por coordenadas GPS.
  void setPositionByCoordinates(double lat, double lng) {
    // Si estamos en una ruta de Google (o fuera del campus)
    final isGoogleRoute = state.activeRoute != null &&
        (state.activeRoute!.origin.id == 'google_origin' || state.routePolylinePoints != null);

    if (isGoogleRoute) {
      final route = state.activeRoute!;
      int newStepIndex = state.currentStepIndex;

      // Calcular distancia al final del paso actual
      final currentStep = route.steps[newStepIndex];
      final stepDest = currentStep.node;
      final distToStepEnd = Geolocator.distanceBetween(
        lat,
        lng,
        stepDest.lat,
        stepDest.lng,
      );

      // Si está a menos de 15 metros del final del paso, avanzar
      if (distToStepEnd < 15.0 && newStepIndex < route.steps.length - 1) {
        newStepIndex++;
      }

      NavStatus newStatus = state.status;
      if (newStepIndex == route.steps.length - 1) {
        final finalDest = route.destination;
        final distToFinal = Geolocator.distanceBetween(
          lat,
          lng,
          finalDest.lat,
          finalDest.lng,
        );
        if (distToFinal < 18.0) {
          newStatus = NavStatus.arrived;
        } else {
          newStatus = NavStatus.navigating;
        }
      }

      state = state.copyWith(
        status: newStatus,
        currentStepIndex: newStepIndex,
      );
      _scheduleAutoFinishIfArrived();
      return;
    }

    final node = _navService.setPositionByCoordinates(lat, lng);
    if (node != null) {
      NavStatus newStatus = state.status;
      int newStepIndex = state.currentStepIndex;

      if (state.activeRoute != null) {
        final idx = state.activeRoute!.steps.indexWhere((s) => s.node.id == node.id);
        if (idx != -1) {
          newStepIndex = idx;
          if (idx == state.activeRoute!.steps.length - 1) {
            newStatus = NavStatus.arrived;
          } else {
            newStatus = NavStatus.navigating;
          }
        } else {
          newStatus = NavStatus.navigating;
        }

        // Respaldo: decidir la llegada solo por "¿el nodo más cercano al
        // usuario es, por casualidad, el nodo de destino?" falla si hay
        // OTRO nodo del grafo geométricamente más cerca aunque ya se llegó
        // (p. ej. un corredor justo antes de la puerta) — así que además
        // se compara la distancia real al destino, sin depender de que el
        // snap-to-node adivine el nodo correcto.
        if (newStatus != NavStatus.arrived) {
          final destNode = state.activeRoute!.destination;
          final distToDestination =
              Geolocator.distanceBetween(lat, lng, destNode.lat, destNode.lng);
          if (distToDestination < 18.0) {
            newStepIndex = state.activeRoute!.steps.length - 1;
            newStatus = NavStatus.arrived;
          }
        }
      } else {
        newStatus = NavStatus.ready;
      }

      state = state.copyWith(
        status: newStatus,
        currentNode: node,
        currentStepIndex: newStepIndex,
      );
      _scheduleAutoFinishIfArrived();
    }
  }

  /// Calcula y activa la navegación a un destino por texto.
  void navigateTo(String destinationQuery) {
    _autoFinishTimer?.cancel();
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
        routeVenueId: route.destination.zoneId,
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
    _autoFinishTimer?.cancel();
    state = state.copyWith(
      status: NavStatus.ready,
      currentStepIndex: 0,
      pendingARNavigation: false,
      clearActiveRoute: true,
      clearRoutePolyline: true,
      clearDestinationName: true,
    );
  }

  /// Establece una ruta de Google Routes API (polyline directa) con instrucciones.
  void setGoogleRoute({
    required List<List<double>> polylinePoints,
    required NavRoute googleRoute,
    String? destinationName,
    int? distanceMeters,
  }) {
    state = state.copyWith(
      status: NavStatus.navigating,
      activeRoute: googleRoute,
      routePolylinePoints: polylinePoints,
      destinationName: destinationName,
      routeDistanceMeters: distanceMeters,
      pendingARNavigation: true,
    );
  }

  /// Traza la ruta con el grafo caminable propio (Dijkstra), sin red.
  ///
  /// Es el camino preferido desde que las 9 sedes tienen sus andadores
  /// trazados (`assets/maps/venues_bundle.json`): es gratis, instantáneo y
  /// funciona sin señal. Cada llamada a la API de Google cuesta dinero, y con
  /// 40,000 asistentes esa diferencia son cientos de dólares.
  ///
  /// Devuelve `false` si el grafo no cubre ese trayecto, para que quien
  /// llama decida si recurre a Google.
  bool calcularRutaLocal({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String? destinationName,
  }) {
    final graph = _navService.graph;
    if (graph == null || graph.nodes.isEmpty) return false;

    CampusNode? masCercano(double lat, double lng) {
      CampusNode? mejor;
      var minima = double.infinity;
      for (final n in graph.nodes.values) {
        final d = Geolocator.distanceBetween(lat, lng, n.lat, n.lng);
        if (d < minima) {
          minima = d;
          mejor = n;
        }
      }
      // Si el nodo más cercano está lejísimos, el grafo no cubre esta zona:
      // mejor decirlo que trazar una ruta que empieza a 2 km del usuario.
      return minima <= _maxEnganche ? mejor : null;
    }

    final desde = masCercano(originLat, originLng);
    final hasta = masCercano(destLat, destLng);
    if (desde == null || hasta == null) return false;
    if (desde.id == hasta.id) {
      final d = Geolocator.distanceBetween(originLat, originLng, destLat, destLng);
      if (d > 1.0) {
        final puntos = [
          [originLat, originLng],
          [destLat, destLng],
        ];
        final directRoute = NavRoute(
          steps: [
            RouteStep(
              node: desde,
              voiceInstruction: 'Tu destino está a ${d.round()} metros.',
            ),
            RouteStep(
              node: hasta,
              voiceInstruction: 'Has llegado a ${destinationName ?? hasta.name}.',
            ),
          ],
          totalDistance: d,
          estimatedMinutes: d / 72.0,
          fullyAccessible: true,
          origin: desde,
          destination: hasta,
        );
        _autoFinishTimer?.cancel();
        state = state.copyWith(
          status: NavStatus.navigating,
          activeRoute: directRoute,
          routePolylinePoints: puntos,
          destinationName: destinationName,
          routeDistanceMeters: d.round(),
          pendingARNavigation: true,
        );
        return true;
      }
      return false; // ya está ahí; lo resuelve la UI
    }

    final ruta = _navService.calculateRouteById(desde.id, hasta.id);
    if (ruta == null || ruta.steps.length < 2) return false;

    // Obtener los puntos con curvas fluidas estilo Google Maps (preserva andadores,
    // pasillos y redondea las esquinas con curvas de Bézier).
    final puntos = ruta.getPolylinePoints(
      origin: [originLat, originLng],
      destination: [destLat, destLng],
    );

    _autoFinishTimer?.cancel();
    state = state.copyWith(
      status: NavStatus.navigating,
      activeRoute: ruta,
      routePolylinePoints: puntos,
      destinationName: destinationName,
      routeDistanceMeters: ruta.totalDistance.round(),
      pendingARNavigation: true,
    );
    return true;
  }

  /// Qué tan lejos puede estar el nodo de grafo más cercano para considerar
  /// que el grafo cubre ese punto. Más allá, la ruta local sería una mentira.
  static const double _maxEnganche = 400.0;

  /// Establece un estado de error al calcular una ruta (ej. por estar demasiado lejos)
  void setRouteError(String errorMessage) {
    _autoFinishTimer?.cancel();
    state = state.copyWith(
      status: NavStatus.error,
      errorMessage: errorMessage,
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
