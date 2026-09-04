import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
    bool clearRoutePolyline = false,
    bool clearDestinationName = false,
  }) {
    return NavigationState(
      status: status ?? this.status,
      currentNode: currentNode ?? this.currentNode,
      activeRoute: activeRoute ?? this.activeRoute,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      accessibleOnly: accessibleOnly ?? this.accessibleOnly,
      errorMessage: errorMessage,
      pendingARNavigation: pendingARNavigation ?? this.pendingARNavigation,
      routePolylinePoints: clearRoutePolyline ? null : (routePolylinePoints ?? this.routePolylinePoints),
      destinationName: clearDestinationName ? null : (destinationName ?? this.destinationName),
      routeDistanceMeters: routeDistanceMeters ?? this.routeDistanceMeters,
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
      ];
}

// ─── StateNotifier ────────────────────────────────────────────

class NavigationNotifier extends StateNotifier<NavigationState> {
  final NavigationService _navService;
  final Dio _dio = Dio();

  NavigationNotifier(this._navService) : super(const NavigationState());

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

  /// Establece la posición actual por ID de nodo (escaneo QR).
  void setPosition(String nodeId) {
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
        if (distToFinal < 15.0) {
          newStatus = NavStatus.arrived;
        } else {
          newStatus = NavStatus.navigating;
        }
      }

      state = state.copyWith(
        status: newStatus,
        currentStepIndex: newStepIndex,
      );
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
      } else {
        newStatus = NavStatus.ready;
      }

      state = state.copyWith(
        status: newStatus,
        currentNode: node,
        currentStepIndex: newStepIndex,
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

  /// Calcula una ruta usando la API de Google Routes y la establece como activa.
  /// Si falla, intenta una ruta de respaldo usando el sistema Dijkstra local del campus.
  Future<bool> calculateGoogleRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String? destinationName,
  }) async {
    state = state.copyWith(status: NavStatus.calculating);
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        _fallbackToDijkstra(destLat, destLng);
        return true;
      }

      final response = await _dio.post(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
        data: {
          "origin": {
            "location": {
              "latLng": {
                "latitude": originLat,
                "longitude": originLng
              }
            }
          },
          "destination": {
            "location": {
              "latLng": {
                "latitude": destLat,
                "longitude": destLng
              }
            }
          },
          "travelMode": "WALK",
        },
        options: Options(
          headers: {
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask':
                'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.legs.steps.navigationInstruction.instructions,routes.legs.steps.endLocation',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final routes = response.data['routes'] as List<dynamic>?;
      if (routes != null && routes.isNotEmpty) {
        final route = routes.first;
        final encodedPolyline = route['polyline']['encodedPolyline'] as String;
        final points = _decodePolyline(encodedPolyline);
        final distance = route['distanceMeters'] as int? ?? 0;

        if (points.isEmpty) {
          _fallbackToDijkstra(destLat, destLng);
          return true;
        }

        // Decodificar los pasos (turn-by-turn instructions) para NAVIA AR
        final legs = route['legs'] as List<dynamic>?;
        final List<RouteStep> routeSteps = [];
        if (legs != null && legs.isNotEmpty) {
          final stepsJson = legs.first['steps'] as List<dynamic>?;
          if (stepsJson != null) {
            for (int idx = 0; idx < stepsJson.length; idx++) {
              final s = stepsJson[idx];
              final instruction = s['navigationInstruction']?['instructions'] as String? ?? 'Sigue derecho';
              final endLoc = s['endLocation']?['latLng'];
              final lat = (endLoc?['latitude'] as num?)?.toDouble() ?? originLat;
              final lng = (endLoc?['longitude'] as num?)?.toDouble() ?? originLng;

              routeSteps.add(
                RouteStep(
                  node: CampusNode(
                    id: 'google_step_$idx',
                    zoneId: 'google_route',
                    name: instruction,
                    aliases: const [],
                    type: NodeType.corridor,
                    lat: lat,
                    lng: lng,
                    floor: 0,
                    accessible: true,
                    description: '',
                  ),
                  voiceInstruction: instruction,
                ),
              );
            }
          }
        }

        // Paso final si la lista de pasos está vacía
        if (routeSteps.isEmpty) {
          routeSteps.add(
            RouteStep(
              node: CampusNode(
                id: 'google_step_final',
                zoneId: 'google_route',
                name: destinationName ?? 'Destino',
                aliases: const [],
                type: NodeType.corridor,
                lat: destLat,
                lng: destLng,
                floor: 0,
                accessible: true,
                description: '',
              ),
              voiceInstruction: 'Llegando a ${destinationName ?? "tu destino"}.',
            ),
          );
        }

        final originNode = CampusNode(
          id: 'google_origin',
          zoneId: 'google_route',
          name: 'Mi Ubicación',
          aliases: const [],
          type: NodeType.corridor,
          lat: originLat,
          lng: originLng,
          floor: 0,
          accessible: true,
          description: '',
        );

        final destNode = CampusNode(
          id: 'google_dest',
          zoneId: 'google_route',
          name: destinationName ?? 'Destino',
          aliases: const [],
          type: NodeType.corridor,
          lat: destLat,
          lng: destLng,
          floor: 0,
          accessible: true,
          description: '',
        );

        final googleRoute = NavRoute(
          steps: routeSteps,
          totalDistance: distance.toDouble(),
          estimatedMinutes: (distance / 72.0),
          fullyAccessible: true,
          origin: originNode,
          destination: destNode,
        );

        state = state.copyWith(
          status: NavStatus.navigating,
          activeRoute: googleRoute,
          routePolylinePoints: points,
          destinationName: destinationName,
          routeDistanceMeters: distance,
          pendingARNavigation: true,
        );
        return true;
      }

      _fallbackToDijkstra(destLat, destLng);
      return true;
    } catch (e) {
      _fallbackToDijkstra(destLat, destLng);
      return true;
    }
  }

  void _fallbackToDijkstra(double destLat, double destLng) {
    final graph = _navService.graph;
    if (graph == null) {
      state = state.copyWith(
        status: NavStatus.error,
        errorMessage: 'Grafo no cargado para navegación de respaldo.',
      );
      return;
    }

    CampusNode? absoluteNearest;
    double minDistance = double.infinity;

    for (final node in graph.nodes.values) {
      final d = Geolocator.distanceBetween(destLat, destLng, node.lat, node.lng);
      if (d < minDistance) {
        minDistance = d;
        absoluteNearest = node;
      }
    }

    if (absoluteNearest != null) {
      navigateTo(absoluteNearest.name);
    } else {
      state = state.copyWith(
        status: NavStatus.error,
        errorMessage: 'No se pudo calcular la ruta de respaldo.',
      );
    }
  }

  List<List<double>> _decodePolyline(String encoded) {
    final List<List<double>> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add([lat / 1E5, lng / 1E5]);
    }
    return poly;
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
