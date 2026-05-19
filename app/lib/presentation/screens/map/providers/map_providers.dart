import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sinait/data/models/place_node.dart';
import 'package:sinait/data/repositories/place_repository.dart';

// 1. Proveedor del Repositorio
final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return PlaceRepository();
});

// 2. StreamProvider que escucha los lugares en tiempo real desde Firebase
final placesStreamProvider = StreamProvider<List<PlaceNode>>((ref) {
  final repository = ref.watch(placeRepositoryProvider);
  return repository.watchPlaces();
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

// 5. Provider que filtra y retorna PlaceNodes (la conversión a Marker se hace en el mapa)
final filteredPlacesProvider = Provider<List<PlaceNode>>((ref) {
  final placesAsyncValue = ref.watch(placesStreamProvider);
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
