import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sinait/data/models/place_node.dart';
import 'package:sinait/data/repositories/place_repository.dart';
import 'package:geolocator/geolocator.dart';

// 1. Proveedor del Repositorio
final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return PlaceRepository();
});

// 2. StreamProvider que escucha los lugares en tiempo real desde Firebase
final placesStreamProvider = StreamProvider<List<PlaceNode>>((ref) {
  final repository = ref.watch(placeRepositoryProvider);
  return repository.watchPlaces();
});

// 3. StateProvider para manejar el filtro activo ('todo', 'salon', 'cafeteria', etc.)
final categoryFilterProvider = StateProvider<String>((ref) => 'todo');

// 4. Provider de Estado Seleccionado (Mejor Práctica de Clean Architecture)
final selectedPlaceProvider = StateProvider<PlaceNode?>((ref) => null);

// 4.1. Provider de Tema del Mapa (light o dark) - Inicia en modo claro
final mapThemeProvider = StateProvider<String>((ref) => 'light');

// 4.2. Provider de Ubicación Actual Basada en QR (Visión Inteligente)
final currentUserPositionProvider = StateProvider<PlaceNode?>((ref) => null);

// 4.2. StreamProvider de Ubicación GPS en Tiempo Real
final currentLocationStreamProvider = StreamProvider<Position>((ref) {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Notificar cada 5 metros
    ),
  );
});

// 5. Provider derivado que filtra los lugares y los mapea a List<Marker> (para flutter_map)
final filteredMapMarkersProvider = Provider<List<Marker>>((ref) {
  // Escuchamos los lugares y el filtro actual
  final placesAsyncValue = ref.watch(placesStreamProvider);
  final filter = ref.watch(categoryFilterProvider);

  return placesAsyncValue.when(
    data: (places) {
      // Filtrar la lista
      final filteredList = filter.toLowerCase() == 'todo' 
          ? places 
          : places.where((p) => p.type.toLowerCase() == filter.toLowerCase()).toList();
          
      // Mappear a Markers de flutter_map
      return filteredList.map((place) {
        return Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () {
              ref.read(selectedPlaceProvider.notifier).state = place;
            },
            child: Icon(
              Icons.location_on,
              size: 40,
              color: place.accessibilityLevel.toLowerCase() == 'alto' 
                  ? const Color(0xFF64FFDA) 
                  : Colors.deepPurpleAccent,
            ),
          ),
        );
      }).toList();
    },
    loading: () => [],
    error: (error, stackTrace) => [],
  );
});
