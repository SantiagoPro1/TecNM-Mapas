import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/repositories/venue_bundle.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/venue.dart';
import 'package:navia/data/cache/map_cache_service.dart';
import 'package:navia/data/repositories/venue_graph_repository.dart';
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
          debugPrint('CampusGraph: cargado desde caché Hive');
          // La caché Hive solo guarda el mapa histórico de TecNM Colima, así
          // que los caminos de las otras 8 sedes se fusionan encima. Sin
          // esto, un teléfono con caché previa se quedaba sin los caminos
          // nuevos y volvía a depender de la API de pago de Google.
          await _agregarCaminosDelPaquete(
            cachedData['nodes'] as List<dynamic>,
            cachedData['edges'] as List<dynamic>? ?? [],
          );
          return await compute(CampusGraph.fromJson, cachedData);
        }
      }
    } catch (e) {
      debugPrint('CampusGraph: error leyendo caché → $e');
    }

    // 2. Fallback: leer directamente de assets
    debugPrint('CampusGraph: leyendo desde assets (fallback)');
    return _loadFromAssets();
  }

  /// Lee los archivos JSON directamente de los assets (todas las sedes
  /// empaquetadas, fusionadas en un solo grafo — comportamiento histórico
  /// usado por [load]).
  static Future<CampusGraph> _loadFromAssets() async {
    final bundledStrings = <String, String>{};
    for (final venue in VenueRegistry.bundledVenues) {
      if (venue.mapAssetPath != null) {
        try {
          bundledStrings[venue.id] =
              await rootBundle.loadString(venue.mapAssetPath!);
        } catch (_) {}
      }
    }

    String? bundleRaw;
    try {
      bundleRaw = await rootBundle.loadString(VenueBundle.assetPath);
    } catch (_) {}

    return compute(_parseGraphFromStrings, (bundledStrings, bundleRaw));
  }

  static CampusGraph _parseGraphFromStrings(
      (Map<String, String>, String?) args) {
    final (bundledStrings, bundleRaw) = args;
    final allNodes = <dynamic>[];
    final allEdges = <dynamic>[];

    for (final entry in bundledStrings.entries) {
      try {
        final data = json.decode(entry.value) as Map<String, dynamic>;
        final zoneId =
            (data['meta'] as Map<String, dynamic>?)?['zoneId'] as String? ??
                entry.key;

        for (final n in (data['nodes'] as List<dynamic>? ?? [])) {
          (n as Map<String, dynamic>).putIfAbsent('zoneId', () => zoneId);
        }
        for (final e in (data['edges'] as List<dynamic>? ?? [])) {
          (e as Map<String, dynamic>).putIfAbsent('zoneId', () => zoneId);
        }

        allNodes.addAll(data['nodes'] as List<dynamic>? ?? []);
        allEdges.addAll(data['edges'] as List<dynamic>? ?? []);
      } catch (_) {
        continue;
      }
    }

    if (bundleRaw != null) {
      try {
        final bundle = json.decode(bundleRaw) as Map<String, dynamic>;
        final venues = bundle['venues'] as Map<String, dynamic>? ?? {};
        for (final entry in venues.entries) {
          final cols = entry.value as Map<String, dynamic>;
          for (final x in (cols['nodes'] as List<dynamic>? ?? [])) {
            (x as Map<String, dynamic>).putIfAbsent('zoneId', () => entry.key);
            allNodes.add(x);
          }
          for (final x in (cols['edges'] as List<dynamic>? ?? [])) {
            (x as Map<String, dynamic>).putIfAbsent('zoneId', () => entry.key);
            allEdges.add(x);
          }
        }
      } catch (_) {}
    }

    final mergedData = {
      'nodes': allNodes,
      'edges': allEdges,
    };

    return CampusGraph.fromJson(mergedData);
  }

  /// Fusiona en [nodos]/[aristas] los caminos peatonales de las 9 sedes del
  /// evento, trazados desde OpenStreetMap y empaquetados en
  /// `assets/maps/venues_bundle.json`. Se procesa en un isolate para no congelar la UI.
  static Future<void> _agregarCaminosDelPaquete(
    List<dynamic> nodos,
    List<dynamic> aristas,
  ) async {
    try {
      final raw = await rootBundle.loadString(VenueBundle.assetPath);
      final (extraNodes, extraEdges) = await compute(_parseBundleJson, raw);
      nodos.addAll(extraNodes);
      aristas.addAll(extraEdges);
      debugPrint('CampusGraph: ${extraNodes.length} nodos de caminos agregados del paquete');
    } catch (e) {
      debugPrint('CampusGraph: no se pudieron leer los caminos del paquete → $e');
    }
  }

  static (List<dynamic>, List<dynamic>) _parseBundleJson(String raw) {
    final bundle = json.decode(raw) as Map<String, dynamic>;
    final venues = bundle['venues'] as Map<String, dynamic>? ?? {};
    final nodos = <dynamic>[];
    final aristas = <dynamic>[];
    for (final entry in venues.entries) {
      final cols = entry.value as Map<String, dynamic>;
      for (final x in (cols['nodes'] as List<dynamic>? ?? [])) {
        (x as Map<String, dynamic>).putIfAbsent('zoneId', () => entry.key);
        nodos.add(x);
      }
      for (final x in (cols['edges'] as List<dynamic>? ?? [])) {
        (x as Map<String, dynamic>).putIfAbsent('zoneId', () => entry.key);
        aristas.add(x);
      }
    }
    return (nodos, aristas);
  }

  /// Carga el grafo de una sola sede.
  ///  - Si la sede tiene JSON empaquetado, lo lee de assets.
  ///  - Si no (sedes del Evento Nacional Deportivo), lo lee de Firestore.
  static Future<CampusGraph> loadForVenue(
    Venue venue, {
    VenueGraphRepository? repo,
  }) async {
    if (venue.isBundled) {
      final jsonStr = await rootBundle.loadString(venue.mapAssetPath!);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      return CampusGraph.fromJson(data, defaultZoneId: venue.id);
    }

    final graphRepo = repo ?? VenueGraphRepository();
    final nodes = await graphRepo.fetchNodesOnce(venue.id);
    final edges = await graphRepo.fetchEdgesOnce(venue.id);
    return CampusGraph.fromParsed(nodes, edges);
  }

  /// Construye el grafo desde un Map ya parseado (JSON de assets/caché).
  ///
  /// [defaultZoneId] se usa cuando un nodo/arista no trae su propio `zoneId`
  /// explícito; si no se pasa, se intenta leer de `data['meta']['zoneId']`.
  factory CampusGraph.fromJson(Map<String, dynamic> data, {String? defaultZoneId}) {
    final zoneId = defaultZoneId ??
        (data['meta'] as Map<String, dynamic>?)?['zoneId'] as String? ??
        '';

    final nodesList = ((data['nodes'] as List<dynamic>?) ?? [])
        .map((n) => CampusNode.fromJson(
              (n as Map<String, dynamic>?) ?? {},
              zoneId: zoneId,
            ))
        .toList();

    final edgesList = ((data['edges'] as List<dynamic>?) ?? [])
        .map((e) => CampusEdge.fromJson(
              (e as Map<String, dynamic>?) ?? {},
              zoneId: zoneId,
            ))
        .toList();

    return CampusGraph.fromParsed(nodesList, edgesList);
  }

  /// Construye el grafo desde nodos/aristas ya deserializados (usado por
  /// [fromJson] y por [loadForVenue] al leer directamente de Firestore).
  factory CampusGraph.fromParsed(
    List<CampusNode> nodesList,
    List<CampusEdge> edgesList,
  ) {
    final nodesMap = <String, CampusNode>{};
    for (final node in nodesList) {
      if (node.id.isEmpty) continue;
      if (kDebugMode && nodesMap.containsKey(node.id)) {
        debugPrint(
            'CampusGraph: id de nodo duplicado entre sedes → "${node.id}" '
            '(zona "${nodesMap[node.id]!.zoneId}" pisada por "${node.zoneId}")');
      }
      nodesMap[node.id] = node;
    }

    final adjacency = _buildAdjacency(nodesMap, edgesList);

    return CampusGraph._(
      nodes: nodesMap,
      edges: edgesList,
      adjacency: adjacency,
    );
  }

  /// Construye la lista de adyacencia BIDIRECCIONAL a partir de los nodos y
  /// aristas ya resueltos. Compartido por [fromJson] (vía [fromParsed]) y por
  /// el grafo cargado en línea desde Firestore.
  static Map<String, List<CampusEdge>> _buildAdjacency(
    Map<String, CampusNode> nodesMap,
    List<CampusEdge> edgesList,
  ) {
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
          zoneId: edge.zoneId,
          from: edge.to,
          to: edge.from,
          distance: edge.distance,
          accessible: edge.accessible,
          direction: _reverseDirection(edge, nodesMap),
        ));
      }
    }

    return adjacency;
  }

  /// Mapa de pronunciaciones de letras del alfabeto español a su letra.
  /// Cubre variantes de STT para comandos tipo "edificio erre" → "edificio r".
  static const Map<String, String> _spanishLetterNames = {
    'erre': 'r', 'ere': 'r', 'rre': 'r',
    'ache': 'h', 'hache': 'h',
    'equis': 'x',
    'jota': 'j',
    'uve': 'v',
    'doble uve': 'w', 'doble v': 'w', 'doble u': 'w',
    'zeta': 'z',
    'ese': 's',
    'eme': 'm',
    'ene': 'n',
    'ele': 'l',
    'efe': 'f',
    'ka': 'k',
    'pe': 'p',
    'cu': 'q',
    'te': 't',
    'ye': 'y', 'i griega': 'y',
    'be': 'b',
    'ce': 'c',
    'ge': 'g',
    'de': 'd',
  };

  /// Normaliza pronunciaciones de letras en consultas de voz.
  /// Ej: "edificio erre" → "edificio r", "edificio ache" → "edificio h".
  static String _normalizeLetterQuery(String q) {
    for (final entry in _spanishLetterNames.entries) {
      final letterName = entry.key;
      final letter = entry.value;
      if (q.contains('edificio $letterName')) {
        return q.replaceAll('edificio $letterName', 'edificio $letter');
      }
    }
    return q;
  }

  /// Busca un nodo por su nombre, id o alias.
  /// Útil para resolver comandos de voz como "llévame a la biblioteca".
  CampusNode? findNodeByQuery(String query) {
    final q = _normalizeLetterQuery(query.toLowerCase().trim());

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
