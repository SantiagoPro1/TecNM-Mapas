import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navia/data/cache/map_cache_service.dart';
import 'package:navia/data/repositories/place_repository.dart';
import 'package:navia/services/offline/connectivity_service.dart';

/// Orquestador central del modo offline de NAVIA.
///
/// Responsabilidades:
///  1. **Monitoreo de conectividad**: delega a [ConnectivityService].
///  2. **Persistencia de última posición GPS**: guarda lat/lng en
///     SharedPreferences para centrar el mapa instantáneamente al abrir.
///  3. **Verificación de readiness offline**: confirma que todos los datos
///     necesarios (caché del grafo, assets, modelos) están disponibles.
///  4. **Caché de tiles**: gestiona la política de caché del TileLayer.
///
/// Flujo de inicialización (en main.dart):
///  ```dart
///  await OfflineManager.initialize();
///  ```
class OfflineManager {
  OfflineManager._();

  static final OfflineManager _instance = OfflineManager._();
  static OfflineManager get instance => _instance;

  // ── SharedPreferences Keys ──────────────────────────────────────
  static const String _kLastLat = 'offline_last_lat';
  static const String _kLastLng = 'offline_last_lng';
  static const String _kLastZoom = 'offline_last_zoom';

  bool _initialized = false;

  /// `true` si OfflineManager ya completó su inicialización.
  bool get isInitialized => _initialized;

  /// Inicializa el sistema offline completo.
  /// Debe llamarse en main() después de MapCacheService.initialize().
  static Future<void> initialize() async {
    final mgr = _instance;
    if (mgr._initialized) return;

    // 1. Iniciar monitoreo de conectividad
    await ConnectivityService.instance.initialize();

    // 2. Verificar que la caché del grafo está lista
    final cacheReady = await MapCacheService.isCacheReady;
    debugPrint('[OfflineManager] Caché del grafo: ${cacheReady ? "lista" : "no disponible"}');

    mgr._initialized = true;
    debugPrint('[OfflineManager] Inicializado '
        '(${ConnectivityService.instance.isOnline ? "online" : "offline"})');

    // 3. Calentar la caché de Firestore con las 9 sedes, SIN bloquear el
    //    arranque: solo el TecNM Colima viene empaquetado en assets, las 8
    //    sedes del evento viven en Firestore y sin esto no existen offline.
    unawaited(prefetchVenueDataForOffline());
  }

  /// Descarga una vez los POIs y el grafo de todas las sedes para que queden
  /// en la caché local de Firestore y la app funcione sin señal.
  ///
  /// Es seguro llamarla sin conexión: `get()` cae a la caché local en vez de
  /// fallar, y cualquier error se registra sin interrumpir nada.
  /// Cada cuánto vale la pena volver a bajar los datos de las 9 sedes.
  ///
  /// Sin este límite la precarga se hacía en CADA arranque, y `get()` sin
  /// `Source` va al servidor aunque el dato ya esté en la caché local: son
  /// ~277 lecturas facturadas por arranque y por persona. Con 40,000
  /// asistentes abriendo la app varias veces al día eso son millones de
  /// lecturas diarias que no aportan nada, porque los puntos de las sedes
  /// casi no cambian una vez montado el evento.
  ///
  /// 12 h es el punto medio: si un administrador mueve un punto, a la
  /// gente le llega ese mismo día — y además `watchPlaces` es un listener en
  /// vivo, así que quien tenga abierta la sede editada lo ve al instante.
  static const Duration _vigenciaPrecarga = Duration(hours: 12);
  static const String _kUltimaPrecarga = 'offline_ultima_precarga_ms';

  static Future<void> prefetchVenueDataForOffline({bool forzar = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ultima = prefs.getInt(_kUltimaPrecarga);
      if (!forzar && ultima != null) {
        final edad = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(ultima));
        if (edad < _vigenciaPrecarga) {
          debugPrint('[OfflineManager] Precarga vigente (hace ${edad.inHours} h);'
              ' se sirve desde la caché local.');
          return;
        }
      }

      // Solo los puntos. El grafo (nodos + aristas, ~6,500 documentos entre
      // las 9 sedes) NO se precarga: las rutas se calculan con el grafo del
      // APK (`CampusGraph.load`), así que bajarlo solo costaba lecturas —
      // ~264 millones cada 12 h con 40,000 asistentes tras una edición.
      await PlaceRepository().prefetchAllVenuesForOffline();
      await prefs.setInt(
          _kUltimaPrecarga, DateTime.now().millisecondsSinceEpoch);
      debugPrint('[OfflineManager] Sedes precargadas para offline');
    } catch (e) {
      debugPrint('[OfflineManager] Precarga de sedes incompleta: $e');
    }
  }

  // ── Última posición GPS conocida ────────────────────────────────

  /// Guarda la última posición GPS válida para uso offline.
  /// Debe llamarse cada vez que se recibe una posición filtrada válida.
  static Future<void> saveLastPosition({
    required double latitude,
    required double longitude,
    double zoom = 17.5,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setDouble(_kLastLat, latitude),
        prefs.setDouble(_kLastLng, longitude),
        prefs.setDouble(_kLastZoom, zoom),
      ]);
    } catch (e) {
      debugPrint('[OfflineManager] Error guardando posición: $e');
    }
  }

  /// Recupera la última posición GPS guardada.
  /// Retorna null si no hay posición almacenada.
  static Future<({double lat, double lng, double zoom})?>
      loadLastPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_kLastLat);
      final lng = prefs.getDouble(_kLastLng);
      final zoom = prefs.getDouble(_kLastZoom) ?? 17.5;

      if (lat == null || lng == null) return null;

      return (lat: lat, lng: lng, zoom: zoom);
    } catch (e) {
      debugPrint('[OfflineManager] Error leyendo posición: $e');
      return null;
    }
  }

  // ── Diagnóstico de readiness offline ────────────────────────────

  /// Verifica que todos los recursos necesarios para modo offline
  /// están disponibles. Retorna un mapa con el estado de cada recurso.
  static Future<Map<String, bool>> checkOfflineReadiness() async {
    final results = <String, bool>{};

    // 1. Caché del grafo del campus
    results['graph_cache'] = await MapCacheService.isCacheReady;

    // 2. Última posición GPS guardada
    final lastPos = await loadLastPosition();
    results['last_position'] = lastPos != null;

    // 3. Conectividad actual
    results['connectivity'] = ConnectivityService.instance.isOnline;

    debugPrint('[OfflineManager] Readiness: $results');
    return results;
  }
}
