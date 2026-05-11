import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

/// Servicio de caché offline para los datos de mapas (nodos + aristas).
///
/// Estrategia:
///  1. Al primer arranque → lee los JSON de assets y los guarda en Hive.
///  2. En arranques posteriores → lee directamente de Hive (offline-first).
///  3. Si los assets se actualizan con una nueva versión de la app,
///     la semilla se re-ejecuta automáticamente (por comparación de versión).
///
/// Los datos se almacenan como JSON crudo en Hive, lo que evita la necesidad
/// de generar TypeAdapters con build_runner y mantiene compatibilidad directa
/// con CampusNode.fromJson / CampusEdge.fromJson.
class MapCacheService {
  MapCacheService._();

  static const String _boxName = 'sinait_map_cache';
  static const String _seedVersionKey = 'seed_version';

  /// Versión de la semilla. Incrementar este valor fuerza una re-siembra
  /// cuando se actualicen los archivos JSON en assets.
  static const int _currentSeedVersion = 1;

  /// Archivos JSON del mapa que sirven como semilla.
  static const List<String> _mapAssetFiles = [
    'assets/maps/tec_colima_map.json',
    'assets/maps/sendera_map.json',
    'assets/maps/zentralia_map.json',
  ];

  /// Inicializa Hive y siembra la caché si es necesario.
  /// Debe llamarse una sola vez en main(), después de WidgetsFlutterBinding.
  static Future<void> initialize() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>(_boxName);

    final cachedVersion = box.get(_seedVersionKey);
    final needsSeed = cachedVersion == null ||
        int.tryParse(cachedVersion) != _currentSeedVersion;

    if (needsSeed) {
      await _seedFromAssets(box);
    }
  }

  /// Lee los JSONs de assets y los persiste en Hive como strings.
  static Future<void> _seedFromAssets(Box<String> box) async {
    for (final file in _mapAssetFiles) {
      try {
        final jsonStr = await rootBundle.loadString(file, cache: false);
        // Validar que el JSON sea parseable antes de guardarlo
        json.decode(jsonStr);
        await box.put(file, jsonStr);
        debugPrint('MapCache: sembrado $file ✓');
      } catch (e) {
        debugPrint('MapCache: error sembrando $file → $e');
      }
    }
    await box.put(_seedVersionKey, _currentSeedVersion.toString());
    debugPrint('MapCache: siembra completada (v$_currentSeedVersion)');
  }

  /// Carga los datos combinados de nodos y aristas desde la caché Hive.
  /// Retorna null si la caché está vacía (no debería pasar tras initialize).
  static Future<Map<String, dynamic>?> loadCachedMapData() async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      final allNodes = <dynamic>[];
      final allEdges = <dynamic>[];

      for (final file in _mapAssetFiles) {
        final jsonStr = box.get(file);
        if (jsonStr == null) continue;

        try {
          final data = json.decode(jsonStr) as Map<String, dynamic>;
          allNodes.addAll(data['nodes'] as List<dynamic>? ?? []);
          allEdges.addAll(data['edges'] as List<dynamic>? ?? []);
        } catch (e) {
          debugPrint('MapCache: JSON corrupto en $file → $e');
          continue;
        }
      }

      if (allNodes.isEmpty) return null;

      return {
        'nodes': allNodes,
        'edges': allEdges,
      };
    } catch (e) {
      debugPrint('MapCache: error leyendo caché → $e');
      return null;
    }
  }

  /// Carga los datos de un mapa específico desde la caché.
  static Future<Map<String, dynamic>?> loadCachedFile(String assetPath) async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      final jsonStr = box.get(assetPath);
      if (jsonStr == null) return null;
      return json.decode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MapCache: error leyendo $assetPath → $e');
      return null;
    }
  }

  /// Actualiza un mapa específico en la caché (para futuras actualizaciones OTA).
  static Future<void> updateCachedFile(
    String assetPath,
    Map<String, dynamic> data,
  ) async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      await box.put(assetPath, json.encode(data));
      debugPrint('MapCache: actualizado $assetPath ✓');
    } catch (e) {
      debugPrint('MapCache: error actualizando $assetPath → $e');
    }
  }

  /// Limpia toda la caché (útil para forzar re-siembra en debug).
  static Future<void> clearCache() async {
    final box = await Hive.openBox<String>(_boxName);
    await box.clear();
    debugPrint('MapCache: caché limpiada');
  }

  /// Indica si la caché tiene datos sembrados.
  static Future<bool> get isCacheReady async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      return box.get(_seedVersionKey) != null;
    } catch (_) {
      return false;
    }
  }
}
