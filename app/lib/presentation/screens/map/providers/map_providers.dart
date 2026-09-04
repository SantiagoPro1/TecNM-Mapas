import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/repositories/place_repository.dart';
import 'package:navia/data/repositories/venue_graph_repository.dart';

// 1. Proveedor del Repositorio
final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return PlaceRepository();
});

// 1.05. Repositorio del grafo caminable (nodos/aristas) — usado por el editor
// de administrador para construir el grafo de las sedes sin JSON empaquetado.
final venueGraphRepositoryProvider = Provider<VenueGraphRepository>((ref) {
  return VenueGraphRepository();
});

// 1.06. Nodos/aristas del grafo en tiempo real, una sede a la vez. Solo el
// editor de administrador los consume — la navegación normal usa el grafo
// cacheado vía CampusGraph/NavigationService, no estos streams.
final nodesStreamProvider =
    StreamProvider.autoDispose.family<List<CampusNode>, String>((ref, zoneId) {
  return ref.watch(venueGraphRepositoryProvider).watchNodes(zoneId);
});

final edgesStreamProvider =
    StreamProvider.autoDispose.family<List<CampusEdge>, String>((ref, zoneId) {
  return ref.watch(venueGraphRepositoryProvider).watchEdges(zoneId);
});

// 1.1. Sede actualmente mostrada en el mapa. `map_screen.dart` la fija al
// resolver `arguments['venueId']` desde la navegación.
final currentVenueIdProvider =
    StateProvider<String>((ref) => VenueRegistry.tecColima.id);

// 2. StreamProvider que escucha los lugares en tiempo real desde Firebase,
// una sede a la vez. `.autoDispose` para que un cliente no acumule listeners
// de sedes que ya no está viendo.
final placesStreamProvider =
    StreamProvider.autoDispose.family<List<PlaceNode>, String>((ref, zoneId) {
  final repository = ref.watch(placeRepositoryProvider);
  return repository.watchPlaces(zoneId);
});

// 3. StateProvider para manejar el filtro activo
final categoryFilterProvider = StateProvider<String>((ref) => 'todo');

// 4. Provider de Lugar Seleccionado
final selectedPlaceProvider = StateProvider<PlaceNode?>((ref) => null);

// 4.1. Provider de Tema del Mapa (light o dark)
final mapThemeProvider = StateProvider<String>((ref) => 'light');

// 4.2. Provider de Ubicación Actual Basada en QR
final currentUserPositionProvider = StateProvider<PlaceNode?>((ref) => null);

// 4.3. StreamProvider de Ubicación GPS en Tiempo Real
final currentLocationStreamProvider = StreamProvider<Position>((ref) {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return Stream.periodic(const Duration(seconds: 4)).asyncMap((_) async {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 3),
        );
      } catch (e) {
        final last = await Geolocator.getLastKnownPosition();
        return last ??
            Position(
              latitude: 19.266,
              longitude: -103.71,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            );
      }
    });
  }

  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
      timeLimit: Duration(seconds: 10),
    ),
  );
});

// 5. Provider que filtra y retorna PlaceNodes de la sede actual (la conversión
// a Marker se hace en el mapa)
final filteredPlacesProvider = Provider<List<PlaceNode>>((ref) {
  final zoneId = ref.watch(currentVenueIdProvider);
  final placesAsyncValue = ref.watch(placesStreamProvider(zoneId));
  final filter = ref.watch(categoryFilterProvider);

  return placesAsyncValue.when(
    data: (places) {
      if (filter.toLowerCase() == 'todo') return places;
      return places
          .where((p) => p.type.toLowerCase() == filter.toLowerCase())
          .toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
