import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/repositories/place_repository.dart';
import 'package:navia/data/repositories/venue_graph_repository.dart';
import 'package:navia/utils/gps_filter.dart';

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

// 2.1. Modo "mapa abierto": el mapa deja de estar anclado a una sede — la
// cámara se puede mover libremente por todo Colima y se muestran los puntos
// de las 9 sedes al mismo tiempo, no solo los de una.
final openMapModeProvider = StateProvider<bool>((ref) => false);

// 2.2. Puntos de TODAS las sedes juntos, para el modo mapa abierto.
//
// Son 9 streams abiertos a la vez (uno por sede) en vez de 1, así que esto
// solo debe consumirse mientras el mapa abierto está en pantalla: los
// `placesStreamProvider` son `.autoDispose`, así que al salir se cierran
// solos y se vuelve a un único listener.
final allVenuesPlacesProvider = Provider<List<PlaceNode>>((ref) {
  final todos = <PlaceNode>[];
  for (final venue in VenueRegistry.all) {
    todos.addAll(ref.watch(placesStreamProvider(venue.id)).value ?? const []);
  }
  return todos;
});

// 3. StateProvider para manejar el filtro activo
final categoryFilterProvider = StateProvider<String>((ref) => 'todo');

// 4. Provider de Lugar Seleccionado
final selectedPlaceProvider = StateProvider<PlaceNode?>((ref) => null);

// 4.1. Provider de Tema del Mapa (light o dark)
final mapThemeProvider = StateProvider<String>((ref) => 'light');

// 4.2. Provider de Ubicación Actual Basada en QR
final currentUserPositionProvider = StateProvider<PlaceNode?>((ref) => null);

// 4.3. StreamProvider de Ubicación GPS en Tiempo Real.
//
// IMPORTANTE — bug histórico ya corregido: antes se usaba
// `timeLimit: Duration(seconds: 10)` en `LocationSettings`. Para un stream
// continuo (a diferencia de una petición puntual), ese parámetro NO es un
// timeout por lectura: el propio paquete geolocator lo documenta como "lanza
// TimeoutException si no llega ninguna ubicación en ese lapso". Como
// `distanceFilter: 2` hace que el sistema operativo solo emita una lectura
// cuando el usuario se movió >= 2m, bastaba con que alguien se detuviera
// más de 10s (leyendo una señal, esperando, dentro de un edificio con mala
// señal) para que el stream completo terminara en error — y como el código
// que lo consume (`ref.listen` + `whenData`) ignora los errores en
// silencio, el GPS se quedaba "congelado" para siempre hasta que el usuario
// tocara manualmente el botón de centrar (que es lo único que invalida y
// recrea este provider). Esto también explica por qué la llegada al
// destino a veces no se detectaba: justo al acercarse, la gente camina más
// lento o se detiene, que es exactamente cuando el stream podía morir.
//
// Ahora el stream nunca se cierra solo: se envuelve en un generador que
// reintenta automáticamente ante cualquier error (timeout, GPS
// desactivado momentáneamente, etc.), y además pasa cada lectura cruda por
// [GpsFilter] para suavizar el ruido típico de GPS urbano/de campus
// (rebotes entre edificios) antes de que le llegue a la UI.
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

  return _resilientFilteredPositionStream();
});

/// Stream de posición que nunca se apaga solo: si el stream nativo de
/// Geolocator termina (por el error que sea), espera un momento y vuelve a
/// suscribirse, en vez de dejar al proveedor en un estado de error
/// permanente. Cada lectura cruda pasa por un [GpsFilter] propio de esta
/// suscripción (se reinicia en cada reintento, para no arrastrar una
/// estimación vieja tras un corte largo de señal).
Stream<Position> _resilientFilteredPositionStream() async* {
  while (true) {
    final filter = GpsFilter();
    try {
      await for (final raw in Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      )) {
        final smoothed = filter.filter(raw);
        if (smoothed == null) continue; // lectura descartada (ruido/salto)
        yield Position(
          latitude: smoothed.latitude,
          longitude: smoothed.longitude,
          timestamp: raw.timestamp,
          accuracy: raw.accuracy,
          altitude: raw.altitude,
          altitudeAccuracy: raw.altitudeAccuracy,
          heading: raw.heading,
          headingAccuracy: raw.headingAccuracy,
          speed: raw.speed,
          speedAccuracy: raw.speedAccuracy,
          floor: raw.floor,
          isMocked: raw.isMocked,
        );
      }
      // El stream nativo terminó sin lanzar (no debería pasar, pero por si
      // acaso): tratarlo igual que un error y reintentar.
      debugPrint('GPS: el stream de posición terminó solo; reintentando.');
    } catch (e) {
      debugPrint('GPS: stream de posición interrumpido ($e); reintentando.');
    }
    await Future.delayed(const Duration(seconds: 2));
  }
}

// 5. Provider que filtra y retorna PlaceNodes de la sede actual (la conversión
// a Marker se hace en el mapa)
final filteredPlacesProvider = Provider<List<PlaceNode>>((ref) {
  final filter = ref.watch(categoryFilterProvider);

  final List<PlaceNode> places;
  if (ref.watch(openMapModeProvider)) {
    places = ref.watch(allVenuesPlacesProvider);
  } else {
    final zoneId = ref.watch(currentVenueIdProvider);
    places = ref.watch(placesStreamProvider(zoneId)).value ?? const [];
  }

  if (filter.toLowerCase() == 'todo') return places;
  return places
      .where((p) => p.type.toLowerCase() == filter.toLowerCase())
      .toList();
});
