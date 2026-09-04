import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';

import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/venue.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/core/constants/campus_locations.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/data/providers/auth_provider.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';
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

  // google_maps_flutter solo tiene implementación nativa en Android/iOS/Web.
  // En desktop (Windows/Linux/macOS) usamos flutter_map con tiles OSM.
  fm.MapController? _flutterMapController;
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  LatLng? _currentPosition;
  LatLng? _displayPosition;
  LatLng? _previousPosition;

  /// Posición interpolada del usuario, actualizada en cada frame de la
  /// animación de suavizado GPS (~60/s). Se lee con un ValueListenableBuilder
  /// acotado solo al widget del mapa, para que mover el punto azul no
  /// reconstruya toda la pantalla (botones, banners, etc.) 60 veces por
  /// segundo — esa era la causa real de que la navegación se sintiera trabada.
  final ValueNotifier<LatLng?> _userPosNotifier = ValueNotifier<LatLng?>(null);

  /// Ícono del usuario para GoogleMap, generado una sola vez (no en cada
  /// frame): regenerarlo por frame implicaba dibujar en Canvas y codificar
  /// PNG ~60 veces por segundo, carísimo para un simple punto que se mueve.
  BitmapDescriptor? _userIconCache;
  double _currentZoom = 17.0;
  double _currentHeading = 0.0;

  bool _centeredOnUser = false;
  bool _isTrackingActive = false;
  bool _isNavigating = false;

  /// true mientras una animación de cámara disparada por nuestro propio
  /// código (seguir al usuario) está en curso — ver _panCamera/_panCameraNavigating.
  bool _isProgrammaticCameraMove = false;

  // ──────────────────────────────────────────────────────────
  //  Editor de administrador (Fase 2)
  // ──────────────────────────────────────────────────────────

  /// Solo visible/activable si isAdminProvider es true. Al tocar el mapa en
  /// este modo se agregan puntos nuevos en vez de solo consultarlos.
  bool _isEditMode = false;

  /// Id del punto que se está reubicando: el siguiente toque en el mapa lo
  /// mueve ahí y sale de este modo. `null` = no hay una reubicación pendiente.
  String? _editMovingId;

  /// Id del punto de origen elegido para trazar una arista nueva ("Conectar").
  /// `null` = no hay ninguna conexión en curso.
  String? _editConnectFromId;

  /// Posición del punto de origen elegido para "Conectar" — se guarda junto
  /// con el id para no tener que volver a buscarlo al crear la arista.
  LatLng? _editConnectFromPos;

  /// Guard para no disparar dos escrituras a la vez desde el editor.
  bool _isEditSaving = false;

  /// true mientras una hoja del editor (agregar/editar punto) está abierta.
  /// GoogleMap en Flutter Web usa un elemento HTML real por debajo (no un
  /// canvas normal de Flutter), y sus toques a veces se "filtran" a través
  /// del modal — sin este guard, tocar un ChoiceChip dentro de la hoja
  /// también llegaba al mapa de fondo y volvía a abrir "Nuevo punto" desde
  /// cero (por eso siempre "regresaba a Edificio", el tipo por defecto).
  bool _isEditSheetOpen = false;

  static const _uuid = Uuid();

  /// Guard para evitar llamadas concurrentes a _fetchRoute cuando el usuario
  /// toca "Trazar Ruta" varias veces antes de que termine la primera peticion.
  bool _isFetchingRoute = false;

  LatLng? _destinationLatLng;
  Timer? _routeRecalcTimer;

  late final AnimationController _posAnimController;
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  static const LatLng _initialPosition =
      LatLng(CampusLocations.centerLat, CampusLocations.centerLng);

  /// Sede que se está mostrando. Se resuelve en [didChangeDependencies] desde
  /// `arguments['venueId']`; por defecto TecNM Colima si no se especifica.
  Venue _venue = VenueRegistry.tecColima;

  /// Centro de la sede que se está viendo. Toda la lógica de GPS se mide
  /// contra ESTO, no contra el centro del TecNM Colima: 6 de las 9 sedes del
  /// evento quedan a más de 2.5 km del Tec (Coquimatlán a ~9.5 km), así que
  /// medir contra el Tec hacía que la app te considerara "fuera del campus"
  /// estando parado justo en la sede.
  LatLng get _venueCenter => LatLng(_venue.centerLat, _venue.centerLng);

  /// Radio alrededor del centro de la sede dentro del cual se considera que
  /// el usuario está "en la sede" y tiene sentido centrar/seguir su GPS.
  static const double _venueRadiusMeters = 2500;

  /// Caja de restricción de cámara de la sede actual (antes era un único
  /// valor global fijo a TecNM Colima — Sendera/Zentralia ya caían fuera de
  /// esa caja).
  LatLngBounds get _cameraBounds => LatLngBounds(
        southwest: LatLng(_venue.boundsSouthLat, _venue.boundsWestLng),
        northeast: LatLng(_venue.boundsNorthLat, _venue.boundsEastLng),
      );

  late LatLng _mapInitialCenter;
  late double _mapInitialZoom;
  bool _initializedWithArgs = false;

  // TTS
  final FlutterTts _flutterTts = FlutterTts();
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

    if (_isDesktop) {
      _flutterMapController = fm.MapController();
    }

    _initTts();
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
        final venueId = args['venueId'] as String?;
        if (venueId != null) {
          _venue = VenueRegistry.byId(venueId);
        }

        final lat = args['lat'] as double?;
        final lng = args['lng'] as double?;
        final zoom = args['zoom'] as double? ?? 17.0;
        if (lat != null && lng != null) {
          _mapInitialCenter = LatLng(lat, lng);
          _mapInitialZoom = zoom;
          _centeredOnUser = true;
        }
      }
      // Sincroniza el provider de sede actual para que filteredPlacesProvider
      // (y con él, todo el pipeline de marcadores) escuche la sede correcta.
      // Se difiere: este mismo widget hace `ref.watch(filteredPlacesProvider)`
      // en su build(), y escribir el provider que depende de él mientras el
      // árbol todavía se está montando dispara "Tried to modify a provider
      // while the widget tree was building" en Riverpod.
      final resolvedVenueId = _venue.id;
      Future(() {
        if (mounted) {
          ref.read(currentVenueIdProvider.notifier).state = resolvedVenueId;
        }
      });
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

  @override
  void dispose() {
    _posAnimController.removeListener(_onPositionAnimTick);
    _posAnimController.dispose();
    _routeRecalcTimer?.cancel();
    _userPosNotifier.dispose();
    _flutterTts.stop();
    _googleMapController?.dispose();
    _flutterMapController?.dispose();
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
          onTap: () {
            if (_isEditMode || _editConnectFromId != null) {
              _handleEditTapOnPoint(
                id: place.id,
                name: place.name,
                lat: place.latitude,
                lng: place.longitude,
                hasPlace: true,
              );
            } else {
              ref.read(selectedPlaceProvider.notifier).state = place;
            }
          },
        ),
      );
    }

    if (mounted) setState(() => _googleMarkers = newMarkers);
  }

  // ──────────────────────────────────────────────────────────
  //  Cámara multiplataforma (GoogleMap / flutter_map)
  // ──────────────────────────────────────────────────────────

  ll.LatLng _toLL(LatLng p) => ll.LatLng(p.latitude, p.longitude);

  void _panCamera(LatLng target, {double? zoom}) {
    if (_isDesktop) {
      final controller = _flutterMapController;
      if (controller == null) return;
      controller.move(_toLL(target), zoom ?? controller.camera.zoom);
      return;
    }
    // GoogleMap dispara onCameraMove también para movimientos programáticos
    // (no solo gestos del usuario) — sin esta bandera, seguir al usuario
    // apagaba _isTrackingActive a sí mismo en el primer auto-pan. flutter_map
    // no tiene este problema porque su onPositionChanged sí distingue
    // hasGesture.
    _isProgrammaticCameraMove = true;
    _googleMapController?.animateCamera(
      zoom != null
          ? CameraUpdate.newLatLngZoom(target, zoom)
          : CameraUpdate.newLatLng(target),
    );
  }

  void _panCameraNavigating(LatLng target, double zoom, double bearing) {
    if (_isDesktop) {
      _flutterMapController?.moveAndRotate(_toLL(target), zoom, bearing);
      return;
    }
    _isProgrammaticCameraMove = true;
    _googleMapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
            target: target, zoom: zoom, tilt: 50.0, bearing: bearing),
      ),
    );
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

  void _showOutsideVenueSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Estás lejos de ${_venue.label}. Centrando la vista en la sede.',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 3),
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

      final distanceToVenue = Geolocator.distanceBetween(
        latLng.latitude, latLng.longitude,
        _venueCenter.latitude, _venueCenter.longitude,
      );

      _centeredOnUser = true;
      if (distanceToVenue < _venueRadiusMeters) {
        _panCamera(latLng, zoom: 17.5);
      } else {
        _panCamera(_venueCenter, zoom: 17.0);
        _showOutsideVenueSnackBar();
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
      final distanceToVenue = Geolocator.distanceBetween(
        targetPos.latitude, targetPos.longitude,
        _venueCenter.latitude, _venueCenter.longitude,
      );
      if (distanceToVenue < _venueRadiusMeters) {
        _panCamera(targetPos, zoom: _currentZoom);
      } else {
        _panCamera(_venueCenter, zoom: 17.0);
        _showOutsideVenueSnackBar();
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
    if (!_isDesktop) _ensureUserIcon();
    _posAnimController.forward(from: 0.0);
    if (_isNavigating) _scheduleRouteRecalc(newPos);
  }

  /// Genera el ícono del usuario una sola vez y lo cachea (ver comentario en
  /// el campo _userIconCache). Solo hace falta llamarla, es idempotente.
  Future<void> _ensureUserIcon() async {
    if (_userIconCache != null || !mounted) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final icon = await _buildUserIcon(dpr);
    if (mounted) setState(() => _userIconCache = icon);
  }

  void _onPositionAnimTick() {
    if (_previousPosition == null || _currentPosition == null) return;

    final t = Curves.easeOutCubic.transform(_posAnimController.value);
    final lat = _previousPosition!.latitude +
        (_currentPosition!.latitude - _previousPosition!.latitude) * t;
    final lng = _previousPosition!.longitude +
        (_currentPosition!.longitude - _previousPosition!.longitude) * t;

    final interpolated = LatLng(lat, lng);
    // Sin setState: solo el mapa (envuelto en un ValueListenableBuilder) debe
    // reaccionar a esto, no toda la pantalla.
    _displayPosition = interpolated;
    _userPosNotifier.value = interpolated;

    if (_isTrackingActive) {
      final distanceToVenue = Geolocator.distanceBetween(
        interpolated.latitude, interpolated.longitude,
        _venueCenter.latitude, _venueCenter.longitude,
      );
      if (distanceToVenue < _venueRadiusMeters) {
        if (_isNavigating) {
          _panCameraNavigating(interpolated, 19.5, _currentHeading);
        } else {
          _panCamera(interpolated);
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
    if (_isDesktop) {
      _flutterMapController?.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(points.map(_toLL).toList()),
          padding: const EdgeInsets.all(60),
        ),
      );
      return;
    }
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
  //  Bottom Sheet y helpers UI
  // ──────────────────────────────────────────────────────────

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

  Widget _buildThemeToggle(bool isDark) {
    return _buildRoundIconButton(
      icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      tooltip: 'Cambiar tema',
      onPressed: () {
        final newTheme = isDark ? 'light' : 'dark';
        ref.read(mapThemeProvider.notifier).state = newTheme;
        setState(() => _currentMapStyle = newTheme == 'dark' ? _darkMapStyle : _lightMapStyle);
      },
    );
  }

  /// Botón circular flotante genérico (mismo estilo para volver a Inicio y
  /// para cambiar de tema — antes vivían como parte del AppBar).
  Widget _buildRoundIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: cs.primary),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildFABs() {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = ref.watch(isAdminProvider).value ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            FloatingActionButton(
              heroTag: 'edit_btn',
              tooltip: _isEditMode ? 'Salir del modo edición' : 'Editar sede (admin)',
              backgroundColor: _isEditMode ? const Color(0xFFFFAB00) : cs.surface,
              onPressed: () => setState(() {
                _isEditMode = !_isEditMode;
                _editMovingId = null;
                _editConnectFromId = null;
                _editConnectFromPos = null;
              }),
              child: Icon(
                _isEditMode ? Icons.close_rounded : Icons.edit_location_alt_rounded,
                color: _isEditMode ? const Color(0xFF0D1B2A) : cs.primary,
              ),
            ),
            const SizedBox(height: 12),
          ],
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
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Editor de administrador (Fase 2) — agregar/mover/conectar/borrar
  //  puntos del grafo caminable y sus pines de POI.
  // ──────────────────────────────────────────────────────────

  /// Toque sobre el mapa (fuera de cualquier marcador) mientras se está en
  /// modo edición: agrega un punto nuevo, completa una reubicación pendiente,
  /// o cancela una conexión en curso si se tocó vacío.
  void _handleMapBackgroundTap(LatLng point) {
    if (_isEditSheetOpen) return;
    if (_editMovingId != null) {
      final id = _editMovingId!;
      setState(() => _editMovingId = null);
      _moveUnifiedPoint(id, point);
      return;
    }
    if (_editConnectFromId != null) {
      setState(() {
        _editConnectFromId = null;
        _editConnectFromPos = null;
      });
      return;
    }
    if (_isEditMode) {
      _showAddPointSheet(point);
    }
  }

  /// Toque sobre un punto EXISTENTE (POI o nodo de corredor) mientras se está
  /// en modo edición o completando una conexión.
  void _handleEditTapOnPoint({
    required String id,
    required String name,
    required double lat,
    required double lng,
    required bool hasPlace,
  }) {
    if (_isEditSheetOpen) return;
    if (_editConnectFromId != null) {
      final fromId = _editConnectFromId!;
      final fromPos = _editConnectFromPos!;
      setState(() {
        _editConnectFromId = null;
        _editConnectFromPos = null;
      });
      if (fromId == id) return; // tocó el mismo punto de nuevo → cancelar
      _connectNodes(
        fromId: fromId,
        fromPos: fromPos,
        toId: id,
        toPos: LatLng(lat, lng),
      );
      return;
    }
    _showEditPointSheet(id: id, name: name, lat: lat, lng: lng, hasPlace: hasPlace);
  }

  void _showAddPointSheet(LatLng at) {
    final cs = Theme.of(context).colorScheme;
    final nameController = TextEditingController();
    var selectedType = _editPointTypes.first;
    setState(() => _isEditSheetOpen = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          // Con tantos tipos, la lista de chips ya no cabe siempre en
          // pantallas chicas (o con el teclado abierto) — scroll en vez de
          // desbordar.
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nuevo punto',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('Sede: ${_venue.label}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej. Cancha 3, Entrada Norte...',
                ),
              ),
              const SizedBox(height: 20),
              Text('TIPO',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _editPointTypes.map((t) {
                  final selected = identical(t, selectedType);
                  return ChoiceChip(
                    label: Text(t.label, style: const TextStyle(fontSize: 12)),
                    avatar: Icon(t.icon,
                        size: 16, color: selected ? cs.onPrimary : cs.primary),
                    selected: selected,
                    selectedColor: cs.primary,
                    onSelected: (_) => setSheetState(() => selectedType = t),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(ctx);
                    await _createUnifiedPoint(
                        name: name, position: at, typeInfo: selectedType);
                  },
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Guardar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isEditSheetOpen = false);
    });
  }

  void _showEditPointSheet({
    required String id,
    required String name,
    required double lat,
    required double lng,
    required bool hasPlace,
  }) {
    final cs = Theme.of(context).colorScheme;
    setState(() => _isEditSheetOpen = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_rounded, color: cs.primary),
                title: const Text('Cambiar nombre'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final newName = await _promptRename(name);
                  if (newName != null && newName.isNotEmpty) {
                    _renameUnifiedPoint(id: id, name: newName, hasPlace: hasPlace);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.open_with_rounded, color: cs.primary),
                title: const Text('Mover'),
                subtitle: const Text('Toca el mapa donde quieres reubicarlo'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _editMovingId = id);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.timeline_rounded, color: cs.primary),
                title: const Text('Conectar a otro punto'),
                subtitle: const Text('Traza un camino caminable hasta otro punto'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editConnectFromId = id;
                    _editConnectFromPos = LatLng(lat, lng);
                  });
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await _confirmDelete(name);
                  if (confirmed) _deleteUnifiedPoint(id: id, hasPlace: hasPlace);
                },
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isEditSheetOpen = false);
    });
  }

  Future<String?> _promptRename(String currentName) async {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: currentName);
    setState(() => _isEditSheetOpen = true);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Cambiar nombre'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isEditSheetOpen = false);
    }
  }

  Future<void> _renameUnifiedPoint({
    required String id,
    required String name,
    required bool hasPlace,
  }) async {
    final zoneId = _venue.id;
    try {
      await ref.read(venueGraphRepositoryProvider).renameNode(zoneId, id, name);
    } catch (_) {}
    if (hasPlace) {
      try {
        await ref.read(placeRepositoryProvider).renamePlace(zoneId, id, name);
      } catch (_) {}
    }
  }

  Future<bool> _confirmDelete(String name) async {
    final cs = Theme.of(context).colorScheme;
    setState(() => _isEditSheetOpen = true);
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('¿Eliminar punto?'),
          content: Text('Se eliminará "$name" permanentemente, junto con sus conexiones.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      return result ?? false;
    } finally {
      if (mounted) setState(() => _isEditSheetOpen = false);
    }
  }

  Future<void> _createUnifiedPoint({
    required String name,
    required LatLng position,
    required _EditPointTypeInfo typeInfo,
  }) async {
    if (_isEditSaving) return;
    setState(() => _isEditSaving = true);
    final zoneId = _venue.id;
    final id = _uuid.v4();
    try {
      final node = CampusNode(
        id: id,
        zoneId: zoneId,
        name: name,
        aliases: const [],
        type: typeInfo.nodeType,
        lat: position.latitude,
        lng: position.longitude,
        floor: 0,
        accessible: true,
        description: '',
      );
      await ref.read(venueGraphRepositoryProvider).createNode(node);

      if (typeInfo.placeType != null) {
        final place = PlaceNode(
          id: id,
          zoneId: zoneId,
          name: name,
          latitude: position.latitude,
          longitude: position.longitude,
          type: typeInfo.placeType!,
          accessibilityLevel: 'alto',
        );
        await ref.read(placeRepositoryProvider).createPlace(place);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('"$name" agregado.'),
              backgroundColor: Colors.green.shade700),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al guardar: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isEditSaving = false);
    }
  }

  /// Reubica un punto. Intenta mover tanto el nodo del grafo como el pin de
  /// POI (si existe) — no todos los puntos existentes tienen ambos, así que
  /// los fallos de "documento no existe" en cualquiera de los dos se ignoran
  /// a propósito.
  Future<void> _moveUnifiedPoint(String id, LatLng newPos) async {
    final zoneId = _venue.id;
    try {
      await ref.read(venueGraphRepositoryProvider).moveNode(
            zoneId,
            id,
            lat: newPos.latitude,
            lng: newPos.longitude,
          );
    } catch (_) {}
    try {
      await ref.read(placeRepositoryProvider).movePlace(
            zoneId,
            id,
            lat: newPos.latitude,
            lng: newPos.longitude,
          );
    } catch (_) {}
  }

  Future<void> _deleteUnifiedPoint({
    required String id,
    required bool hasPlace,
  }) async {
    final zoneId = _venue.id;
    try {
      await ref.read(venueGraphRepositoryProvider).deleteNode(zoneId, id);
    } catch (_) {}
    if (hasPlace) {
      try {
        await ref.read(placeRepositoryProvider).deletePlace(zoneId, id);
      } catch (_) {}
    }
  }

  Future<void> _connectNodes({
    required String fromId,
    required LatLng fromPos,
    required String toId,
    required LatLng toPos,
  }) async {
    final distance = Geolocator.distanceBetween(
      fromPos.latitude,
      fromPos.longitude,
      toPos.latitude,
      toPos.longitude,
    );
    final edge = CampusEdge(
      zoneId: _venue.id,
      from: fromId,
      to: toId,
      distance: distance,
      accessible: true,
      direction: 'Continúa por el camino.',
    );
    try {
      await ref.read(venueGraphRepositoryProvider).createEdge(edge);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Conexión creada.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al conectar: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Escuchar cambios de tema global para regenerar marcadores con nuevos colores
    // (solo aplica a los iconos BitmapDescriptor de GoogleMap; en desktop los
    // marcadores de flutter_map se reconstruyen solos en cada build)
    ref.listen(themeProvider, (_, __) {
      if (_isDesktop) return;
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
          final distanceToVenue = Geolocator.distanceBetween(
            latLng.latitude, latLng.longitude,
            _venueCenter.latitude, _venueCenter.longitude,
          );
          if (distanceToVenue < _venueRadiusMeters) {
            _panCamera(latLng, zoom: 17.5);
          } else {
            _panCamera(_venueCenter, zoom: 17.0);
            _showOutsideVenueSnackBar();
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
        _panCamera(LatLng(next.currentNode!.lat, next.currentNode!.lng));
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

    // Lugares filtrados → reconstruir marcadores (solo GoogleMap; en desktop
    // los marcadores de flutter_map se derivan directo del provider en build)
    ref.listen<List<PlaceNode>>(filteredPlacesProvider, (_, next) {
      if (!_isDesktop) _rebuildMarkers(next);
    });

    final isDark = ref.watch(mapThemeProvider) == 'dark';

    // Grafo en línea (Firestore) de la sede actual — solo se suscribe
    // mientras el admin está en modo edición, para no gastar lecturas/
    // listeners de Firestore en usuarios normales que solo navegan.
    final editNodes = _isEditMode
        ? (ref.watch(nodesStreamProvider(_venue.id)).value ??
            const <CampusNode>[])
        : const <CampusNode>[];
    final editEdges = _isEditMode
        ? (ref.watch(edgesStreamProvider(_venue.id)).value ??
            const <CampusEdge>[])
        : const <CampusEdge>[];
    final editNodesById = {for (final n in editNodes) n.id: n};

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      floatingActionButton: _buildFABs(),
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: Stack(
        children: [
          // ── Mapa (Google Maps en Android/iOS/Web, flutter_map en desktop) ──
          // El punto azul del usuario se mueve vía _userPosNotifier dentro de
          // este ValueListenableBuilder para que solo el mapa se redibuje en
          // cada frame de GPS — el resto de la pantalla (botones, banners)
          // vive fuera y no se ve afectado.
          RepaintBoundary(
            child: _isDesktop
                ? _buildDesktopMap(isDark, editNodes, editEdges, editNodesById)
                : ValueListenableBuilder<LatLng?>(
                    valueListenable: _userPosNotifier,
                    builder: (context, userPos, _) {
                      final markers = {
                        ..._googleMarkers,
                        if (_isEditMode)
                          for (final node in editNodes)
                            if (node.type == NodeType.corridor)
                              Marker(
                                markerId: MarkerId('editnode_${node.id}'),
                                position: LatLng(node.lat, node.lng),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueViolet),
                                onTap: () => _handleEditTapOnPoint(
                                  id: node.id,
                                  name: node.name,
                                  lat: node.lat,
                                  lng: node.lng,
                                  hasPlace: false,
                                ),
                              ),
                        if (userPos != null && _userIconCache != null)
                          Marker(
                            markerId: const MarkerId('user_location'),
                            position: userPos,
                            icon: _userIconCache!,
                            zIndexInt: 10,
                            anchor: const Offset(0.5, 0.5),
                          ),
                      };
                      final polylines = {
                        ..._googlePolylines,
                        if (_isEditMode)
                          for (final edge in editEdges)
                            if (editNodesById[edge.from] != null &&
                                editNodesById[edge.to] != null)
                              Polyline(
                                polylineId:
                                    PolylineId('editedge_${edge.docId}'),
                                points: [
                                  LatLng(editNodesById[edge.from]!.lat,
                                      editNodesById[edge.from]!.lng),
                                  LatLng(editNodesById[edge.to]!.lat,
                                      editNodesById[edge.to]!.lng),
                                ],
                                color: const Color(0xFFFFAB00),
                                width: 3,
                                patterns: [PatternItem.dash(12), PatternItem.gap(8)],
                              ),
                      };
                      return GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _mapInitialCenter,
                          zoom: _mapInitialZoom,
                        ),
                        onMapCreated: (controller) {
                          _googleMapController = controller;
                          _initializeGpsAndCenter();
                          _rebuildMarkers(ref.read(filteredPlacesProvider));
                        },
                        onTap: _handleMapBackgroundTap,
                        onCameraMove: (pos) {
                          _currentZoom = pos.zoom;
                          if (_isTrackingActive && !_isProgrammaticCameraMove) {
                            setState(() => _isTrackingActive = false);
                          }
                        },
                        onCameraIdle: () {
                          _isProgrammaticCameraMove = false;
                        },
                        markers: markers,
                        polylines: polylines,
                        style: _currentMapStyle,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                        rotateGesturesEnabled: false,
                        cameraTargetBounds: CameraTargetBounds(_cameraBounds),
                        minMaxZoomPreference:
                            const MinMaxZoomPreference(13, 20),
                        mapType: MapType.normal,
                      );
                    },
                  ),
          ),
          // ── Botón para volver a Inicio ─────────────────────────
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildRoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Volver a Inicio',
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.home),
                ),
              ),
            ),
          ),
          // ── Botón de cambio de tema (antes vivía en el AppBar) ─
          Positioned(
            top: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildThemeToggle(isDark),
              ),
            ),
          ),
          // ── Banner de modo edición (admin, Fase 2) ─────────────
          if (_isEditMode)
            Positioned(
              top: 0, left: 16, right: 16,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 76),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFAB00),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_location_alt_rounded,
                            color: Color(0xFF0D1B2A), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _editConnectFromId != null
                                ? 'Toca el segundo punto para conectar'
                                : _editMovingId != null
                                    ? 'Toca el mapa donde quieres mover el punto'
                                    : 'MODO EDICIÓN — toca el mapa para agregar un punto',
                            style: const TextStyle(
                                color: Color(0xFF0D1B2A),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5),
                          ),
                        ),
                        if (_editConnectFromId != null || _editMovingId != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              _editConnectFromId = null;
                              _editConnectFromPos = null;
                              _editMovingId = null;
                            }),
                            child: const Icon(Icons.close_rounded,
                                color: Color(0xFF0D1B2A), size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // ── Barra de navegacion activa ────────────────────────
          if (_isNavigating)
            Positioned(
              top: 0, left: 16, right: 16,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
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
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Mapa alterno para desktop (flutter_map + tiles OSM cacheados)
  // ──────────────────────────────────────────────────────────

  Widget _buildDesktopMap(
    bool isDark,
    List<CampusNode> editNodes,
    List<CampusEdge> editEdges,
    Map<String, CampusNode> editNodesById,
  ) {
    final places = ref.watch(filteredPlacesProvider);

    final tileLayer = fm.TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'mx.edu.tecnm.colima.navia',
      maxZoom: 19,
      errorTileCallback: (tile, error, stack) {
        debugPrint('MapScreen (desktop): error de tile → $error');
      },
    );

    return fm.FlutterMap(
      mapController: _flutterMapController,
      options: fm.MapOptions(
        initialCenter: _toLL(_mapInitialCenter),
        initialZoom: _mapInitialZoom,
        minZoom: 13,
        maxZoom: 20,
        cameraConstraint: fm.CameraConstraint.contain(
          bounds: fm.LatLngBounds(
            _toLL(LatLng(_cameraBounds.southwest.latitude,
                _cameraBounds.southwest.longitude)),
            _toLL(LatLng(_cameraBounds.northeast.latitude,
                _cameraBounds.northeast.longitude)),
          ),
        ),
        onMapReady: () => _initializeGpsAndCenter(),
        onTap: (tapPosition, point) => _handleMapBackgroundTap(
            LatLng(point.latitude, point.longitude)),
        onPositionChanged: (position, hasGesture) {
          if (position.zoom != null) _currentZoom = position.zoom!;
          if (hasGesture) {
            if (_isTrackingActive) {
              setState(() => _isTrackingActive = false);
            }
          }
        },
      ),
      children: [
        isDark
            ? ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  -1, 0, 0, 0, 255, //
                  0, -1, 0, 0, 255, //
                  0, 0, -1, 0, 255, //
                  0, 0, 0, 1, 0, //
                ]),
                child: tileLayer,
              )
            : tileLayer,
        fm.PolylineLayer(
          polylines: [
            ..._googlePolylines.map((p) => fm.Polyline(
                  points: p.points.map(_toLL).toList(),
                  color: const Color(0xFF38BDF8),
                  strokeWidth: 6,
                )),
            if (_isEditMode)
              for (final edge in editEdges)
                if (editNodesById[edge.from] != null &&
                    editNodesById[edge.to] != null)
                  fm.Polyline(
                    points: [
                      _toLL(LatLng(editNodesById[edge.from]!.lat,
                          editNodesById[edge.from]!.lng)),
                      _toLL(LatLng(editNodesById[edge.to]!.lat,
                          editNodesById[edge.to]!.lng)),
                    ],
                    color: const Color(0xFFFFAB00),
                    strokeWidth: 3,
                  ),
          ],
        ),
        fm.MarkerLayer(
          markers: [
            for (final place in places)
              fm.Marker(
                point: ll.LatLng(place.latitude, place.longitude),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () {
                    if (_isEditMode || _editConnectFromId != null) {
                      _handleEditTapOnPoint(
                        id: place.id,
                        name: place.name,
                        lat: place.latitude,
                        lng: place.longitude,
                        hasPlace: true,
                      );
                    } else {
                      ref.read(selectedPlaceProvider.notifier).state = place;
                    }
                  },
                  child: _DesktopPoiIcon(place: place),
                ),
              ),
            if (_isEditMode)
              for (final node in editNodes)
                if (node.type == NodeType.corridor)
                  fm.Marker(
                    point: ll.LatLng(node.lat, node.lng),
                    width: 22,
                    height: 22,
                    child: GestureDetector(
                      onTap: () => _handleEditTapOnPoint(
                        id: node.id,
                        name: node.name,
                        lat: node.lat,
                        lng: node.lng,
                        hasPlace: false,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFAB00),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
        // Capa aparte y reactiva solo para el punto del usuario: así el
        // marcador se puede mover en cada frame de GPS sin reconstruir el
        // tile layer ni los marcadores de POIs (que no cambian con el GPS).
        ValueListenableBuilder<LatLng?>(
          valueListenable: _userPosNotifier,
          builder: (context, userPos, _) {
            if (userPos == null) return const SizedBox.shrink();
            return fm.MarkerLayer(
              markers: [
                fm.Marker(
                  point: _toLL(userPos),
                  width: 30,
                  height: 30,
                  child: const _DesktopUserIcon(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Icono de POI para el mapa alterno de escritorio (flutter_map). Replica el
/// estilo de los marcadores de GoogleMap sin depender de BitmapDescriptor/
/// Canvas, que solo tiene sentido junto al plugin nativo de Android/iOS/Web.
class _DesktopPoiIcon extends StatelessWidget {
  final PlaceNode place;
  const _DesktopPoiIcon({required this.place});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCafe = place.type.toLowerCase() == 'cafetería';
    final isBuilding = place.type.toLowerCase() == 'edificio';

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

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        border: Border.all(color: cs.primary.withValues(alpha: 0.7), width: 2),
        boxShadow: [
          BoxShadow(color: cs.primary.withValues(alpha: 0.15), blurRadius: 6),
        ],
      ),
      alignment: Alignment.center,
      child: letter.isNotEmpty
          ? Text(
              letter,
              style: TextStyle(
                color: cs.primary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            )
          : Icon(
              isCafe ? Icons.local_cafe_rounded : Icons.place_rounded,
              color: isCafe ? const Color(0xFFFFB020) : cs.primary,
              size: 18,
            ),
    );
  }
}

/// Punto de ubicación del usuario en el mapa alterno de escritorio.
class _DesktopUserIcon extends StatelessWidget {
  const _DesktopUserIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFAB00),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFAB00).withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

/// Tipos de punto que el editor de administrador puede crear. Cada uno se
/// traduce en un [CampusNode] (para que el punto sea parte del grafo
/// caminable y las rutas puedan pasar por/hacia él) y, salvo "Corredor", en
/// un [PlaceNode] con el mismo id (para que además aparezca como pin
/// tocable en el mapa) — ver [_MapScreenState._createUnifiedPoint].
class _EditPointTypeInfo {
  final String label;
  final IconData icon;

  /// `null` = punto de solo-ruta (corredor/intersección), sin pin visible.
  final String? placeType;
  final NodeType nodeType;

  const _EditPointTypeInfo(this.label, this.icon, this.placeType, this.nodeType);
}

const List<_EditPointTypeInfo> _editPointTypes = [
  _EditPointTypeInfo('Edificio', Icons.apartment_rounded, 'Edificio', NodeType.building),
  _EditPointTypeInfo('Cancha / Área deportiva', Icons.sports_soccer_rounded, 'Cancha', NodeType.area),
  // Salud y logística — lo más consultado en un evento masivo, van primero.
  _EditPointTypeInfo('Primeros auxilios', Icons.medical_services_rounded, 'Primeros Auxilios', NodeType.service),
  _EditPointTypeInfo('Hidratación', Icons.water_drop_rounded, 'Hidratación', NodeType.service),
  _EditPointTypeInfo('Baños', Icons.wc_rounded, 'Baños', NodeType.service),
  _EditPointTypeInfo('Vestidores', Icons.checkroom_rounded, 'Vestidores', NodeType.service),
  _EditPointTypeInfo('Cafetería / Comida', Icons.restaurant_rounded, 'Cafetería', NodeType.service),
  _EditPointTypeInfo('Podio / Premiación', Icons.emoji_events_rounded, 'Podio', NodeType.area),
  _EditPointTypeInfo('Estacionamiento', Icons.local_parking_rounded, 'Estacionamiento', NodeType.service),
  _EditPointTypeInfo('Transporte / Punto de abordaje', Icons.directions_bus_rounded, 'Transporte', NodeType.service),
  _EditPointTypeInfo('Entrada / Acceso', Icons.meeting_room_rounded, 'Entrada', NodeType.entrance),
  _EditPointTypeInfo('Registro / Acreditación', Icons.how_to_reg_rounded, 'Registro', NodeType.service),
  _EditPointTypeInfo('Seguridad', Icons.security_rounded, 'Seguridad', NodeType.service),
  _EditPointTypeInfo('Información', Icons.info_rounded, 'Información', NodeType.service),
  _EditPointTypeInfo('Corredor / Intersección (solo ruta, sin pin visible)',
      Icons.timeline_rounded, null, NodeType.corridor),
];
