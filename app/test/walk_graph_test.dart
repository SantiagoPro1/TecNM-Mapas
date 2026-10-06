import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/services/navigation/campus_graph.dart';

/// El grafo caminable de las 9 sedes (trazado desde OpenStreetMap por
/// `scripts/build_walk_graph.py`) es lo que permite calcular rutas sin llamar
/// a la API de pago de Google. Si se rompe, la app vuelve a gastar dinero en
/// cada "Trazar Ruta" sin que nadie lo note: solo se ve en la factura.
///
/// Por eso estas pruebas corren Dijkstra de verdad sobre el archivo real.
void main() {
  late Map<String, dynamic> bundle;

  setUpAll(() {
    bundle = json.decode(
      File('assets/maps/venues_bundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  double metros(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final p1 = lat1 * pi / 180, p2 = lat2 * pi / 180;
    final dp = (lat2 - lat1) * pi / 180, dl = (lon2 - lon1) * pi / 180;
    final a = pow(sin(dp / 2), 2) + cos(p1) * cos(p2) * pow(sin(dl / 2), 2);
    return 2 * r * asin(sqrt(a.toDouble()));
  }

  CampusGraph grafoDe(String vid) {
    final cols = (bundle['venues'] as Map<String, dynamic>)[vid]
        as Map<String, dynamic>;
    final nodes = (cols['nodes'] as List)
        .cast<Map<String, dynamic>>()
        .map((n) => CampusNode.fromFirestoreMap(vid, n['id'] as String, n))
        .toList();
    final edges = (cols['edges'] as List)
        .cast<Map<String, dynamic>>()
        .map((e) => CampusEdge.fromFirestoreMap(vid, e))
        .toList();
    return CampusGraph.fromParsed(nodes, edges);
  }

  test('las 9 sedes tienen caminos trazados', () {
    for (final v in VenueRegistry.all) {
      final cols = (bundle['venues'] as Map<String, dynamic>)[v.id]
          as Map<String, dynamic>;
      expect((cols['nodes'] as List), isNotEmpty,
          reason: '${v.id} se quedó sin nodos de camino');
      expect((cols['edges'] as List), isNotEmpty,
          reason: '${v.id} se quedó sin aristas: no se le puede trazar ruta');
    }
  });

  test('toda arista apunta a nodos que existen', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    for (final entry in venues.entries) {
      final cols = entry.value as Map<String, dynamic>;
      final ids = (cols['nodes'] as List)
          .map((n) => (n as Map)['id'] as String)
          .toSet();
      for (final e in (cols['edges'] as List).cast<Map<String, dynamic>>()) {
        expect(ids.contains(e['from']), isTrue,
            reason: '${entry.key}: arista desde un nodo inexistente '
                '(${e['from']})');
        expect(ids.contains(e['to']), isTrue,
            reason: '${entry.key}: arista hacia un nodo inexistente '
                '(${e['to']})');
      }
    }
  });

  test('cada punto de interés es también un nodo del grafo', () {
    // Sin esto no se le puede pedir una ruta a esa cancha: la app pide la
    // ruta por el id del punto.
    final venues = bundle['venues'] as Map<String, dynamic>;
    for (final entry in venues.entries) {
      final cols = entry.value as Map<String, dynamic>;
      final ids = (cols['nodes'] as List)
          .map((n) => (n as Map)['id'] as String)
          .toSet();
      for (final p in (cols['places'] as List).cast<Map<String, dynamic>>()) {
        expect(ids.contains(p['id']), isTrue,
            reason: '${entry.key}: el punto ${p['id']} no está en el grafo');
      }
    }
  });

  test('Dijkstra encuentra ruta entre TODOS los pares de puntos', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    final sinRuta = <String>[];
    for (final entry in venues.entries) {
      final grafo = grafoDe(entry.key);
      final cols = entry.value as Map<String, dynamic>;
      final pois = (cols['places'] as List)
          .map((p) => (p as Map)['id'] as String)
          .toList();
      for (var i = 0; i < pois.length; i++) {
        for (var j = i + 1; j < pois.length; j++) {
          final r = grafo.dijkstra.findShortestPath(pois[i], pois[j]);
          if (r == null) sinRuta.add('${entry.key}: ${pois[i]} → ${pois[j]}');
        }
      }
    }
    expect(sinRuta, isEmpty,
        reason: 'trayectos sin ruta posible: ${sinRuta.take(10)}');
  });

  test('ninguna ruta da un rodeo absurdo', () {
    // Una ruta a pie razonable no pasa de ~8 veces la distancia en línea
    // recta. Más que eso delata un grafo mal conectado que obliga a rodear,
    // y al usuario le parece que la app está rota.
    final venues = bundle['venues'] as Map<String, dynamic>;
    final absurdas = <String>[];
    for (final entry in venues.entries) {
      final grafo = grafoDe(entry.key);
      final cols = entry.value as Map<String, dynamic>;
      final pois = (cols['places'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < pois.length; i++) {
        for (var j = i + 1; j < pois.length; j++) {
          final recta = metros(
            (pois[i]['latitude'] as num).toDouble(),
            (pois[i]['longitude'] as num).toDouble(),
            (pois[j]['latitude'] as num).toDouble(),
            (pois[j]['longitude'] as num).toDouble(),
          );
          if (recta < 30) continue; // a esa distancia el cociente no dice nada
          final r = grafo.dijkstra.findShortestPath(
              pois[i]['id'] as String, pois[j]['id'] as String);
          if (r == null) continue;
          final ratio = r.totalDistance / recta;
          if (ratio > 8) {
            absurdas.add('${entry.key}: ${pois[i]['id']} → ${pois[j]['id']} '
                '(${ratio.toStringAsFixed(1)}x)');
          }
        }
      }
    }
    expect(absurdas, isEmpty, reason: 'rodeos excesivos: ${absurdas.take(10)}');
  });

  test('ninguna ruta salta por otros puntos de interés intermedios', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    final conSaltos = <String>[];
    for (final entry in venues.entries) {
      final grafo = grafoDe(entry.key);
      final cols = entry.value as Map<String, dynamic>;
      final pois = (cols['places'] as List).cast<Map<String, dynamic>>();
      final poiIds = pois.map((p) => p['id'] as String).toSet();
      for (var i = 0; i < pois.length; i++) {
        for (var j = i + 1; j < pois.length; j++) {
          final id1 = pois[i]['id'] as String;
          final id2 = pois[j]['id'] as String;
          final r = grafo.dijkstra.findShortestPath(id1, id2);
          if (r == null) continue;
          final intermedios = r.path
              .sublist(1, r.path.length - 1)
              .where((nid) => poiIds.contains(nid))
              .toList();
          if (intermedios.isNotEmpty) {
            conSaltos.add('${entry.key}: $id1 → $id2 pasando por $intermedios');
          }
        }
      }
    }
    expect(conSaltos, isEmpty,
        reason: 'rutas que saltan por otros puntos: ${conSaltos.take(10)}');
  });
}
