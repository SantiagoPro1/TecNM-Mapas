import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sinait/data/models/place_node.dart';
import 'package:sinait/data/repositories/place_repository.dart';
import 'package:sinait/core/theme/app_theme.dart';
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
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // En Windows el getPositionStream tiene un bug con los hilos.
    // Usamos getCurrentPosition periódicamente para obtener la ubicación real.
    return Stream.periodic(const Duration(seconds: 3)).asyncMap((_) async {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    });
  }

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
        final isBuilding = place.type.toLowerCase() == 'edificio';
        final isCafe = place.type.toLowerCase() == 'cafetería';
        
        // Color suave basado en el nuevo tema
        // Usar colores del tema para mayor suavidad y consistencia
        const softAccent = AppTheme.accent;
        const softBackground = AppTheme.surface;

        // Extraer la letra del ID (ej. edificio_a -> A)
        String buildingLetter = '';
        if (isBuilding && place.id.startsWith('edificio_')) {
          buildingLetter = place.id.split('_').last.toUpperCase();
        } else if (place.id == 'cecum') {
          buildingLetter = 'C';
        }

        return Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 45,
          height: 45,
          child: GestureDetector(
            onTap: () {
              ref.read(selectedPlaceProvider.notifier).state = place;
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Shadow / Glow Suave
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: softAccent.withOpacity(0.15),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                // Main Marker Circle
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: softBackground,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: softAccent.withOpacity(0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: isBuilding && buildingLetter.isNotEmpty
                        ? Text(
                            buildingLetter,
                            style: const TextStyle(
                              color: softAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Icon(
                            isCafe ? Icons.coffee_rounded : Icons.location_on_rounded,
                            size: 16,
                            color: softAccent,
                          ),
                  ),
                ),
                // Pequeño indicador debajo
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: softAccent.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList();
    },
    loading: () => [],
    error: (error, stackTrace) => [],
  );
});
