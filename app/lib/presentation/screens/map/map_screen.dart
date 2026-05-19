import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:navia/presentation/widgets/bottom_nav.dart';
import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/core/constants/campus_locations.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _googleMapController;
  Set<Polyline> _googlePolylines = {};
  Set<Marker> _googleMarkers = {};

  LatLng? _currentPosition;
  LatLng? _displayPosition;
  LatLng? _previousPosition;
  double _currentZoom = 17.0;
  double _currentHeading = 0.0;

  bool _centeredOnUser = false;
  bool _gpsInitDone = false;
  bool _isTrackingActive = false;
  bool _isNavigating = false;

  LatLng? _destinationLatLng;
  Timer? _routeRecalcTimer;
  Timer? _debounceTimer;

  late final AnimationController _posAnimController;
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  static const LatLng _initialPosition =
      LatLng(CampusLocations.centerLat, CampusLocations.centerLng);

  static final LatLngBounds _cameraBounds = LatLngBounds(
    southwest: const LatLng(19.2380, -103.7330),
    northeast: const LatLng(19.2710, -103.7050),
  );

  late LatLng _mapInitialCenter;
  late double _mapInitialZoom;
  bool _initializedWithArgs = false;

  // TTS / STT
  final FlutterTts _flutterTts = FlutterTts();
  late stt.SpeechToText _speechToText;
  bool _isListening = false;
  String _lastRecognizedWords = '';

  // HTTP client para llamar al backend
  final Dio _dio = Dio();

  // Map style strings (cargados desde assets)
  String? _darkMapStyle;
  String? _lightMapStyle;
  String? _currentMapStyle;

  @override
  void initState() {
    super.initState();
    _mapInitialCenter = _initialPosition;
    _mapInitialZoom = 17.0;

    _posAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_onPositionAnimTick);

    _initTts();
    _initStt();
    _loadMapStyles();
  }

  Future<void> _loadMapStyles() async {
    try {
      _darkMapStyle =
          await rootBundle.loadString('assets/map_styles/dark_style.json');
      _lightMapStyle =
          await rootBundle.loadString('assets/map_styles/light_style.json');
      final isDark = ref.read(mapThemeProvider) == 'dark';
      if (mounted) {
        setState(() => _currentMapStyle = isDark ? _darkMapStyle : _lightMapStyle);
      }
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = ref.read(settingsProvider);
    ref.read(mapThemeProvider.notifier).state =
        settings.highContrast ? 'dark' : 'light';

    if (!_initializedWithArgs) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        final lat = args['lat'] as double?;
        final lng = args['lng'] as double?;
        final zoom = args['zoom'] as double? ?? 17.0;
        if (lat != null && lng != null) {
          _mapInitialCenter = LatLng(lat, lng);
          _mapInitialZoom = zoom;
          _centeredOnUser = true;
        }
      }
      _initializedWithArgs = true;

      final navState = ref.read(navigationProvider);
      if (navState.activeRoute != null) {
        final points = navState.activeRoute!.steps
            .map((s) => LatLng(s.node.lat, s.node.lng))
            .toList();
        Future.microtask(() {
          _setRoutePolyline(points);
          setState(() {
            _isNavigating = true;
            _destinationLatLng = points.last;
          });
        });
        if (_mapInitialCenter == _initialPosition) {
          _mapInitialCenter = points.first;
          _mapInitialZoom = 17.5;
          _centeredOnUser = true;
        }
      } else if (navState.currentNode != null) {
        if (_mapInitialCenter == _initialPosition) {
          _mapInitialCenter =
              LatLng(navState.currentNode!.lat, navState.currentNode!.lng);
          _mapInitialZoom = 18.0;
          _centeredOnUser = true;
        }
      }
    }
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("es-MX");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  void _speak(String text) {
    final voiceEnabled = ref.read(settingsProvider).voiceEnabled;
    if (voiceEnabled) _flutterTts.speak(text);
  }

  Future<void> _initStt() async {
    _speechToText = stt.SpeechToText();
    await _speechToText.initialize(
      onError: (val) => debugPrint('STT Error: $val'),
      onStatus: (val) => debugPrint('STT Status: $val'),
    );
  }

  @override
  void dispose() {
    _posAnimController.removeListener(_onPositionAnimTick);
    _posAnimController.dispose();
    _routeRecalcTimer?.cancel();
    _debounceTimer?.cancel();
    _flutterTts.stop();
    _speechToText.stop();
    _googleMapController?.dispose();
    _dio.close();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────
  //  Marcadores POI — BitmapDescriptor desde Canvas
  // ──────────────────────────────────────────────────────────

  Future<BitmapDescriptor> _buildPoiIcon(
      String letter, bool isCafe, double devicePixelRatio) async {
    final cacheKey = '${letter}_${isCafe}_$devicePixelRatio';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    const size = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Glow suave
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Fondo círculo
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 8,
      Paint()..color = const Color(0xFF1E293B),
    );

    // Borde accent
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 8,
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    if (letter.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: const TextStyle(
            color: Color(0xFF38BDF8),
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((size - tp.width) / 2, (size - tp.height) / 2),
      );
    } else {
      // Ícono simple para cafetería u otros
      final iconPainter = TextPainter(
        text: TextSpan(
          text: isCafe ? '☕' : '📍',
          style: const TextStyle(fontSize: 24),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        Offset((size - iconPainter.width) / 2, (size - iconPainter.height) / 2),
      );
    }

    final img = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: 40,
      height: 40,
    );

    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> _buildUserIcon(double devicePixelRatio) async {
    const cacheKey = 'user_marker';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    const size = 80.0;
    final pulse = 1.0 +
        0.08 *
            math.sin(DateTime.now().millisecondsSinceEpoch / 600.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Anillo pulsante
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      (size / 2 - 2) * pulse,
      Paint()
        ..color = const Color(0xFFFFAB00).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Punto central
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      22,
      Paint()
        ..color = const Color(0xFFFFAB00)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      16,
      Paint()..color = const Color(0xFFFFAB00),
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      16,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final img = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: 36,
      height: 36,
    );

    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<void> _rebuildMarkers(List<PlaceNode> places) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final Set<Marker> newMarkers = {};

    for (final place in places) {
      final isBuilding = place.type.toLowerCase() == 'edificio';
      final isCafe = place.type.toLowerCase() == 'cafetería';

      String letter = place.letter ?? '';
      if (letter.isEmpty) {
        if (isBuilding && place.id.startsWith('edificio_')) {
          letter = place.id.split('_').last.toUpperCase();
        } else if (place.id == 'cecum') {
          letter = 'C';
        } else if (place.id == 'activididades_extraescolares') {
          letter = 'Ñ';
        }
      }

      final icon = await _buildPoiIcon(letter, isCafe, dpr);
      newMarkers.add(
        Marker(
          markerId: MarkerId(place.id),
          position: LatLng(place.latitude, place.longitude),
          icon: icon,
          infoWindow: InfoWindow(title: place.name, snippet: place.type),
          onTap: () =>
              ref.read(selectedPlaceProvider.notifier).state = place,
        ),
      );
    }

    if (mounted) setState(() => _googleMarkers = newMarkers);
  }

  Future<void> _updateUserMarker(LatLng position) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Invalidar cache del usuario para reflejar animación de pulso
    _markerIconCache.remove('user_marker');
    final icon = await _buildUserIcon(dpr);
    final userMarker = Marker(
      markerId: const MarkerId('user_location'),
      position: position,
      icon: icon,
      zIndexInt: 10,
      anchor: const Offset(0.5, 0.5),
    );

    if (mounted) {
      setState(() {
        _googleMarkers.removeWhere(
            (m) => m.markerId == const MarkerId('user_location'));
        _googleMarkers = {..._googleMarkers, userMarker};
      });
    }
  }

  // ──────────────────────────────────────────────────────────
  //  GPS y permisos
  // ──────────────────────────────────────────────────────────

  Future<bool> _requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) await _showGpsDisabledDialog();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.location_off_rounded,
                      color: Color(0xFF0D1B2A), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Permiso de ubicación denegado. Algunas funciones estarán limitadas.',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D1B2A)),
                    ),
                  ),
                ],
              ),
              backgroundColor: Color(0xFFFFAB00),
              behavior: SnackBarBehavior.fixed,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0D1B2A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            icon: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_disabled_rounded,
                  color: Color(0xFFFF5252), size: 40),
            ),
            title: const Text(
              'Permiso de Ubicación Requerido',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18),
            ),
            content: const Text(
              'Los permisos de ubicación han sido denegados permanentemente. '
              'Para usar la navegación en el campus, abre los ajustes de la aplicación y habilítalos manualmente.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar',
                    style: TextStyle(
                        color: Colors.white54, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Abrir Ajustes',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF0D1B2A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Geolocator.openAppSettings();
                },
              ),
            ],
          ),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _showGpsDisabledDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF38BDF8), Color(0xFF0091EA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.gps_off_rounded,
              color: Colors.white, size: 36),
        ),
        title: const Text(
          'GPS Desactivado',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Para brindarte la mejor experiencia de navegación en el campus, NAVIA necesita acceder a tu ubicación en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'También puedes navegar escaneando los códigos QR de los pasillos.',
                      style: TextStyle(
                          color: Color(0xFF90CAF9),
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuar sin GPS',
                style: TextStyle(
                    color: Colors.white54, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.gps_fixed_rounded, size: 18),
            label: const Text('Activar GPS',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF0D1B2A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Geolocator.openLocationSettings();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _initializeGpsAndCenter() async {
    try {
      if (_centeredOnUser) return;
      final permissionGranted = await _requestLocationPermission();
      if (!permissionGranted || !mounted) return;

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        if (!mounted) return;
        final latLng = LatLng(position.latitude, position.longitude);
        setState(() => _currentPosition = latLng);
        if (!_centeredOnUser) {
          _centeredOnUser = true;
          _googleMapController
              ?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17.5));
        }
      } on TimeoutException {
        debugPrint('GPS: timeout — se usará el stream.');
      } catch (e) {
        debugPrint('GPS: error al obtener posición inicial: $e');
      }
    } finally {
      _gpsInitDone = true;
    }
  }

  void _centerOnUser() {
    // Restaurar a GPS real al centrar
    ref.read(navigationProvider.notifier).clearManualPosition();
    setState(() => _isTrackingActive = true);

    LatLng? targetPos = _displayPosition ?? _currentPosition;

    if (targetPos != null) {
      _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(targetPos, _currentZoom));
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Interpolación GPS suave
  // ──────────────────────────────────────────────────────────

  void _onNewGpsPosition(LatLng newPos, {double heading = 0.0}) {
    _previousPosition = _displayPosition ?? _currentPosition ?? newPos;
    setState(() {
      _currentPosition = newPos;
      if (heading >= 0) _currentHeading = heading;
    });
    _posAnimController.forward(from: 0.0);
    if (_isNavigating) _scheduleRouteRecalc(newPos);
  }

  void _onPositionAnimTick() {
    if (_previousPosition == null || _currentPosition == null) return;

    final t = Curves.easeOutCubic.transform(_posAnimController.value);
    final lat = _previousPosition!.latitude +
        (_currentPosition!.latitude - _previousPosition!.latitude) * t;
    final lng = _previousPosition!.longitude +
        (_currentPosition!.longitude - _previousPosition!.longitude) * t;

    final interpolated = LatLng(lat, lng);
    setState(() => _displayPosition = interpolated);
    _updateUserMarker(interpolated);

    if (_isTrackingActive) {
      if (_isNavigating) {
        _googleMapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: interpolated,
              zoom: 19.5,
              tilt: 50.0,
              bearing: _currentHeading,
            ),
          ),
        );
      } else {
        _googleMapController?.animateCamera(
            CameraUpdate.newLatLng(interpolated));
      }
    }
  }

  void _scheduleRouteRecalc(LatLng rawPos) {
    _routeRecalcTimer?.cancel();
    _routeRecalcTimer =
        Timer(const Duration(milliseconds: 1200), () async {
      if (!mounted || !_isNavigating || _destinationLatLng == null) return;

      final snapPos = _displayPosition ?? rawPos;
      final navService = ref.read(navigationServiceProvider);
      final graph = navService.graph;
      if (graph == null) return;

      final corridors = graph.nodes.values
          .where((n) =>
              n.type == NodeType.corridor || n.type == NodeType.entrance)
          .toList();
      final nearest =
          _closestNodeTo(corridors, snapPos, maxDistanceM: 100);
      if (nearest == null) return;
      if (nearest.id == navService.currentNodeId) return;

      await calculateAccessibleRoute(_destinationLatLng!);
    });
  }

  // ──────────────────────────────────────────────────────────
  //  Rutas via Google Routes API (backend proxy)
  // ──────────────────────────────────────────────────────────

  Future<void> calculateAccessibleRoute(LatLng destination,
      [String? destinationName]) async {
    _destinationLatLng = destination;

    final origin = _displayPosition ?? _currentPosition;
    if (origin == null) {
      final navService = ref.read(navigationServiceProvider);
      final graph = navService.graph;
      final fromId = navService.currentNodeId;

      if (fromId == null || graph == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.qr_code_scanner,
                      color: Color(0xFF0D1B2A), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Activa el GPS o escanea el QR del pasillo más cercano para trazar tu ruta.',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D1B2A)),
                    ),
                  ),
                ],
              ),
              backgroundColor: Color(0xFF38BDF8),
              behavior: SnackBarBehavior.fixed,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      // Si hay nodo QR fijado, usar sus coordenadas como origen
      final fromNode = graph.nodes[fromId];
      if (fromNode == null) return;
      await _fetchRoute(
          LatLng(fromNode.lat, fromNode.lng), destination, destinationName);
      return;
    }

    await _fetchRoute(origin, destination, destinationName);
  }

  Future<void> _fetchRoute(
      LatLng origin, LatLng destination, String? destinationName) async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        _fallbackToDijkstra(destination);
        return;
      }

      final response = await _dio.post(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
        data: {
          "origin": {
            "location": {
              "latLng": {
                "latitude": origin.latitude,
                "longitude": origin.longitude
              }
            }
          },
          "destination": {
            "location": {
              "latLng": {
                "latitude": destination.latitude,
                "longitude": destination.longitude
              }
            }
          },
          "travelMode": "WALK",
        },
        options: Options(
          headers: {
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask':
                'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final routes = response.data['routes'] as List<dynamic>?;
      if (routes != null && routes.isNotEmpty) {
        final route = routes.first;
        final encodedPolyline = route['polyline']['encodedPolyline'] as String;
        final points = _decodePolyline(encodedPolyline);
        final distance = route['distanceMeters'] as int? ?? 0;

        if (points.isEmpty) {
          _speak('No se encontró una ruta válida.');
          return;
        }

        _setRoutePolyline(points);
        setState(() {
          _isNavigating = true;
          _destinationLatLng = destination;
        });

        _fitBounds(points);

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _isNavigating) {
            setState(() => _isTrackingActive = true);
          }
        });

        _speak(
            'Ruta trazada hacia ${destinationName ?? "tu destino"}. '
            '${distance > 0 ? "$distance metros." : ""}');
      } else {
        debugPrint('Google Routes no encontró ruta.');
        _fallbackToDijkstra(destination);
      }
    } on DioException catch (e) {
      debugPrint('Error al obtener ruta (Dio): ${e.response?.data ?? e.message}');
      _fallbackToDijkstra(destination);
    } catch (e) {
      debugPrint('Error inesperado en ruta: $e');
      _fallbackToDijkstra(destination);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  void _fallbackToDijkstra(LatLng destination) {
    final navService = ref.read(navigationServiceProvider);
    final graph = navService.graph;
    if (graph == null) return;

    final destNode = _closestNodeTo(graph.nodes.values.toList(), destination);
    if (destNode != null) {
      ref.read(navigationProvider.notifier).navigateTo(destNode.id);
      _speak('Usando sistema de navegación local del campus.');
    } else {
      _speak('No se pudo calcular la ruta.');
    }
  }

  void _setRoutePolyline(List<LatLng> points) {
    setState(() {
      _googlePolylines = {
        Polyline(
          polylineId: const PolylineId('campus_route'),
          points: points,
          color: const Color(0xFF38BDF8),
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      };
    });
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _googleMapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  CampusNode? _closestNodeTo(List<CampusNode> nodes, LatLng target,
      {double maxDistanceM = double.infinity}) {
    CampusNode? best;
    double bestDist = double.infinity;
    for (final node in nodes) {
      final d = Geolocator.distanceBetween(
          target.latitude, target.longitude, node.lat, node.lng);
      if (d < bestDist) {
        bestDist = d;
        best = node;
      }
    }
    return bestDist <= maxDistanceM ? best : null;
  }

  // ──────────────────────────────────────────────────────────
  //  STT
  // ──────────────────────────────────────────────────────────

  Future<void> _startListening(LongPressStartDetails details) async {
    _flutterTts.stop();
    if (!_speechToText.isAvailable) {
      final bool available = await _speechToText.initialize();
      if (!mounted) return;
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Micrófono no disponible.')),
        );
        return;
      }
    }
    setState(() => _isListening = true);
    await _speechToText.listen(
      onResult: (result) {
        setState(
            () => _lastRecognizedWords = result.recognizedWords);
      },
      localeId: "es_MX",
    );
  }

  Future<void> _stopListening(LongPressEndDetails details) async {
    setState(() => _isListening = false);
    await _speechToText.stop();
    _processVoiceCommand(_lastRecognizedWords);
  }

  void _processVoiceCommand(String text) {
    if (text.isEmpty) return;
    final lowerText = text.toLowerCase();

    if (lowerText.contains('ir a') ||
        lowerText.contains('buscar') ||
        lowerText.contains('ir')) {
      String searchTarget = lowerText
          .replaceAll('quiero ir a la', '')
          .replaceAll('quiero ir al', '')
          .replaceAll('ir a la', '')
          .replaceAll('ir al', '')
          .replaceAll('ir a', '')
          .replaceAll('ir', '')
          .replaceAll('buscar', '')
          .replaceAll('quiero', '')
          .trim();

      if (searchTarget.isNotEmpty) {
        _speak('Buscando $searchTarget');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Map Screen'),
      ),
    );
  }
}
