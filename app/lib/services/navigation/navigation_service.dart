import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/services/navigation/campus_graph.dart';
import 'package:navia/services/navigation/dijkstra.dart';

/// Servicio principal de navegación del campus.
///
/// Orquesta la carga del grafo, el cálculo de rutas con Dijkstra,
/// y la generación de instrucciones de voz paso a paso.
class NavigationService {
  CampusGraph? _graph;
  bool _isLoaded = false;

  /// Indica si el grafo del campus ya fue cargado.
  bool get isLoaded => _isLoaded;

  /// Referencia al grafo cargado (null si no se ha inicializado).
  CampusGraph? get graph => _graph;

  /// Nodo actual del usuario (determinado por escaneo QR o GPS).
  String? _currentNodeId;
  String? get currentNodeId => _currentNodeId;

  /// Indica si la posición fue fijada manualmente (QR/Estoy Aquí).
  /// Si es true, las actualizaciones de GPS se ignoran hasta resetear.
  bool _isManualPosition = false;
  bool get isManualPosition => _isManualPosition;

  /// Inicializa el servicio cargando el grafo del campus desde assets.
  /// Debe llamarse una sola vez al inicio de la app.
  Future<void> initialize() async {
    if (_isLoaded) return;
    _graph = await CampusGraph.load();
    _isLoaded = true;
  }

  /// Establece la posición actual del usuario a partir del escaneo QR.
  ///
  /// [nodeId] es el ID del nodo obtenido del código QR del pasillo.
  /// Retorna el nodo encontrado, o null si el ID no existe en el grafo.
  CampusNode? setCurrentPosition(String nodeId) {
    if (_graph == null) return null;
    final node = _graph!.nodes[nodeId];
    if (node != null) {
      _currentNodeId = nodeId;
      _isManualPosition = true; // Bloquear GPS
    }
    return node;
  }

  /// Desbloquea la posición manual para volver a usar GPS real.
  void resetManualPosition() {
    _isManualPosition = false;
  }

  /// Establece la posición del usuario por coordenadas GPS.
  /// Busca el nodo más cercano a las coordenadas dadas.
  CampusNode? setPositionByCoordinates(double lat, double lng) {
    if (_graph == null) return null;

    // Si la posición fue fijada manualmente, ignoramos el GPS
    if (_isManualPosition) {
      return _graph!.nodes[_currentNodeId];
    }

    // Aumentamos el radio de búsqueda inicial a 200m para mayor tolerancia
    var nearby = _graph!.nearbyNodes(lat, lng, radiusM: 200);

    // Si no hay nodos a 200m, buscamos el más cercano absoluto en todo el grafo
    if (nearby.isEmpty) {
      CampusNode? absoluteNearest;
      double minDistance = double.infinity;

      for (final node in _graph!.nodes.values) {
        final d = _approxDistMeters(lat, lng, node.lat, node.lng);
        if (d < minDistance) {
          minDistance = d;
          absoluteNearest = node;
        }
      }
      // Solo hacer snap si está a menos de 500 metros del campus
      if (absoluteNearest != null && minDistance < 500) {
        nearby = [absoluteNearest];
      }
    }

    if (nearby.isEmpty) return null;

    // Ordenar por distancia y tomar el más cercano
    nearby.sort((a, b) {
      final distA = _approxDistMeters(lat, lng, a.lat, a.lng);
      final distB = _approxDistMeters(lat, lng, b.lat, b.lng);
      return distA.compareTo(distB);
    });

    _currentNodeId = nearby.first.id;
    return nearby.first;
  }

  /// Distancia aproximada en metros para distancias cortas.
  static double _approxDistMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const metersPerDegLat = 111320.0;
    final avgLat = (lat1 + lat2) / 2;
    final metersPerDegLng = 111320.0 * _cosApprox(avgLat);
    final dLat = (lat2 - lat1) * metersPerDegLat;
    final dLng = (lng2 - lng1) * metersPerDegLng;
    return _sqrtApprox(dLat * dLat + dLng * dLng);
  }

  static double _cosApprox(double degrees) {
    const pi = 3.14159265358979;
    final x = degrees * pi / 180.0;
    final x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24;
  }

  static double _sqrtApprox(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 15; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  /// Calcula la ruta desde la posición actual hasta un destino.
  ///
  /// [destinationQuery] puede ser un id, nombre o alias (ej. "biblioteca").
  /// [accessibleOnly] filtra rutas sin escaleras.
  ///
  /// Retorna null si:
  /// - No hay posición actual establecida
  /// - No se encontró el destino
  /// - No existe ruta posible
  NavRoute? calculateRoute(
    String destinationQuery, {
    bool accessibleOnly = false,
  }) {
    if (_graph == null || _currentNodeId == null) return null;

    // Resolver el destino por query de texto
    final destinationNode = _graph!.findNodeByQuery(destinationQuery);
    if (destinationNode == null) return null;

    return calculateRouteById(
      _currentNodeId!,
      destinationNode.id,
      accessibleOnly: accessibleOnly,
    );
  }

  /// Calcula la ruta entre dos nodos por sus IDs exactos.
  NavRoute? calculateRouteById(
    String fromId,
    String toId, {
    bool accessibleOnly = false,
  }) {
    if (_graph == null) return null;

    final result = _graph!.dijkstra.findShortestPath(
      fromId,
      toId,
      accessibleOnly: accessibleOnly,
    );

    if (result == null) return null;

    return _buildNavRoute(result);
  }

  /// Busca los N destinos más cercanos a la posición actual.
  List<NavRoute> nearestDestinations({
    int limit = 5,
    bool accessibleOnly = false,
  }) {
    if (_graph == null || _currentNodeId == null) return [];

    final results = _graph!.dijkstra.findNearestDestinations(
      _currentNodeId!,
      limit: limit,
      accessibleOnly: accessibleOnly,
    );

    return results.map((r) => _buildNavRoute(r)).toList();
  }

  /// Busca un nodo del campus por texto libre (voz o teclado).
  CampusNode? findDestination(String query) {
    return _graph?.findNodeByQuery(query);
  }

  /// Lista todos los destinos válidos del campus.
  List<CampusNode> get allDestinations => _graph?.destinations ?? [];

  /// Nodo actual del usuario.
  CampusNode? get currentNode {
    if (_graph == null || _currentNodeId == null) return null;
    return _graph!.nodes[_currentNodeId!];
  }

  /// Convierte un DijkstraResult en un NavRoute con instrucciones de voz.
  NavRoute _buildNavRoute(DijkstraResult result) {
    final steps = <RouteStep>[];

    for (int i = 0; i < result.path.length; i++) {
      final nodeId = result.path[i];
      final node = _graph!.nodes[nodeId]!;

      CampusEdge? edge;
      String voiceInstruction;

      if (i == 0) {
        // Primer paso: ir directo a la indicación (el origen ya se muestra
        // por separado en la tarjeta de ubicación actual).
        if (i < result.edges.length) {
          edge = result.edges[i];
          voiceInstruction = '${edge.direction}.';
        } else {
          voiceInstruction = 'Dirígete hacia tu destino.';
        }
      } else if (i == result.path.length - 1) {
        // Último paso: anunciar llegada
        voiceInstruction = 'Has llegado a ${node.name}. ${node.description}.';
      } else {
        // Pasos intermedios: usar la instrucción de la arista
        if (i - 1 < result.edges.length) {
          edge = (i < result.edges.length) ? result.edges[i] : null;

          voiceInstruction = 'Pasando por ${node.name}.';

          if (edge != null) {
            voiceInstruction += ' ${edge.direction}.';
            voiceInstruction += ' ${edge.distance.round()} metros.';
          }
        } else {
          voiceInstruction = 'Continúa por ${node.name}.';
        }
      }

      steps.add(RouteStep(
        node: node,
        edge: edge,
        voiceInstruction: voiceInstruction,
      ));
    }

    return NavRoute(
      steps: steps,
      totalDistance: result.totalDistance,
      estimatedMinutes: result.estimatedMinutes,
      fullyAccessible: result.fullyAccessible,
      origin: result.origin,
      destination: result.destination,
    );
  }
}
