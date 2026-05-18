import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/cache/map_cache_service.dart';
import 'package:navia/services/navigation/dijkstra.dart';

/// Carga y gestiona el grafo del campus desde el JSON en assets.
///
/// Convierte el JSON en una lista de adyacencia bidireccional y expone
/// un motor [Dijkstra] listo para pathfinding.
///
/// Estrategia de carga offline-first:
///  1. Intenta leer desde la caché Hive (funciona sin internet).
///  2. Si la caché falla, lee directamente de los assets como fallback.
class CampusGraph {
  /// Todos los nodos del campus, indexados por id.
  final Map<String, CampusNode> nodes;

  /// Todas las aristas originales (sin duplicar bidireccionales).
  final List<CampusEdge> edges;

  /// Lista de adyacencia: nodeId → aristas salientes (bidireccional).
  final Map<String, List<CampusEdge>> adjacency;

  /// Motor de Dijkstra preconfigurado.
  late final Dijkstra dijkstra;

  CampusGraph._({
    required this.nodes,
    required this.edges,
    required this.adjacency,
  }) {
    dijkstra = Dijkstra(adjacency: adjacency, nodes: nodes);
  }

  /// Carga el grafo con estrategia offline-first:
  ///  1. Caché Hive (instantáneo, funciona offline)
  ///  2. Assets originales (fallback)
  static Future<CampusGraph> load() async {
    // 1. Intentar desde caché Hive
    try {
      final cachedData = await MapCacheService.loadCachedMapData();
      if (cachedData != null) {
        final nodes = cachedData['nodes'] as List<dynamic>? ?? [];
        if (nodes.isNotEmpty) {
          debugPrint('CampusGraph: cargado desde caché Hive ✓');
          return CampusGraph.fromJson(cachedData);
        }
      }
    } catch (e) {
      debugPrint('CampusGraph: error leyendo caché → $e');
    }

    // 2. Fallback: leer directamente de assets
    debugPrint('CampusGraph: leyendo desde assets (fallback)');
    return _loadFromAssets();
  }

  /// Lee los archivos JSON directamente de los assets.
  static Future<CampusGraph> _loadFromAssets() async {
    final mapFiles = [
      'assets/maps/tec_colima_map.json',
      'assets/maps/sendera_map.json',
      'assets/maps/zentralia_map.json',
    ];

    final allNodes = <dynamic>[];
    final allEdges = <dynamic>[];

    for (final file in mapFiles) {
      try {
        final jsonStr = await rootBundle.loadString(file);
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        allNodes.addAll(data['nodes'] as List<dynamic>);
        allEdges.addAll(data['edges'] as List<dynamic>);
      } catch (e) {
        // Si un archivo falla, continúa con los demás
        continue;
      }
    }

    final mergedData = {
      'nodes': allNodes,
      'edges': allEdges,
    };

    return CampusGraph.fromJson(mergedData);
  }

  /// Construye el grafo desde un Map ya parseado.
  factory CampusGraph.fromJson(Map<String, dynamic> data) {
    // Parsear nodos
    final nodesList = ((data['nodes'] as List<dynamic>?) ?? [])
        .map((n) => CampusNode.fromJson((n as Map<String, dynamic>?) ?? {}))
        .toList();

    final nodesMap = <String, CampusNode>{};
    for (final node in nodesList) {
      if (node.id.isNotEmpty) {
        nodesMap[node.id] = node;
      }
    }

    // Parsear aristas
    final edgesList = ((data['edges'] as List<dynamic>?) ?? [])
        .map((e) => CampusEdge.fromJson((e as Map<String, dynamic>?) ?? {}))
        .toList();

    // Construir lista de adyacencia BIDIRECCIONAL
    final adjacency = <String, List<CampusEdge>>{};

    for (final nodeId in nodesMap.keys) {
      adjacency[nodeId] = [];
    }

    for (final edge in edgesList) {
      // Validar que AMBOS nodos existan antes de agregar la arista
      if (!nodesMap.containsKey(edge.from) || !nodesMap.containsKey(edge.to)) {
        continue; // Ignorar aristas rotas (previene crashes en Dijkstra)
      }

      // Dirección original: from → to
      adjacency[edge.from]?.add(edge);

      // Solo agregar dirección inversa automática si NO existe ya una arista manual en ese sentido
      final manualReverse =
          edgesList.any((e) => e.from == edge.to && e.to == edge.from);
      if (!manualReverse) {
        adjacency[edge.to]?.add(CampusEdge(
          from: edge.to,
          to: edge.from,
          distance: edge.distance,
          accessible: edge.accessible,
          direction: _reverseDirection(edge, nodesMap),
        ));
      }
    }

    return CampusGraph._(
      nodes: nodesMap,
      edges: edgesList,
      adjacency: adjacency,
    );
  }

  /// Busca un nodo por su nombre, id o alias.
  /// Útil para resolver comandos de voz como "llévame a la biblioteca".
  CampusNode? findNodeByQuery(String query) {
    final q = query.toLowerCase().trim();

    // 1. Búsqueda exacta por id
    if (nodes.containsKey(q)) return nodes[q];

    // 2. Búsqueda por nombre o alias
    CampusNode? bestMatch;
    int bestScore = 0;

    for (final node in nodes.values) {
      // Sólo buscar en destinos válidos (no en corredores internos)
      if (!node.isDestination && !node.matchesQuery(q)) continue;

      if (node.matchesQuery(q)) {
        // Dar mayor puntaje a coincidencias exactas del nombre
        final nameScore = node.name.toLowerCase() == q ? 100 : 10;
        // Dar puntaje extra a edificios sobre corredores
        final typeScore = node.isDestination ? 50 : 0;
        final score = nameScore + typeScore;

        if (score > bestScore) {
          bestScore = score;
          bestMatch = node;
        }
      }
    }

    return bestMatch;
  }

  /// Obtiene todos los nodos que son destinos válidos (para listar al usuario).
  List<CampusNode> get destinations =>
      nodes.values.where((n) => n.isDestination).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Obtiene los nodos cercanos a una coordenada GPS.
  List<CampusNode> nearbyNodes(double lat, double lng, {double radiusM = 50}) {
    return nodes.values.where((n) {
      final dist = _haversineMeters(lat, lng, n.lat, n.lng);
      return dist <= radiusM;
    }).toList();
  }

  /// Genera la instrucción inversa para la arista de regreso.
  static String _reverseDirection(
    CampusEdge edge,
    Map<String, CampusNode> nodesMap,
  ) {
    final fromNode = nodesMap[edge.from];
    final toNode = nodesMap[edge.to];
    if (fromNode != null && toNode != null) {
      return 'Camina hacia ${fromNode.name}';
    }
    return 'Regresa por el mismo camino';
  }

  /// Distancia Haversine simplificada (metros) para distancias cortas.
  static double _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * _cos(lat1);
    final dLat = (lat2 - lat1) * metersPerDegLat;
    final dLng = (lng2 - lng1) * metersPerDegLng;
    return _sqrt(dLat * dLat + dLng * dLng);
  }

  // Evitamos importar dart:math para mantener independencia
  static double _cos(double degrees) {
    const pi = 3.14159265358979;
    return _cosRad(degrees * pi / 180.0);
  }

  static double _cosRad(double x) {
    // Aproximación Taylor para cos(x)
    final x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}
