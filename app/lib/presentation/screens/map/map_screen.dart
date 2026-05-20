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

import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/core/constants/campus_locations.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';
import 'package:navia/core/theme/app_theme.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _googleMapController;
  Set<Marker> _googleMarkers = {};
  Set<Polyline> _googlePolylines = {};

  LatLng? _currentPosition;
  LatLng? _displayPosition;
  LatLng? _previousPosition;
  double _currentZoom = 17.0;
  double _currentHeading = 0.0;

  bool _centeredOnUser = false;
  bool _isTrackingActive = false;
  bool _isNavigating = false;

  /// Guard para evitar llamadas concurrentes a _fetchRoute cuando el usuario
  /// toca "Trazar Ruta" varias veces antes de que termine la primera peticion.
  bool _isFetchingRoute = false;

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

    final cs = Theme.of(context).colorScheme;
    final primaryColor = cs.primary;
    final surfaceColor = cs.surface;

    // Glow suave
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Fondo círculo
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 8,
      Paint()..color = surfaceColor,
    );

    // Borde accent
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 8,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    if (letter.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: TextStyle(
            color: primaryColor,
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
      // Icono material professional en vez de emoji
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(
            isCafe ? Icons.local_cafe_rounded.codePoint : Icons.place_rounded.codePoint
          ),
          style: TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: 32,
            color: isCafe ? const Color(0xFFFFB020) : primaryColor,
          ),
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

  void _showOutsideCampusSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Te encuentras fuera del campus. Centrando vista en el TecNM Colima.',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Color(0xFF1E293B),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _initializeGpsAndCenter({bool force = false}) async {
    if (_centeredOnUser && !force) return;
    final permissionGranted = await _requestLocationPermission();
    if (!permissionGranted || !mounted) return;

    ref.invalidate(currentLocationStreamProvider);

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (!mounted) return;
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() => _currentPosition = latLng);
      
      final distanceToCampus = Geolocator.distanceBetween(
        latLng.latitude, latLng.longitude,
        CampusLocations.centerLat, CampusLocations.centerLng,
      );
      
      _centeredOnUser = true;
      if (distanceToCampus < 2500) {
        _googleMapController
            ?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17.5));
      } else {
        _googleMapController
            ?.animateCamera(CameraUpdate.newLatLngZoom(_initialPosition, 17.0));
        _showOutsideCampusSnackBar();
      }
    } on TimeoutException {
      debugPrint('GPS: timeout — se usará el stream.');
    } catch (e) {
      debugPrint('GPS: error al obtener posición inicial: $e');
    }
  }

  void _centerOnUser() {
    // Restaurar a GPS real al centrar
    ref.read(navigationProvider.notifier).clearManualPosition();
    setState(() => _isTrackingActive = true);

    LatLng? targetPos = _displayPosition ?? _currentPosition;

    if (targetPos != null) {
      final distanceToCampus = Geolocator.distanceBetween(
        targetPos.latitude, targetPos.longitude,
        CampusLocations.centerLat, CampusLocations.centerLng,
      );
      if (distanceToCampus < 2500) {
        _googleMapController?.animateCamera(
            CameraUpdate.newLatLngZoom(targetPos, _currentZoom));
      } else {
        _googleMapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_initialPosition, 17.0));
        _showOutsideCampusSnackBar();
      }
    } else {
      _initializeGpsAndCenter(force: true);
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
      final distanceToCampus = Geolocator.distanceBetween(
        interpolated.latitude, interpolated.longitude,
        CampusLocations.centerLat, CampusLocations.centerLng,
      );
      if (distanceToCampus < 2500) {
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
    if (_isFetchingRoute) return;
    _isFetchingRoute = true;
    _destinationLatLng = destination;

    try {
      final origin = _displayPosition ?? _currentPosition;
      if (origin == null) {
        final navService = ref.read(navigationServiceProvider);
        final graph = navService.graph;
        final fromId = navService.currentNodeId;

        if (fromId == null || graph == null) {
          if (mounted) {
            final cs = Theme.of(context).colorScheme;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.view_in_ar_rounded,
                        color: cs.onPrimary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Activa el GPS o usa la cámara NAVIA AR para trazar tu ruta.',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimary),
                      ),
                    ),
                  ],
                ),
                backgroundColor: cs.primary,
                behavior: SnackBarBehavior.fixed,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
        // Si hay nodo QR fijado, usar sus coordenadas como origen
        final fromNode = graph.nodes[fromId];
        if (fromNode == null) return;
        await ref.read(navigationProvider.notifier).calculateGoogleRoute(
              originLat: fromNode.lat,
              originLng: fromNode.lng,
              destLat: destination.latitude,
              destLng: destination.longitude,
              destinationName: destinationName,
            );
        return;
      }

      await ref.read(navigationProvider.notifier).calculateGoogleRoute(
            originLat: origin.latitude,
            originLng: origin.longitude,
            destLat: destination.latitude,
            destLng: destination.longitude,
            destinationName: destinationName,
          );
    } finally {
      _isFetchingRoute = false;
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
    if (_currentPosition != null) {
      ref.read(navigationProvider.notifier).setPositionByCoordinates(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
    }
    ref.read(voiceProvider.notifier).processTextCommand(text);
  }

  // ──────────────────────────────────────────────────────────
  //  Bottom Sheet y helpers UI
  // ──────────────────────────────────────────────────────────

  void _announceNearestPlace(LatLng center) {
    final placesAsyncValue = ref.read(placesStreamProvider);
    placesAsyncValue.whenData((places) {
      if (places.isEmpty) return;
      PlaceNode? nearest;
      double minDist = double.infinity;
      for (final p in places) {
        final d = Geolocator.distanceBetween(
            center.latitude, center.longitude, p.latitude, p.longitude);
        if (d < minDist) { minDist = d; nearest = p; }
      }
      if (nearest != null && minDist < 150) {
        _flutterTts.stop();
        _speak('Viendo zona cerca de: ${nearest.name}');
      }
    });
  }

  void _handleArrival() {
    ref.read(navigationProvider.notifier).cancelNavigation();
    setState(() {
      _isNavigating = false;
      _googlePolylines = {};
      _destinationLatLng = null;
      _isTrackingActive = false;
    });
    _speak('Has llegado a tu destino. NAVIA te desea un excelente dia.');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF0D1B2A), size: 24),
            SizedBox(width: 10),
            Text('Has llegado a tu destino!',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D1B2A))),
          ],
        ),
        backgroundColor: const Color(0xFF38BDF8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showAccessibleBottomSheet(PlaceNode place) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50, height: 5,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    place.type.toLowerCase().contains('cafetería') ? Icons.coffee_rounded : Icons.business_rounded,
                    color: cs.primary, size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                            letterSpacing: -0.5,
                          )),
                      const SizedBox(height: 4),
                      Text(place.type.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: cs.primary.withValues(alpha: 0.8),
                            letterSpacing: 1.2,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _buildInfoBadge(Icons.accessible_rounded,
                    'Nivel: ${place.accessibilityLevel.toUpperCase()}',
                    place.accessibilityLevel.toLowerCase() == 'alto' ? Colors.greenAccent : Colors.orangeAccent),
                const SizedBox(width: 12),
                _buildInfoBadge(Icons.map_rounded, 'Piso: Planta Baja', Colors.blueAccent),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.85)]),
                    ),
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.directions_walk_rounded, size: 22, color: cs.onPrimary),
                      label: Text('Trazar Ruta',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onPrimary)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        final navService = ref.read(navigationServiceProvider);
                        var node = navService.findDestination(place.id);
                        node ??= navService.findDestination(place.name);
                        if (node != null) {
                          if (_currentPosition != null) {
                            ref.read(navigationProvider.notifier).setPositionByCoordinates(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                );
                          }
                          ref.read(navigationProvider.notifier).navigateTo(node.id);
                        } else {
                          calculateAccessibleRoute(
                              LatLng(place.latitude, place.longitude),
                              place.name);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
                      color: cs.primary.withValues(alpha: 0.05),
                    ),
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.location_on_rounded, size: 22, color: cs.primary),
                      label: Text('Estoy Aquí',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.primary)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ref.read(navigationProvider.notifier).setPosition(place.id);
                        _speak('Ubicación fijada en ${place.name}.');
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppBar(
      backgroundColor: theme.appBarTheme.backgroundColor ?? cs.surface,
      foregroundColor: theme.appBarTheme.foregroundColor ?? cs.onSurface,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 36, height: 36,
            margin: const EdgeInsets.only(left: 4, right: 10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Icon(Icons.school_rounded, color: cs.primary, size: 20),
          ),
          Text('NAVIA',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.appBarTheme.titleTextStyle?.color ?? cs.onSurface,
                letterSpacing: 2.5,
              )),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: cs.primary,
          ),
          onPressed: () {
            final newTheme = isDark ? 'light' : 'dark';
            ref.read(mapThemeProvider.notifier).state = newTheme;
            setState(() => _currentMapStyle = newTheme == 'dark' ? _darkMapStyle : _lightMapStyle);
          },
          tooltip: 'Cambiar tema',
        ),
      ],
    );
  }

  Widget _buildFABs() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'center_btn',
            onPressed: _centerOnUser,
            backgroundColor: _isTrackingActive ? cs.primary : cs.surface,
            elevation: _isTrackingActive ? 8 : 4,
            child: Icon(
              _isTrackingActive ? Icons.gps_fixed_rounded : Icons.my_location_rounded,
              color: _isTrackingActive ? cs.onPrimary : cs.primary,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onLongPressStart: _startListening,
            onLongPressEnd: _stopListening,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 70, height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _isListening
                    ? const LinearGradient(colors: [Color(0xFFFF5252), Color(0xFFFF1744)])
                    : LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [cs.primary, cs.primary.withValues(alpha: 0.85)]),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? const Color(0xFFFF5252) : cs.primary)
                        .withValues(alpha: 0.5),
                    blurRadius: _isListening ? 20 : 12,
                    spreadRadius: _isListening ? 4 : 2,
                  ),
                ],
              ),
              child: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded, color: _isListening ? Colors.white : cs.onPrimary, size: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    final cs = Theme.of(context).colorScheme;
    final currentFilter = ref.watch(categoryFilterProvider);
    final filters = [
      ('Todo', Icons.grid_view_rounded),
      ('Edificio', Icons.business_rounded),
      ('Cafetería', Icons.coffee_rounded),
      ('Servicios', Icons.miscellaneous_services_rounded),
      ('Parque', Icons.park_rounded),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filters.map((fd) {
          final isSelected = currentFilter.toLowerCase() == fd.$1.toLowerCase();
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => ref.read(categoryFilterProvider.notifier).state = fd.$1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.85)])
                      : null,
                  color: isSelected ? null : cs.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : cs.onSurface.withValues(alpha: 0.12),
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 10)]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(fd.$2, size: 15, color: isSelected ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text(fd.$1,
                        style: TextStyle(
                          color: isSelected ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.75),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13, letterSpacing: 0.3,
                        )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Escuchar cambios de tema global para regenerar marcadores con nuevos colores
    ref.listen(themeProvider, (_, __) {
      _markerIconCache.clear();
      _rebuildMarkers(ref.read(filteredPlacesProvider));
    });

    // Lugar seleccionado → bottom sheet
    ref.listen<PlaceNode?>(selectedPlaceProvider, (_, next) {
      if (next != null) {
        _showAccessibleBottomSheet(next);
        Future.delayed(const Duration(milliseconds: 100),
            () => ref.read(selectedPlaceProvider.notifier).state = null);
      }
    });

    // Stream GPS
    ref.listen<AsyncValue<Position>>(currentLocationStreamProvider, (_, next) {
      next.whenData((position) {
        final latLng = LatLng(position.latitude, position.longitude);
        _onNewGpsPosition(latLng, heading: position.heading);

        // Sincronizar posición actual en el provider de navegación local
        ref.read(navigationProvider.notifier).setPositionByCoordinates(
              position.latitude,
              position.longitude,
            );

        if (!_centeredOnUser) {
          _centeredOnUser = true;
          final distanceToCampus = Geolocator.distanceBetween(
            latLng.latitude, latLng.longitude,
            CampusLocations.centerLat, CampusLocations.centerLng,
          );
          if (distanceToCampus < 2500) {
            _googleMapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17.5));
          } else {
            _googleMapController?.animateCamera(CameraUpdate.newLatLngZoom(_initialPosition, 17.0));
            _showOutsideCampusSnackBar();
          }
        }

        if (_isNavigating && _destinationLatLng != null) {
          final dist = Geolocator.distanceBetween(
            latLng.latitude, latLng.longitude,
            _destinationLatLng!.latitude, _destinationLatLng!.longitude,
          );
          if (dist <= 10.0) _handleArrival();
        }
      });
    });

    // Navegación activa → actualizar polilínea
    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.currentNode != previous?.currentNode && next.currentNode != null) {
        _googleMapController?.animateCamera(CameraUpdate.newLatLng(
          LatLng(next.currentNode!.lat, next.currentNode!.lng),
        ));
      }

      // Auto-navegar a NAVIA AR cuando se encuentra una ruta por voz o localmente.
      if (next.pendingARNavigation && !(previous?.pendingARNavigation ?? false)) {
        ref.read(navigationProvider.notifier).consumeARNavigation();
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.scanner,
          );
        }
      }

      if (next.activeRoute != previous?.activeRoute ||
          next.routePolylinePoints != previous?.routePolylinePoints) {
        if (next.routePolylinePoints != null) {
          final points = next.routePolylinePoints!
              .map((p) => LatLng(p[0], p[1]))
              .toList();
          _setRoutePolyline(points);
          setState(() => _isNavigating = true);
          _fitBounds(points);
        } else if (next.activeRoute != null) {
          final points = next.activeRoute!.steps
              .map((s) => LatLng(s.node.lat, s.node.lng))
              .toList();
          _setRoutePolyline(points);
          setState(() => _isNavigating = true);
          _fitBounds(points);
        } else {
          setState(() { _googlePolylines = {}; _isNavigating = false; });
        }
      }
    });

    // Lugares filtrados → reconstruir marcadores
    ref.listen<List<PlaceNode>>(filteredPlacesProvider, (_, next) => _rebuildMarkers(next));

    final isDark = ref.watch(mapThemeProvider) == 'dark';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: _buildAppBar(isDark),
      floatingActionButton: _buildFABs(),
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: Stack(
        children: [
          // ── Mapa Google Maps ──────────────────────────────────
          RepaintBoundary(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _mapInitialCenter,
                zoom: _mapInitialZoom,
              ),
              onMapCreated: (controller) {
                _googleMapController = controller;
                _initializeGpsAndCenter();
                _rebuildMarkers(ref.read(filteredPlacesProvider));
              },
              onCameraMove: (pos) {
                _currentZoom = pos.zoom;
                if (_isTrackingActive) setState(() => _isTrackingActive = false);
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 600),
                    () => _announceNearestPlace(pos.target));
              },
              markers: _googleMarkers,
              polylines: _googlePolylines,
              style: _currentMapStyle,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              rotateGesturesEnabled: false,
              cameraTargetBounds: CameraTargetBounds(_cameraBounds),
              minMaxZoomPreference: const MinMaxZoomPreference(13, 20),
              mapType: MapType.normal,
            ),
          ),
          // ── Gradient top para legibilidad de filtros ──────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [
                    (isDark ? const Color(0xFF0F172A) : Colors.white).withValues(alpha: 0.95),
                    (isDark ? const Color(0xFF0F172A) : Colors.white).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // ── Filtros de categoría ──────────────────────────────
          Positioned(top: 12, left: 0, right: 0, child: _buildFiltersRow()),
          // ── Indicador de escucha por voz ──────────────────────
          if (_isListening)
            Positioned(
              bottom: 120, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                  boxShadow: [BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.2), blurRadius: 20)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.graphic_eq, color: Color(0xFF38BDF8), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lastRecognizedWords.isEmpty ? 'Escuchando...' : _lastRecognizedWords,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // ── Barra de navegacion activa ────────────────────────
          if (_isNavigating)
            Positioned(
              top: 70, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.navigation_rounded, color: Color(0xFF38BDF8), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Ruta activa',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    // Boton para ir a NAVIA AR
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(context, AppRoutes.scanner);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.view_in_ar_rounded, color: Color(0xFF0D1B2A), size: 14),
                            SizedBox(width: 4),
                            Text('AR',
                                style: TextStyle(
                                    color: Color(0xFF0D1B2A),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        ref.read(navigationProvider.notifier).cancelNavigation();
                        setState(() {
                          _isNavigating = false;
                          _googlePolylines = {};
                          _destinationLatLng = null;
                          _isTrackingActive = false;
                        });
                      },
                      child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
