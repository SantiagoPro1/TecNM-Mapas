import 'dart:math' as math;
import 'package:navia/data/models/campus_node.dart';
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
  ///
  /// También limpia [_currentNodeId] — sin esto, aunque la bandera se
  /// apagara, el nodo fijado por "Estoy Aquí" seguía viviendo aquí. Eso
  /// importaba porque `calculateAccessibleRoute` (en map_screen.dart) usa
  /// `currentNodeId` como respaldo de origen cuando todavía no hay una
  /// lectura de GPS real disponible (p. ej. sin señal/GPS lento) — sin
  /// limpiarlo, una ruta trazada justo después de "Quitar" (y antes de que
  /// llegara una lectura de GPS nueva) terminaba usando el lugar viejo como
  /// si la persona siguiera parada ahí.
  void resetManualPosition() {
    if (_isManualPosition) _currentNodeId = null;
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
    final closest = nearby.first;

    // Si el nodo más cercano es un andador o vértice sin nombre (típico en sedes
    // con grafo de caminos OSM), buscamos si hay un punto o cancha con nombre
    // dentro de 100 metros para que la UI muestre el lugar real en vez de un vacío.
    if (closest.name.trim().isEmpty) {
      CampusNode? nearestNamed;
      double minNamedDist = double.infinity;
      for (final n in nearby) {
        if (n.name.trim().isNotEmpty) {
          final d = _approxDistMeters(lat, lng, n.lat, n.lng);
          if (d < minNamedDist) {
            minNamedDist = d;
            nearestNamed = n;
          }
        }
      }
      if (nearestNamed != null && minNamedDist <= 100) {
        final prefix = minNamedDist < 25 ? 'En' : 'Cerca de';
        return closest.copyWith(name: '$prefix ${nearestNamed.name}');
      }
    }

    return closest;
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

  static double _calculateBearing(
      double lat1, double lng1, double lat2, double lng2) {
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
    final b = math.atan2(y, x) * 180.0 / math.pi;
    return (b + 360.0) % 360.0;
  }

  static double _bearingDiff(double b1, double b2) {
    var diff = b2 - b1;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    return diff;
  }

  /// Convierte un DijkstraResult en un NavRoute con maniobras e instrucciones
  /// de voz profesionales estilo Google Maps.
  NavRoute _buildNavRoute(DijkstraResult result) {
    final steps = <RouteStep>[];
    final path = result.path;
    final totalSteps = path.length;
    final destNode = result.destination;
    final destName = destNode.name.isNotEmpty ? destNode.name : 'tu destino';

    for (int i = 0; i < totalSteps; i++) {
      final nodeId = path[i];
      final node = _graph!.nodes[nodeId]!;
      final edge = i < result.edges.length ? result.edges[i] : null;
      final nextNode = i + 1 < totalSteps ? _graph!.nodes[path[i + 1]] : null;
      final prevNode = i > 0 ? _graph!.nodes[path[i - 1]] : null;
      final segDistance = edge?.distance ?? 0.0;

      RouteManeuver maneuver = RouteManeuver.straight;
      String title = '';
      String voiceInstruction = '';

      if (i == 0) {
        // Inicio de la ruta
        maneuver = RouteManeuver.depart;
        title = 'Inicia tu recorrido';
        if (totalSteps == 1) {
          title = 'Estás en tu destino';
          voiceInstruction = 'Ya estás en $destName.';
          maneuver = RouteManeuver.arrive;
        } else {
          final targetText = (nextNode != null &&
                  nextNode.name.isNotEmpty &&
                  nextNode.type != NodeType.corridor)
              ? nextNode.name
              : destName;
          voiceInstruction =
              'Inicia tu recorrido y avanza ${segDistance.round()} metros hacia $targetText.';
        }
      } else if (i == totalSteps - 1) {
        // Llegada al destino final
        maneuver = RouteManeuver.arrive;
        title = 'Llegada: $destName';
        voiceInstruction = 'Has llegado a $destName.';
      } else {
        // Pasos intermedios: calcular ángulo de giro entre (prev -> curr) y (curr -> next)
        double diff = 0.0;
        if (prevNode != null && nextNode != null) {
          final bIn = _calculateBearing(
              prevNode.lat, prevNode.lng, node.lat, node.lng);
          final bOut = _calculateBearing(
              node.lat, node.lng, nextNode.lat, nextNode.lng);
          diff = _bearingDiff(bIn, bOut);
        }

        if (diff.abs() <= 25.0) {
          maneuver = RouteManeuver.straight;
          title = 'Continúa recto';
        } else if (diff > 25.0 && diff <= 65.0) {
          maneuver = RouteManeuver.slightRight;
          title = 'Gira ligeramente a la derecha';
        } else if (diff > 65.0 && diff <= 120.0) {
          maneuver = RouteManeuver.turnRight;
          title = 'Gira a la derecha';
        } else if (diff > 120.0) {
          maneuver = RouteManeuver.sharpRight;
          title = 'Gira a la derecha';
        } else if (diff < -25.0 && diff >= -65.0) {
          maneuver = RouteManeuver.slightLeft;
          title = 'Gira ligeramente a la izquierda';
        } else if (diff < -65.0 && diff >= -120.0) {
          maneuver = RouteManeuver.turnLeft;
          title = 'Gira a la izquierda';
        } else {
          maneuver = RouteManeuver.sharpLeft;
          title = 'Gira a la izquierda';
        }

        // Si la arista tiene dirección explícita personalizada, respetarla
        final edgeDir = edge?.direction.trim() ?? '';
        final distText =
            segDistance > 0 ? '${segDistance.round()} metros' : '';

        if (edgeDir.isNotEmpty) {
          voiceInstruction = '$title por $edgeDir';
          if (distText.isNotEmpty) voiceInstruction += ' durante $distText';
          voiceInstruction += '.';
        } else if (node.name.isNotEmpty && node.type != NodeType.corridor) {
          voiceInstruction = '$title pasando por ${node.name}';
          if (distText.isNotEmpty) voiceInstruction += ' por $distText';
          voiceInstruction += ' hacia $destName.';
        } else {
          voiceInstruction = '$title por el andador';
          if (distText.isNotEmpty) voiceInstruction += ' durante $distText';
          voiceInstruction += '.';
        }
      }

      steps.add(RouteStep(
        node: node,
        edge: edge,
        voiceInstruction: voiceInstruction,
        maneuver: maneuver,
        distanceMeters: segDistance,
        title: title,
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
