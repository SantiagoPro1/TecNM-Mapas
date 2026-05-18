import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Servicio encargado de gestionar, localizar y cargar modelos TFLite.
///
/// Soporta resolucion de modelos incluidos en el empaquetado (assets)
/// o descargados dinamicamente en el almacenamiento del dispositivo
/// (utilizando `path_provider` para evitar inflar el tamanio de la app).
class ModelManagerService {
  /// Cache de interpreters ya cargados para evitar cargas duplicadas.
  final Map<String, Interpreter> _cache = {};

  /// Intenta cargar y devolver un interprete TFLite para el modelo solicitado.
  ///
  /// El flujo de busqueda es:
  /// 1. Cache en memoria (si ya se cargo previamente).
  /// 2. Verifica la existencia del archivo en `assets/models/`.
  /// 3. Si no existe, busca en `getApplicationDocumentsDirectory()/models/`.
  /// 4. Si no existe localmente, lo descarga desde Firebase Storage.
  ///
  /// Retorna un [Interpreter] listo para usarse o `null` si no se encontro.
  Future<Interpreter?> loadModel(String modelFileName) async {
    // 0. Revisar cache en memoria
    if (_cache.containsKey(modelFileName)) {
      debugPrint('ModelManagerService: "$modelFileName" en cache de memoria.');
      return _cache[modelFileName];
    }

    // 1. Verificar existencia en assets integrados.
    try {
      await rootBundle.load('assets/models/$modelFileName');
      debugPrint('ModelManagerService: "$modelFileName" encontrado en assets.');

      final interpreter = await Interpreter.fromAsset(
        'assets/models/$modelFileName',
        options: _buildOptions(),
      );
      _cache[modelFileName] = interpreter;
      return interpreter;
    } catch (_) {
      debugPrint(
        'ModelManagerService: "$modelFileName" no esta en assets. '
        'Buscando en almacenamiento dinamico...',
      );
    }

    // 2. Verificar existencia en el dispositivo (descarga dinamica).
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${appDir.path}/models');

      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final localPath = '${modelsDir.path}/$modelFileName';
      final file = File(localPath);

      if (await file.exists()) {
        debugPrint(
          'ModelManagerService: "$modelFileName" encontrado localmente.',
        );
        final interpreter = Interpreter.fromFile(
          file,
          options: _buildOptions(),
        );
        _cache[modelFileName] = interpreter;
        return interpreter;
      } else {
        debugPrint(
            'ModelManagerService: Archivo no encontrado localmente. Iniciando descarga...');

        // 3. Descargar desde Firebase Storage
        try {
          final storageRef =
              FirebaseStorage.instance.ref().child('models/$modelFileName');
          await storageRef.writeToFile(file);
          debugPrint('ModelManagerService: Descarga completada exitosamente.');

          final interpreter = Interpreter.fromFile(
            file,
            options: _buildOptions(),
          );
          _cache[modelFileName] = interpreter;
          return interpreter;
        } catch (e) {
          debugPrint(
              'ModelManagerService: Error descargando modelo desde Firebase - $e');
        }
      }
    } catch (e) {
      debugPrint(
          'ModelManagerService: Error accediendo al almacenamiento - $e');
    }

    return null;
  }

  /// Construye opciones optimizadas para el interprete TFLite.
  InterpreterOptions _buildOptions() {
    final options = InterpreterOptions();
    // Usar 2 threads para mejor rendimiento en dispositivos multicore
    // sin consumir demasiada bateria.
    options.threads = 2;
    return options;
  }

  /// Libera todos los interpreters cacheados.
  void dispose() {
    for (final interpreter in _cache.values) {
      interpreter.close();
    }
    _cache.clear();
    debugPrint('ModelManagerService: cache de interpreters liberada.');
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider del servicio de gestion de modelos.
final modelManagerServiceProvider = Provider<ModelManagerService>((ref) {
  final service = ModelManagerService();
  ref.onDispose(service.dispose);
  return service;
});
