import 'dart:collection';
import 'package:sinait/data/models/campus_node.dart';
import 'package:sinait/data/models/campus_edge.dart';

/// Implementación del algoritmo de Dijkstra adaptada para el grafo del campus.
///
/// Calcula la ruta más corta (por distancia en metros) entre dos nodos,
/// con la opción de filtrar sólo aristas accesibles (sin escaleras).
class Dijkstra {
  /// Lista de adyacencia: nodeId → lista de aristas salientes.
  final Map<String, List<CampusEdge>> _adjacency;

  /// Mapa de nodos por id para lookup rápido.
  final Map<String, CampusNode> _nodes;

  Dijkstra({
    required Map<String, List<CampusEdge>> adjacency,
    required Map<String, CampusNode> nodes,
  })  : _adjacency = adjacency,
        _nodes = nodes;

  /// Busca la ruta más corta desde [startId] hasta [endId].
  ///
  /// Si [accessibleOnly] es true, ignora aristas con `accessible == false`
  /// (escaleras, pasos sin rampa, etc.).
  ///
  /// Retorna `null` si no existe ruta posible.
  DijkstraResult? findShortestPath(
    String startId,
    String endId, {
    bool accessibleOnly = false,
  }) {
    // Validar que ambos nodos existen
    if (!_nodes.containsKey(startId) || !_nodes.containsKey(endId)) {
      return null;
    }

    // Distancias mínimas conocidas
    final distances = <String, double>{};
    // Nodo anterior en la ruta óptima
    final previous = <String, String?>{};
    // Arista usada para llegar a cada nodo
    final usedEdge = <String, CampusEdge?>{};
    // Set de nodos ya procesados
    final visited = <String>{};

    // Priority Queue: (distancia, nodeId)
    // Usamos SplayTreeSet para simular una min-heap
    final queue = SplayTreeSet<_QueueEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        if (cmp != 0) return cmp;
        return a.nodeId.compareTo(b.nodeId);
      },
    );

    // Inicialización
    for (final nodeId in _nodes.keys) {
      distances[nodeId] = double.infinity;
      previous[nodeId] = null;
      usedEdge[nodeId] = null;
    }
    distances[startId] = 0;
    queue.add(_QueueEntry(0, startId));

    while (queue.isNotEmpty) {
      final current = queue.first;
      queue.remove(current);

      if (visited.contains(current.nodeId)) continue;
      visited.add(current.nodeId);

      // Si llegamos al destino, terminamos
      if (current.nodeId == endId) break;

      // Explorar vecinos
      final edges = _adjacency[current.nodeId] ?? [];
      for (final edge in edges) {
        // Filtrar por accesibilidad si se requiere
        if (accessibleOnly && !edge.accessible) continue;

        final neighbor = edge.to;
        if (visited.contains(neighbor)) continue;

        final newDist = distances[current.nodeId]! + edge.distance;

        if (newDist < distances[neighbor]!) {
          distances[neighbor] = newDist;
          previous[neighbor] = current.nodeId;
          usedEdge[neighbor] = edge;
          queue.add(_QueueEntry(newDist, neighbor));
        }
      }
    }

    // Si no se encontró ruta
    if (distances[endId] == double.infinity) {
      return null;
    }

    // Reconstruir la ruta
    final path = <String>[];
    final pathEdges = <CampusEdge>[];
    String? current = endId;

    while (current != null) {
      path.add(current);
      final edge = usedEdge[current];
      if (edge != null) pathEdges.add(edge);
      current = previous[current];
    }

    path.reversed;
    pathEdges.reversed;

    return DijkstraResult(
      path: path.reversed.toList(),
      edges: pathEdges.reversed.toList(),
      totalDistance: distances[endId]!,
      nodes: _nodes,
    );
  }

  /// Busca los N destinos más cercanos desde un nodo de origen.
  List<DijkstraResult> findNearestDestinations(
    String startId, {
    int limit = 5,
    bool accessibleOnly = false,
  }) {
    final results = <DijkstraResult>[];

    for (final node in _nodes.values) {
      if (node.id == startId) continue;
      if (!node.isDestination) continue;

      final result = findShortestPath(
        startId,
        node.id,
        accessibleOnly: accessibleOnly,
      );
      if (result != null) {
        results.add(result);
      }
    }

    results.sort((a, b) => a.totalDistance.compareTo(b.totalDistance));
    return results.take(limit).toList();
  }
}

/// Resultado de una búsqueda de Dijkstra.
class DijkstraResult {
  /// IDs de los nodos en orden desde el origen al destino.
  final List<String> path;

  /// Aristas usadas en la ruta, en orden.
  final List<CampusEdge> edges;

  /// Distancia total en metros.
  final double totalDistance;

  /// Referencia al mapa de nodos.
  final Map<String, CampusNode> nodes;

  const DijkstraResult({
    required this.path,
    required this.edges,
    required this.totalDistance,
    required this.nodes,
  });

  /// Nodo de origen.
  CampusNode get origin => nodes[path.first]!;

  /// Nodo de destino.
  CampusNode get destination => nodes[path.last]!;

  /// Tiempo estimado en minutos (velocidad peatonal ~1.2 m/s).
  double get estimatedMinutes => totalDistance / 72.0; // 1.2 m/s * 60

  /// ¿Toda la ruta es accesible?
  bool get fullyAccessible => edges.every((e) => e.accessible);

  /// Nombres de los nodos en la ruta.
  List<String> get nodeNames =>
      path.map((id) => nodes[id]?.name ?? id).toList();
}

/// Entrada interna de la cola de prioridad.
class _QueueEntry {
  final double distance;
  final String nodeId;
  const _QueueEntry(this.distance, this.nodeId);
}
