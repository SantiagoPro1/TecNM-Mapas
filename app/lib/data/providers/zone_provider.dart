import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:sinait/core/constants/app_zone.dart';
import 'package:sinait/core/constants/campus_locations.dart';

// ─── Estado de zona ──────────────────────────────────────────────

/// Estado inmutable del sistema de geofencing.
class ZoneState extends Equatable {
  /// Zona activa detectada por GPS.
  final AppZone currentZone;

  /// Última posición GPS conocida.
  final Position? lastPosition;

  /// Distancia (m) al centro de la zona activa (null si desconocido).
  final double? distanceToCenter;

  /// Error de geolocalización, si existe.
  final String? error;

  const ZoneState({
    this.currentZone = AppZone.desconocido,
    this.lastPosition,
    this.distanceToCenter,
    this.error,
  });

  ZoneState copyWith({
    AppZone? currentZone,
    Position? lastPosition,
    double? distanceToCenter,
    String? error,
  }) {
    return ZoneState(
      currentZone: currentZone ?? this.currentZone,
      lastPosition: lastPosition ?? this.lastPosition,
      distanceToCenter: distanceToCenter ?? this.distanceToCenter,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
        currentZone,
        lastPosition?.latitude,
        lastPosition?.longitude,
        distanceToCenter,
        error,
      ];
}

// ─── StateNotifier ───────────────────────────────────────────────

/// Mapa estático que vincula el índice de [CampusLocations.zonePerimeters]
/// con su [AppZone] correspondiente.
const _indexToZone = <int, AppZone>{
  0: AppZone.escolar,
  1: AppZone.sendera,
  2: AppZone.zentralia,
};

class ZoneNotifier extends StateNotifier<ZoneState> {
  StreamSubscription<Position>? _positionSub;

  ZoneNotifier() : super(const ZoneState()) {
    _startListening();
  }

  // ─── Stream de posición GPS ──────────────────────────────────

  Future<void> _startListening() async {
    // 1 — Verificar servicio de ubicación.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      state = state.copyWith(
        error: 'Servicio de ubicación desactivado.',
      );
      debugPrint('[ZoneNotifier] Servicio de ubicación desactivado.');
      return;
    }

    // 2 — Verificar / solicitar permisos.
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        state = state.copyWith(error: 'Permiso de ubicación denegado.');
        debugPrint('[ZoneNotifier] Permiso denegado.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      state = state.copyWith(
        error: 'Permiso de ubicación denegado permanentemente.',
      );
      debugPrint('[ZoneNotifier] Permiso denegado permanentemente.');
      return;
    }

    // 3 — Obtener posición inicial.
    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      _evaluateZone(initial);
    } catch (e) {
      debugPrint('[ZoneNotifier] Error obteniendo posición inicial: $e');
    }

    // 4 — Suscribirse al stream continuo.
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // metros mínimos para nuevo evento
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _evaluateZone,
      onError: (Object e) {
        debugPrint('[ZoneNotifier] Error en stream de posición: $e');
        state = state.copyWith(error: 'Error de geolocalización: $e');
      },
    );

    debugPrint('[ZoneNotifier] Stream de geofencing iniciado.');
  }

  // ─── Evaluación de zona ──────────────────────────────────────

  /// Calcula la distancia del usuario a cada perímetro y determina
  /// la [AppZone] correspondiente.
  void _evaluateZone(Position position) {
    const perimeters = CampusLocations.zonePerimeters;

    AppZone detected = AppZone.desconocido;
    double? closestDistance;

    for (var i = 0; i < perimeters.length; i++) {
      final (lat, lng, radius) = perimeters[i];

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      if (distance <= radius) {
        // Dentro del radio: si es más cercano que otro match, prevalece.
        if (closestDistance == null || distance < closestDistance) {
          detected = _indexToZone[i] ?? AppZone.desconocido;
          closestDistance = distance;
        }
      }
    }

    // Solo actualizamos si cambió la zona o la posición.
    final zoneChanged = detected != state.currentZone;

    state = state.copyWith(
      currentZone: detected,
      lastPosition: position,
      distanceToCenter: closestDistance,
      error: null,
    );

    if (zoneChanged) {
      debugPrint(
        '[ZoneNotifier] Zona actualizada → ${detected.label} '
        '(distancia al centro: ${closestDistance?.toStringAsFixed(1) ?? "N/A"} m)',
      );
    }
  }

  // ─── Ciclo de vida ───────────────────────────────────────────

  @override
  void dispose() {
    _positionSub?.cancel();
    debugPrint('[ZoneNotifier] Stream de geofencing cancelado.');
    super.dispose();
  }
}

// ─── Providers ───────────────────────────────────────────────────

/// Provider principal del geofencing.
final zoneProvider =
    StateNotifierProvider<ZoneNotifier, ZoneState>((ref) {
  return ZoneNotifier();
});

/// Provider de conveniencia: zona activa.
final currentZoneProvider = Provider<AppZone>((ref) {
  return ref.watch(zoneProvider).currentZone;
});

/// Provider de conveniencia: ¿está el usuario dentro de alguna zona?
final isInsideKnownZoneProvider = Provider<bool>((ref) {
  return ref.watch(zoneProvider).currentZone != AppZone.desconocido;
});
