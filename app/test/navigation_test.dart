import 'package:flutter_test/flutter_test.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/services/navigation/campus_graph.dart';

CampusNode _node(String id, {bool accessible = true}) => CampusNode(
      id: id,
      zoneId: 'test',
      name: 'Nodo $id',
      aliases: const [],
      type: NodeType.corridor,
      lat: 19.26,
      lng: -103.72,
      floor: 0,
      accessible: accessible,
      description: '',
    );

CampusEdge _edge(String from, String to, double metros,
        {bool accessible = true}) =>
    CampusEdge(
      zoneId: 'test',
      from: from,
      to: to,
      distance: metros,
      accessible: accessible,
      direction: 'Sigue derecho',
    );

void main() {
  group('Dijkstra: ruta más corta', () {
    // A --100m--> B --100m--> D   (200m en total)
    // A ---------500m--------> D  (directo pero más largo)
    final grafo = CampusGraph.fromParsed(
      [_node('A'), _node('B'), _node('D')],
      [
        _edge('A', 'B', 100),
        _edge('B', 'D', 100),
        _edge('A', 'D', 500),
      ],
    );

    test('prefiere la ruta de 200m sobre la directa de 500m', () {
      final ruta = grafo.dijkstra.findShortestPath('A', 'D');

      expect(ruta, isNotNull);
      expect(ruta!.path, ['A', 'B', 'D']);
      expect(ruta.totalDistance, 200);
    });

    test('las aristas funcionan en ambos sentidos aunque se declaren una vez',
        () {
      // Solo se declaró A→B y B→D; el grafo sintetiza el sentido inverso.
      final ruta = grafo.dijkstra.findShortestPath('D', 'A');

      expect(ruta, isNotNull);
      expect(ruta!.path, ['D', 'B', 'A']);
      expect(ruta.totalDistance, 200);
    });

    test('devuelve null si el nodo no existe', () {
      expect(grafo.dijkstra.findShortestPath('A', 'NO_EXISTE'), isNull);
      expect(grafo.dijkstra.findShortestPath('NO_EXISTE', 'A'), isNull);
    });

    test('devuelve null si no hay camino posible', () {
      final aislado = CampusGraph.fromParsed(
        [_node('A'), _node('Z')],
        [],
      );
      expect(aislado.dijkstra.findShortestPath('A', 'Z'), isNull);
    });
  });

  group('Dijkstra: filtro de accesibilidad', () {
    // El atajo A→C→B (20m) pasa por una arista NO accesible (escaleras).
    // La alternativa accesible A→B es más larga (100m).
    final grafo = CampusGraph.fromParsed(
      [_node('A'), _node('B'), _node('C')],
      [
        _edge('A', 'C', 10, accessible: false),
        _edge('C', 'B', 10),
        _edge('A', 'B', 100),
      ],
    );

    test('sin filtro toma el atajo con escaleras', () {
      final ruta = grafo.dijkstra.findShortestPath('A', 'B');
      expect(ruta!.path, ['A', 'C', 'B']);
      expect(ruta.totalDistance, 20);
    });

    test('con accessibleOnly evita las escaleras aunque sea más largo', () {
      final ruta =
          grafo.dijkstra.findShortestPath('A', 'B', accessibleOnly: true);
      expect(ruta, isNotNull);
      expect(ruta!.path, ['A', 'B']);
      expect(ruta.totalDistance, 100);
    });
  });

  group('CampusGraph: construcción', () {
    test('ignora aristas que apunten a nodos inexistentes sin reventar', () {
      // Una arista rota no debe tumbar el grafo (ni a Dijkstra después).
      final grafo = CampusGraph.fromParsed(
        [_node('A'), _node('B')],
        [
          _edge('A', 'B', 50),
          _edge('A', 'FANTASMA', 10),
        ],
      );

      expect(grafo.nodes.length, 2);
      final ruta = grafo.dijkstra.findShortestPath('A', 'B');
      expect(ruta!.totalDistance, 50);
    });
  });

  group('NavigationState: cancelar ruta', () {
    // Bug real: copyWith usaba `activeRoute ?? this.activeRoute`, así que
    // pasar `activeRoute: null` para "borrarla" nunca funcionaba (null ??
    // x siempre regresa x). Resultado: al cancelar, la ruta seguía viva en
    // el estado global y reaparecía al abrir el mapa de otra sede.
    final ruta = NavRoute(
      steps: [
        RouteStep(node: _node('A'), voiceInstruction: 'Sal por A'),
        RouteStep(node: _node('B'), voiceInstruction: 'Llega a B'),
      ],
      totalDistance: 100,
      estimatedMinutes: 1.5,
      fullyAccessible: true,
      origin: _node('A'),
      destination: _node('B'),
    );

    test('clearActiveRoute realmente borra la ruta (no solo la polilínea)',
        () {
      final conRuta = const NavigationState().copyWith(
        status: NavStatus.navigating,
        activeRoute: ruta,
        routeVenueId: 'tec_colima',
        routePolylinePoints: [
          [19.26, -103.72]
        ],
        destinationName: 'Cafetería',
      );
      expect(conRuta.activeRoute, isNotNull);

      final cancelada = conRuta.copyWith(
        status: NavStatus.ready,
        clearActiveRoute: true,
        clearRoutePolyline: true,
        clearDestinationName: true,
      );

      expect(cancelada.activeRoute, isNull);
      expect(cancelada.routeVenueId, isNull);
      expect(cancelada.routePolylinePoints, isNull);
      expect(cancelada.destinationName, isNull);
    });

    test('pasar activeRoute: null sin la bandera no borra nada (regresión)',
        () {
      // Documenta por qué existe `clearActiveRoute`: sin la bandera, `null`
      // es indistinguible de "no tocar este campo".
      final conRuta = const NavigationState().copyWith(activeRoute: ruta);
      final intentoFallido = conRuta.copyWith();
      expect(intentoFallido.activeRoute, isNotNull);
    });
  });

  group('NavigationState: quitar posición manual ("Estoy Aquí")', () {
    // Mismo bug de fondo que clearActiveRoute, pero en currentNode: sin
    // `clearCurrentNode`, "Quitar" en el mapa apagaba `isManualPosition`
    // pero el chip de Inicio ("Edificio R · CAMBIAR") seguía leyendo el
    // `currentNode` viejo, que nunca se limpiaba.
    test('clearCurrentNode realmente borra el nodo fijado', () {
      final conNodo = const NavigationState().copyWith(
        currentNode: _node('EDIFICIO_R'),
        isManualPosition: true,
        manualPositionLabel: 'Edificio R',
      );
      expect(conNodo.currentNode, isNotNull);

      final limpio = conNodo.copyWith(
        isManualPosition: false,
        clearManualPositionLabel: true,
        clearCurrentNode: true,
      );

      expect(limpio.currentNode, isNull);
      expect(limpio.isManualPosition, isFalse);
      expect(limpio.manualPositionLabel, isNull);
    });

    test('pasar currentNode: null sin la bandera no borra nada (regresión)',
        () {
      final conNodo =
          const NavigationState().copyWith(currentNode: _node('EDIFICIO_R'));
      final intentoFallido = conNodo.copyWith();
      expect(intentoFallido.currentNode, isNotNull);
    });
  });
}
