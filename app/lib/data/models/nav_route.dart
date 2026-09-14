import 'package:equatable/equatable.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/campus_edge.dart';

/// Un paso individual dentro de una ruta calculada.
class RouteStep extends Equatable {
  /// Nodo actual de este paso.
  final CampusNode node;

  /// Arista que conecta con el siguiente paso (null en el último paso).
  final CampusEdge? edge;

  /// Instrucción de voz para este paso.
  final String voiceInstruction;

  const RouteStep({
    required this.node,
    this.edge,
    required this.voiceInstruction,
  });

  @override
  List<Object?> get props => [node, edge, voiceInstruction];
}

/// Resultado completo de una búsqueda de ruta con Dijkstra.
class NavRoute extends Equatable {
  /// Lista ordenada de pasos desde el origen hasta el destino.
  final List<RouteStep> steps;

  /// Distancia total de la ruta en metros.
  final double totalDistance;

  /// Tiempo estimado en minutos (asumiendo ~1.2 m/s = velocidad peatonal).
  final double estimatedMinutes;

  /// ¿Toda la ruta es accesible?
  final bool fullyAccessible;

  /// Nodo de origen.
  final CampusNode origin;

  /// Nodo de destino.
  final CampusNode destination;

  const NavRoute({
    required this.steps,
    required this.totalDistance,
    required this.estimatedMinutes,
    required this.fullyAccessible,
    required this.origin,
    required this.destination,
  });

  /// Cantidad de pasos en la ruta.
  int get stepCount => steps.length;

  /// Obtiene todos los puntos LatLng (nodos y puntos intermedios) de la ruta.
  List<List<double>> getPolylinePoints() {
    final points = <List<double>>[];
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      points.add([step.node.lat, step.node.lng]);
      if (step.edge?.polylinePoints != null) {
        points.addAll(step.edge!.polylinePoints!);
      }
    }
    return points;
  }

  /// Resumen legible para voz.
  String get voiceSummary {
    final distStr = totalDistance < 100
        ? '${totalDistance.round()} metros'
        : '${(totalDistance / 100).toStringAsFixed(0)} cuadras aproximadamente';
    final timeStr = estimatedMinutes < 1
        ? 'menos de un minuto'
        : '${estimatedMinutes.round()} ${estimatedMinutes.round() == 1 ? 'minuto' : 'minutos'}';

    return 'Ruta de ${origin.name} a ${destination.name}. '
        'Distancia: $distStr. '
        'Tiempo estimado: $timeStr. '
        '${fullyAccessible ? 'La ruta es completamente accesible.' : 'Atención: esta ruta incluye escaleras.'}';
  }

  /// Genera todas las instrucciones de voz en orden.
  List<String> get allVoiceInstructions =>
      steps.map((s) => s.voiceInstruction).toList();

  @override
  List<Object?> get props => [
        steps,
        totalDistance,
        estimatedMinutes,
        fullyAccessible,
        origin,
        destination,
      ];
}
