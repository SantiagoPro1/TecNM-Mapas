import 'package:flutter_test/flutter_test.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/services/navigation/route_geometry_smoother.dart';

void main() {
  group('RouteGeometrySmoother Tests', () {
    test('Calcula distancia Haversine correctamente', () {
      final d = RouteGeometrySmoother.distanceMeters(
        19.26186, -103.72368,
        19.26192, -103.72368,
      );
      expect(d, greaterThan(5.0));
      expect(d, lessThan(10.0));
    });

    test('Suaviza giros de 90 grados con curvas de Bézier', () {
      // Un recorrido de 3 puntos formando una L (giro a la derecha)
      final raw = [
        [19.26186, -103.72368],
        [19.26286, -103.72368], // Esquina a ~110m
        [19.26286, -103.72268], // Destino a ~105m
      ];

      final smoothed = RouteGeometrySmoother.smoothGoogleCurves(raw);

      // Debe haber generado puntos de curva intermedios en la esquina
      expect(smoothed.length, greaterThan(raw.length));
      expect(smoothed.first, equals(raw.first));
      expect(smoothed.last, equals(raw.last));
    });

    test('Ensambla y orienta correctamente los puntos intermedios de aristas', () {
      const nodeA = CampusNode(
        id: 'node_a',
        name: 'Nodo A',
        zoneId: 'tec_colima',
        aliases: [],
        type: NodeType.corridor,
        floor: 0,
        accessible: true,
        description: '',
        lat: 19.2610,
        lng: -103.7210,
      );
      const nodeB = CampusNode(
        id: 'node_b',
        name: 'Nodo B',
        zoneId: 'tec_colima',
        aliases: [],
        type: NodeType.corridor,
        floor: 0,
        accessible: true,
        description: '',
        lat: 19.2620,
        lng: -103.7210,
      );

      const edge = CampusEdge(
        zoneId: 'tec_colima',
        from: 'node_a',
        to: 'node_b',
        distance: 111.0,
        accessible: true,
        direction: 'Recto',
        polylinePoints: [
          [19.2610, -103.7210],
          [19.2615, -103.7210],
          [19.2620, -103.7210],
        ],
      );

      final steps = [
        const RouteStep(node: nodeA, edge: edge, voiceInstruction: 'Inicia en A'),
        const RouteStep(node: nodeB, edge: null, voiceInstruction: 'Llegada a B'),
      ];

      final assembled = RouteGeometrySmoother.assembleRawRoutePoints(steps);
      expect(assembled.length, equals(3));
      expect(assembled.first[0], closeTo(19.2610, 0.0001));
      expect(assembled[1][0], closeTo(19.2615, 0.0001));
      expect(assembled.last[0], closeTo(19.2620, 0.0001));
    });
  });
}
