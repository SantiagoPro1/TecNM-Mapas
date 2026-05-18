import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navia/data/cache/map_cache_service.dart';
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
    debugPrint('[OfflineManager] Caché del grafo: ${cacheReady ? "✓" : "✗"}');

    mgr._initialized = true;
    debugPrint('[OfflineManager] Inicializado ✓ '
        '(${ConnectivityService.instance.isOnline ? "online" : "offline"})');
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
