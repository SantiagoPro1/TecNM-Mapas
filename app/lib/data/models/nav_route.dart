import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/services/navigation/route_geometry_smoother.dart';

/// Tipo de maniobra peatonal para instrucciones estilo Google Maps.
enum RouteManeuver {
  depart,
  straight,
  slightRight,
  turnRight,
  sharpRight,
  uTurn,
  slightLeft,
  turnLeft,
  sharpLeft,
  arrive,
}

/// Un paso individual dentro de una ruta calculada.
class RouteStep extends Equatable {
  /// Nodo actual de este paso.
  final CampusNode node;

  /// Arista que conecta con el siguiente paso (null en el último paso).
  final CampusEdge? edge;

  /// Instrucción de voz para este paso.
  final String voiceInstruction;

  /// Tipo de maniobra para iconografía y UI de navegación.
  final RouteManeuver maneuver;

  /// Distancia estimada de este tramo en metros.
  final double distanceMeters;

  /// Título corto de la maniobra (ej: "Gira a la derecha").
  final String title;

  const RouteStep({
    required this.node,
    this.edge,
    required this.voiceInstruction,
    this.maneuver = RouteManeuver.straight,
    this.distanceMeters = 0.0,
    this.title = '',
  });

  /// Ícono visual representativo de la maniobra.
  IconData get maneuverIcon {
    switch (maneuver) {
      case RouteManeuver.depart:
        return Icons.navigation_rounded;
      case RouteManeuver.straight:
        return Icons.straight_rounded;
      case RouteManeuver.slightRight:
        return Icons.turn_slight_right_rounded;
      case RouteManeuver.turnRight:
        return Icons.turn_right_rounded;
      case RouteManeuver.sharpRight:
        return Icons.u_turn_right_rounded;
      case RouteManeuver.slightLeft:
        return Icons.turn_slight_left_rounded;
      case RouteManeuver.turnLeft:
        return Icons.turn_left_rounded;
      case RouteManeuver.sharpLeft:
      case RouteManeuver.uTurn:
        return Icons.u_turn_left_rounded;
      case RouteManeuver.arrive:
        return Icons.place_rounded;
    }
  }

  /// Título legible para mostrar en pantalla.
  String get displayTitle {
    if (title.isNotEmpty) return title;
    switch (maneuver) {
      case RouteManeuver.depart:
        return 'Inicia tu recorrido';
      case RouteManeuver.straight:
        return 'Continúa recto';
      case RouteManeuver.slightRight:
        return 'Gira ligeramente a la derecha';
      case RouteManeuver.turnRight:
        return 'Gira a la derecha';
      case RouteManeuver.sharpRight:
        return 'Gira pronunciadamente a la derecha';
      case RouteManeuver.slightLeft:
        return 'Gira ligeramente a la izquierda';
      case RouteManeuver.turnLeft:
        return 'Gira a la izquierda';
      case RouteManeuver.sharpLeft:
        return 'Gira pronunciadamente a la izquierda';
      case RouteManeuver.uTurn:
        return 'Da vuelta en U';
      case RouteManeuver.arrive:
        return 'Llegada al destino';
    }
  }

  @override
  List<Object?> get props => [
        node,
        edge,
        voiceInstruction,
        maneuver,
        distanceMeters,
        title,
      ];
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

  /// Obtiene todos los puntos LatLng (nodos y curvas intermedias) suavizados estilo Google Maps.
  List<List<double>> getPolylinePoints({
    List<double>? origin,
    List<double>? destination,
  }) {
    return RouteGeometrySmoother.assembleAndSmooth(
      steps,
      origin: origin,
      destination: destination,
    );
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
