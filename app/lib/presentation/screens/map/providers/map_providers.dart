import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/repositories/place_repository.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/utils/svg_marker_helper.dart';
import 'package:navia/presentation/widgets/custom_map_marker.dart';
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
//
// Configuración optimizada por plataforma para máxima frecuencia (~2 Hz):
//  • Android: AndroidSettings con foreground notification e intervalDuration 500ms.
//  • iOS: AppleSettings con activityType fitness y pauseLocationUpdatesAutomatically: false.
//  • Desktop: Polling cada 2s (Geolocator plugin tiene limitaciones en desktop).
//
// distanceFilter = 0 para recibir TODAS las lecturas. El filtro Kalman en
// GpsFilter se encarga de suavizar el ruido y rechazar outliers.
// Esto permite actualizaciones incluso cuando el usuario está quieto,
// mejorando la estabilidad del marcador y la detección de movimiento.
final currentLocationStreamProvider = StreamProvider<Position>((ref) {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Desktop: polling periódico (el stream nativo tiene bugs en desktop)
    return Stream.periodic(const Duration(seconds: 2)).asyncMap((_) async {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 2),
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

  // Mobile: configuración de máxima precisión y frecuencia
  if (Platform.isAndroid) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // Recibir TODAS las lecturas — el Kalman filtra
        intervalDuration: const Duration(milliseconds: 500), // ~2 Hz
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'NAVIA Navegación',
          notificationText: 'Rastreando ubicación para navegación en campus.',
          enableWakeLock: true,
        ),
      ),
    );
  }

  // iOS
  if (Platform.isIOS) {
    return Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // Recibir TODAS las lecturas — el Kalman filtra
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      ),
    );
  }

  // Fallback genérico
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      timeLimit: Duration(seconds: 3),
    ),
  );
});

// 5. Provider derivado que filtra los lugares y los mapea a List<Marker> (para flutter_map)
//    Ahora usa CustomMapMarker con iconos SVG vectoriales escalables.
//    Los colores se derivan reactivamente del ThemeData activo.
final filteredMapMarkersProvider = Provider<List<Marker>>((ref) {
  // Escuchamos los lugares, el filtro actual y el tema activo
  final placesAsyncValue = ref.watch(placesStreamProvider);
  final filter = ref.watch(categoryFilterProvider);
  final currentTheme = ref.watch(themeProvider);

  // Colores derivados del tema activo
  final softAccent = currentTheme.colorScheme.primary;
  final softBackground = currentTheme.colorScheme.surface;

  return placesAsyncValue.when(
    data: (places) {
      // Filtrar la lista
      final filteredList = filter.toLowerCase() == 'todo'
          ? places
          : places
              .where((p) => p.type.toLowerCase() == filter.toLowerCase())
              .toList();

      // Mappear a Markers de flutter_map usando CustomMapMarker + SVG
      return filteredList.map((place) {
        final isBuilding = place.type.toLowerCase() == 'edificio';

        // Extraer la letra del ID (priorizando el campo 'letter' si existe)
        String buildingLetter = place.letter ?? '';
        if (buildingLetter.isEmpty) {
          if (isBuilding && place.id.startsWith('edificio_')) {
            buildingLetter = place.id.split('_').last.toUpperCase();
          } else if (place.id == 'cecum') {
            buildingLetter = 'C';
          } else if (place.id == 'activididades_extraescolares') {
            buildingLetter = 'Ñ';
          }
        }

        // Resolver el icono SVG apropiado para este POI
        final svgAsset = SvgMarkerHelper.svgAssetForPoi(
          id: place.id,
          type: place.type,
          name: place.name,
        );

        return Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 45,
          height: 45,
          child: CustomMapMarker(
            svgAsset: svgAsset,
            semanticLabel: '${place.name}, ${place.type}',
            iconColor: softAccent,
            backgroundColor: softBackground,
            borderColor: softAccent,
            buildingLetter: buildingLetter.isNotEmpty ? buildingLetter : null,
            onTap: () {
              ref.read(selectedPlaceProvider.notifier).state = place;
            },
          ),
        );
      }).toList();
    },
    loading: () => [],
    error: (error, stackTrace) => [],
  );
});
