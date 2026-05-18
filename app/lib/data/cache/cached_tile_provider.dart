import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// Proveedor de tiles con caché en disco para soporte offline.
///
/// Estrategia:
///  1. Al solicitar un tile, primero verifica si existe en el caché local.
///  2. Si existe → retorna desde disco (funciona offline).
///  3. Si no existe → descarga por HTTP, guarda en disco, y retorna.
///  4. Si falla la descarga (offline) → retorna el tile en caché si existe,
///     o un tile transparente si no hay caché.
///
/// Los tiles se almacenan en:
///   `{appCacheDir}/navia_tiles/{z}/{x}/{y}.png`
///
/// Solo usa [Dio] (ya en pubspec) para las descargas HTTP.
/// No requiere paquetes adicionales.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({this.maxCacheAgeDays = 30});

  /// Días máximos que un tile cacheado se considera válido.
  /// Después de este tiempo se re-descarga (si hay conexión).
  final int maxCacheAgeDays;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    responseType: ResponseType.bytes,
  ));

  String? _cacheDir;

  /// Obtiene el directorio base de caché (lazy init).
  Future<String> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = '${appDir.path}/navia_tiles';
    return _cacheDir!;
  }

  /// Ruta del archivo de tile en disco.
  Future<String> _tilePath(TileCoordinates coords) async {
    final dir = await _getCacheDir();
    return '$dir/${coords.z}/${coords.x}/${coords.y}.png';
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // Construir la URL del tile usando el template
    final url = getTileUrl(coordinates, options);

    // Retornar un ImageProvider que primero busca en caché
    return _CachedTileImageProvider(
      url: url,
      coordinates: coordinates,
      provider: this,
    );
  }
}

/// ImageProvider personalizado que implementa el flujo caché → red.
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  final String url;
  final TileCoordinates coordinates;
  final CachedTileProvider provider;

  const _CachedTileImageProvider({
    required this.url,
    required this.coordinates,
    required this.provider,
  });

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadTile(ImageDecoderCallback decode) async {
    final filePath = await provider._tilePath(coordinates);
    final file = File(filePath);

    // 1. Intentar leer desde caché
    if (await file.exists()) {
      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);

      // Si el tile no expiró, usarlo directamente
      if (age.inDays < provider.maxCacheAgeDays) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return decode(buffer);
        }
      }
    }

    // 2. Descargar de la red
    try {
      final response = await provider._dio.get<List<int>>(url);
      final bytes = Uint8List.fromList(response.data!);

      // Guardar en disco (fire-and-forget, no bloquea el render)
      _saveToDisk(file, bytes);

      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) {
      // 3. Fallback: si hay caché expirado, usarlo
      if (await file.exists()) {
        debugPrint('TileCache: usando tile expirado offline → $filePath');
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return decode(buffer);
        }
      }

      // 4. Sin caché ni red → tile transparente 1x1
      debugPrint('TileCache: tile no disponible → $url');
      final transparent = _transparentPixel();
      final buffer = await ui.ImmutableBuffer.fromUint8List(transparent);
      return decode(buffer);
    }
  }

  /// Guarda los bytes del tile en disco de forma asíncrona.
  Future<void> _saveToDisk(File file, Uint8List bytes) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('TileCache: error guardando tile → $e');
    }
  }

  /// Genera un PNG transparente de 1x1 píxel (fallback mínimo).
  static Uint8List _transparentPixel() {
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, // 8-bit RGBA
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT
      0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, // zlib
      0xE5, 0x27, 0xDE, 0xFC, // CRC
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
      0xAE, 0x42, 0x60, 0x82, // CRC
    ]);
  }

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _CachedTileImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}
