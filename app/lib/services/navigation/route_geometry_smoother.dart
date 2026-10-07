import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:navia/data/models/nav_route.dart';

/// Utilidad para ensamblar y suavizar la geometría de rutas peatonales con
/// estilo Google Maps (curvas fluidas, andadores exactos y redondeo de esquinas).
class RouteGeometrySmoother {
  RouteGeometrySmoother._();

  /// Distancia en metros entre dos coordenadas (fórmula Haversine).
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0; // Radio de la Tierra en metros
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(math.max(0.0, 1.0 - a)));
    return r * c;
  }

  /// Ensambla la secuencia continua de coordenadas de una ruta asegurando
  /// la orientación correcta de cada arista y eliminando duplicados.
  static List<List<double>> assembleRawRoutePoints(
    List<RouteStep> steps, {
    List<double>? origin,
    List<double>? destination,
  }) {
    if (steps.isEmpty) {
      final res = <List<double>>[];
      if (origin != null) res.add(origin);
      if (destination != null) res.add(destination);
      return res;
    }

    final raw = <List<double>>[];

    // 1. Origen manual si se proporcionó y está desfasado del primer nodo
    if (origin != null && origin.length >= 2) {
      raw.add([origin[0], origin[1]]);
    }

    for (int i = 0; i < steps.length; i++) {
      final currentStep = steps[i];
      final nodeCoords = [currentStep.node.lat, currentStep.node.lng];

      // Agregar nodo si es el primero o si está a distancia apreciable del último punto
      if (raw.isEmpty ||
          distanceMeters(
                raw.last[0],
                raw.last[1],
                nodeCoords[0],
                nodeCoords[1],
              ) >=
              0.4) {
        raw.add(nodeCoords);
      }

      // Si este paso tiene arista hacia el siguiente nodo
      final edge = currentStep.edge;
      if (edge != null &&
          edge.polylinePoints != null &&
          edge.polylinePoints!.isNotEmpty) {
        final pts = edge.polylinePoints!;

        // Determinar orientación: ¿los puntos van de este nodo al siguiente o al revés?
        final nextNodeCoords = (i + 1 < steps.length)
            ? [steps[i + 1].node.lat, steps[i + 1].node.lng]
            : null;

        List<List<double>> orientedPoints;
        if (pts.length >= 2 && nextNodeCoords != null) {
          final firstToNode = distanceMeters(
            pts.first[0],
            pts.first[1],
            nodeCoords[0],
            nodeCoords[1],
          );
          final lastToNode = distanceMeters(
            pts.last[0],
            pts.last[1],
            nodeCoords[0],
            nodeCoords[1],
          );

          if (firstToNode > lastToNode) {
            // El primer punto está más lejos del nodo actual que el último:
            // la lista de puntos está en sentido inverso
            orientedPoints = pts.reversed.toList();
          } else {
            orientedPoints = List.from(pts);
          }
        } else {
          orientedPoints = List.from(pts);
        }

        // Agregar los puntos intermedios evitando duplicar extremos
        for (final p in orientedPoints) {
          if (raw.isEmpty ||
              distanceMeters(raw.last[0], raw.last[1], p[0], p[1]) >= 0.4) {
            raw.add([p[0], p[1]]);
          }
        }
      }
    }

    // 2. Destino manual si se proporcionó
    if (destination != null && destination.length >= 2) {
      if (raw.isEmpty ||
          distanceMeters(
                raw.last[0],
                raw.last[1],
                destination[0],
                destination[1],
              ) >=
              0.4) {
        raw.add([destination[0], destination[1]]);
      }
    }

    return raw;
  }

  /// Aplica redondeo de esquinas y suavizado de curvas estilo Google Maps
  /// mediante curvas de Bézier cuadráticas en cada quiebre o andador.
  static List<List<double>> smoothGoogleCurves(
    List<List<double>> points, {
    double maxFilletRadiusMeters = 5.0,
    int stepsPerCorner = 5,
  }) {
    if (points.length <= 2) return points;

    // 1. Filtrar puntos redundantes o con micro-distancia (< 0.4 metros)
    final cleaned = <List<double>>[points.first];
    for (int i = 1; i < points.length; i++) {
      final prev = cleaned.last;
      final curr = points[i];
      if (distanceMeters(prev[0], prev[1], curr[0], curr[1]) >= 0.4) {
        cleaned.add(curr);
      }
    }

    if (cleaned.length <= 2) return cleaned;

    final result = <List<double>>[cleaned.first];

    // 2. Iterar sobre cada vértice intermedio para redondear la esquina
    for (int i = 1; i < cleaned.length - 1; i++) {
      final p0 = cleaned[i - 1];
      final p1 = cleaned[i];
      final p2 = cleaned[i + 1];

      final d1 = distanceMeters(p0[0], p0[1], p1[0], p1[1]);
      final d2 = distanceMeters(p1[0], p1[1], p2[0], p2[1]);

      // Radio de redondeo: máximo 38% del segmento adyacente más corto
      final r = math.min(
        maxFilletRadiusMeters,
        math.min(d1 * 0.38, d2 * 0.38),
      );

      // Calcular el ángulo entre los vectores entrante y saliente
      final v1Lat = p1[0] - p0[0];
      final v1Lng = p1[1] - p0[1];
      final v2Lat = p2[0] - p1[0];
      final v2Lng = p2[1] - p1[1];

      final dot = v1Lat * v2Lat + v1Lng * v2Lng;
      final mag1 = math.sqrt(v1Lat * v1Lat + v1Lng * v1Lng);
      final mag2 = math.sqrt(v2Lat * v2Lat + v2Lng * v2Lng);

      if (mag1 == 0 || mag2 == 0) {
        result.add(p1);
        continue;
      }

      final cosAngle = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
      final angleDeg = math.acos(cosAngle) * 180.0 / math.pi;

      // Si el ángulo es casi recto o un quiebre notable (> 12° y < 165°) y r >= 0.8m
      if (angleDeg > 12.0 && angleDeg < 165.0 && r >= 0.8) {
        // Punto tangente de corte Q0 antes del vértice P1
        final t1 = 1.0 - (r / d1);
        final q0 = [
          p0[0] + (p1[0] - p0[0]) * t1,
          p0[1] + (p1[1] - p0[1]) * t1,
        ];

        // Punto tangente de corte Q1 después del vértice P1
        final t2 = r / d2;
        final q1 = [
          p1[0] + (p2[0] - p1[0]) * t2,
          p1[1] + (p2[1] - p1[1]) * t2,
        ];

        // Añadir Q0
        if (distanceMeters(result.last[0], result.last[1], q0[0], q0[1]) >= 0.3) {
          result.add(q0);
        }

        // Interpolar curva Bézier cuadrática entre Q0 y Q1 usando P1 como punto de control
        for (int step = 1; step < stepsPerCorner; step++) {
          final u = step / stepsPerCorner;
          final oneMinusU = 1.0 - u;
          final lat = oneMinusU * oneMinusU * q0[0] +
              2 * oneMinusU * u * p1[0] +
              u * u * q1[0];
          final lng = oneMinusU * oneMinusU * q0[1] +
              2 * oneMinusU * u * p1[1] +
              u * u * q1[1];

          if (distanceMeters(result.last[0], result.last[1], lat, lng) >= 0.3) {
            result.add([lat, lng]);
          }
        }

        // Añadir Q1
        if (distanceMeters(result.last[0], result.last[1], q1[0], q1[1]) >= 0.3) {
          result.add(q1);
        }
      } else {
        // Línea recta o giro extremo: conservar el vértice
        if (distanceMeters(result.last[0], result.last[1], p1[0], p1[1]) >= 0.3) {
          result.add(p1);
        }
      }
    }

    // 3. Añadir el último punto
    if (distanceMeters(
          result.last[0],
          result.last[1],
          cleaned.last[0],
          cleaned.last[1],
        ) >=
        0.3) {
      result.add(cleaned.last);
    }

    return result;
  }

  /// Ensambla los pasos y aplica el suavizado completo de curvas.
  static List<List<double>> assembleAndSmooth(
    List<RouteStep> steps, {
    List<double>? origin,
    List<double>? destination,
    double maxFilletRadiusMeters = 5.0,
  }) {
    final raw = assembleRawRoutePoints(
      steps,
      origin: origin,
      destination: destination,
    );
    return smoothGoogleCurves(
      raw,
      maxFilletRadiusMeters: maxFilletRadiusMeters,
    );
  }

  /// Suaviza una lista de LatLng directa de Google Maps.
  static List<gmaps.LatLng> smoothLatLngs(
    List<gmaps.LatLng> points, {
    double maxFilletRadiusMeters = 5.0,
  }) {
    if (points.length <= 2) return points;
    final asList = points.map((p) => [p.latitude, p.longitude]).toList();
    final smoothed = smoothGoogleCurves(
      asList,
      maxFilletRadiusMeters: maxFilletRadiusMeters,
    );
    return smoothed.map((p) => gmaps.LatLng(p[0], p[1])).toList();
  }
}
