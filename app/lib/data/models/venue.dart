import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Representa una sede/zona navegable dentro de NAVIA (un campus, plaza
/// comercial, o sede deportiva).
///
/// Sustituye las listas de mapas hardcodeadas que antes vivían repetidas en
/// `campus_graph.dart`, `map_cache_service.dart`, `place_repository.dart` y
/// `home_screen.dart`.
class Venue extends Equatable {
  final String id;
  final String label;
  final String shortDescription;

  /// Ruta del asset JSON con el grafo caminable, si esta sede viene
  /// empaquetada con la app. Si es `null`, el grafo se lee en línea desde
  /// Firestore (`venues/{id}/nodes`, `venues/{id}/edges`).
  final String? mapAssetPath;

  final double centerLat;
  final double centerLng;

  final double boundsSouthLat;
  final double boundsWestLng;
  final double boundsNorthLat;
  final double boundsEastLng;

  final double defaultZoom;
  final IconData icon;

  const Venue({
    required this.id,
    required this.label,
    required this.shortDescription,
    this.mapAssetPath,
    required this.centerLat,
    required this.centerLng,
    required this.boundsSouthLat,
    required this.boundsWestLng,
    required this.boundsNorthLat,
    required this.boundsEastLng,
    required this.defaultZoom,
    required this.icon,
  });

  /// `true` si el grafo/mapa de esta sede viene empaquetado con la app
  /// (assets/maps/*.json). `false` si se administra en línea vía Firestore.
  bool get isBundled => mapAssetPath != null;

  @override
  List<Object?> get props => [id];
}
