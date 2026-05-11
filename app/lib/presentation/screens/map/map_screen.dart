import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:sinait/presentation/widgets/bottom_nav.dart';
import 'package:sinait/data/models/place_node.dart';
import 'package:sinait/data/models/campus_node.dart';
import 'package:sinait/presentation/screens/map/providers/map_providers.dart';
import 'package:sinait/core/constants/campus_locations.dart';
import 'package:sinait/data/providers/navigation_provider.dart';
import 'package:sinait/data/providers/settings_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  List<Polyline> _polylines = [];
  LatLng? _currentPosition;
  bool _centeredOnUser = false; // se vuelve true cuando el GPS centra el mapa
  bool _gpsInitDone = false;   // true cuando _initializeGpsAndCenter() termina

  // ── Interpolación suave del marcador GPS ──────────────────────────────
  late final AnimationController _posAnimController;
  LatLng? _previousPosition;   // posición GPS anterior (inicio de la tween)
  LatLng? _displayPosition;    // posición renderizada (interpolada)

  // ── Modo de Seguimiento Activo ────────────────────────────────────────
  bool _isTrackingActive = false; // cámara sigue al usuario
  Timer? _routeRecalcTimer;       // debounce para recálculo de ruta

  // Coordenadas iniciales (TecNM Campus Colima)
  static const LatLng _initialPosition =
      LatLng(CampusLocations.centerLat, CampusLocations.centerLng);

  // TTS
  final FlutterTts _flutterTts = FlutterTts();
  LatLng? _currentMapCenter;
  Timer? _debounceTimer;

  // STT
  late stt.SpeechToText _speechToText;
  bool _isListening = false;
  String _lastRecognizedWords = '';

  // Navigation state for Arrival Logic
  LatLng? _destinationLatLng;
  bool _isNavigating = false;

  // Dev Panel State
  final List<String> _ttsHistory = [];
  static const bool _isSimulatingLocation = false;

  // Coordenadas dinámicas para el inicio
  late LatLng _mapInitialCenter;
  late double _mapInitialZoom;
  bool _initializedWithArgs = false;

  @override
  void initState() {
    super.initState();
    _mapInitialCenter = _initialPosition;
    _mapInitialZoom = 17.0;

    // AnimationController para interpolar la posición del marcador GPS.
    // Duración = ventana de suavizado entre actualizaciones GPS (~800ms).
    _posAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_onPositionAnimTick);

    _initTts();
    _initStt();
    // NOTA: _requestLocationPermission() se invoca dentro de
    // _initializeGpsAndCenter() cuando el mapa está listo (onMapReady).
    // No se llama aquí para evitar diálogos antes de que el mapa exista.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync map theme from settings
    final settings = ref.read(settingsProvider);
    ref.read(mapThemeProvider.notifier).state = settings.highContrast ? 'dark' : 'light';

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

      // Active route logic
      final navState = ref.read(navigationProvider);
      if (navState.activeRoute != null) {
        final points = navState.activeRoute!.steps.map((s) => LatLng(s.node.lat, s.node.lng)).toList();
        Future.microtask(() {
          setState(() {
            _polylines = [
              Polyline(points: points, color: const Color(0xFF00E5FF), strokeWidth: 6)
            ];
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
        // If they manually set their location but haven't started a route yet
        if (_mapInitialCenter == _initialPosition) {
           _mapInitialCenter = LatLng(navState.currentNode!.lat, navState.currentNode!.lng);
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
    setState(() {
      _ttsHistory.insert(0,
          "${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second} - $text");
      if (_ttsHistory.length > 10) _ttsHistory.removeLast();
    });
    // Solo hablar si la navegación asistida está activada
    final voiceEnabled = ref.read(settingsProvider).voiceEnabled;
    if (voiceEnabled) {
      _flutterTts.speak(text);
    }
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
    _mapController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────
  //  GPS: permisos, servicio habilitado y centrado inicial
  // ──────────────────────────────────────────────────────────

  /// Verifica permisos de ubicación y estado del servicio GPS.
  /// Muestra diálogos profesionales si el GPS está apagado o los
  /// permisos están denegados permanentemente.
  Future<bool> _requestLocationPermission() async {
    // 1. ¿El servicio de ubicación está activo?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) await _showGpsDisabledDialog();
      return false;
    }

    // 2. Verificar / solicitar permisos
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // El usuario rechazó el permiso esta vez
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.location_off_rounded, color: Color(0xFF0D1B2A), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Permiso de ubicación denegado. Algunas funciones estarán limitadas.',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0D1B2A)),
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
      // Permisos denegados permanentemente → abrir ajustes de la app
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0D1B2A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            icon: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_disabled_rounded, color: Color(0xFFFF5252), size: 40),
            ),
            title: const Text(
              'Permiso de Ubicación Requerido',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
            ),
            content: const Text(
              'Los permisos de ubicación han sido denegados permanentemente. '
              'Para usar la navegación en el campus, abre los ajustes de la aplicación y habilítalos manualmente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Abrir Ajustes', style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: const Color(0xFF0D1B2A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

  /// Diálogo profesional cuando el servicio GPS está desactivado.
  Future<void> _showGpsDisabledDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.gps_off_rounded, color: Colors.white, size: 36),
        ),
        title: const Text(
          'GPS Desactivado',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Para brindarte la mejor experiencia de navegación en el campus, SINAIT necesita acceder a tu ubicación en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFF00E5FF), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'También puedes navegar escaneando los códigos QR de los pasillos.',
                      style: TextStyle(color: Color(0xFF90CAF9), fontSize: 12, height: 1.4),
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
            child: const Text('Continuar sin GPS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.gps_fixed_rounded, size: 18),
            label: const Text('Activar GPS', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF0D1B2A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

  /// Llamado cuando el mapa termina de crearse (onMapReady).
  /// Flujo determinístico:
  ///  1. Verifica permisos / servicio GPS → diálogos profesionales si falla.
  ///  2. Obtiene la posición GPS actual (con timeout).
  ///  3. Mueve la cámara a esa posición.
  ///  4. Marca _gpsInitDone para que el stream-listener sepa que puede
  ///     tomar el control del centrado si fuera necesario.
  Future<void> _initializeGpsAndCenter() async {
    try {
      // Si ya se centró por argumentos de ruta o navegación activa, no interferir.
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
        setState(() {
          _currentPosition = latLng;
        });

        // Solo centrar si aún no se ha centrado (evita race-condition con el stream)
        if (!_centeredOnUser) {
          _centeredOnUser = true;
          _mapController.move(latLng, 17.5);
        }
      } on TimeoutException {
        debugPrint('GPS: timeout al obtener posición inicial — se usará el stream.');
      } on LocationServiceDisabledException {
        debugPrint('GPS: servicio desactivado durante getCurrentPosition.');
      } catch (e) {
        debugPrint('GPS: error al obtener posición inicial: $e');
      }
    } finally {
      // Siempre marcar como terminado para desbloquear el stream-listener.
      _gpsInitDone = true;
    }
  }

  // Centra el mapa en la posición actual y activa el seguimiento.
  void _centerOnUser() {
    final navState = ref.read(navigationProvider);
    LatLng? targetPos;
    if (navState.currentNode != null) {
      targetPos = LatLng(navState.currentNode!.lat, navState.currentNode!.lng);
    } else if (_displayPosition != null) {
      targetPos = _displayPosition;
    } else if (_currentPosition != null) {
      targetPos = _currentPosition;
    }

    if (targetPos != null) {
      _mapController.move(targetPos, 17.5);
      setState(() => _isTrackingActive = true);
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Interpolación GPS → marcador suave (sin saltos)
  // ──────────────────────────────────────────────────────────

  /// Llamado cada vez que llega una nueva posición GPS cruda.
  /// Inicia la tween desde la posición anterior a la nueva.
  void _onNewGpsPosition(LatLng newPos) {
    _previousPosition = _displayPosition ?? _currentPosition ?? newPos;
    setState(() => _currentPosition = newPos);

    // Reiniciar la animación de interpolación
    _posAnimController.forward(from: 0.0);

    // Programar re-snap a grafo si hay navegación activa
    if (_isNavigating) _scheduleRouteRecalc(newPos);
  }

  /// Tick del AnimationController: interpola lat/lng con curva suave.
  void _onPositionAnimTick() {
    if (_previousPosition == null || _currentPosition == null) return;

    final t = Curves.easeOutCubic.transform(_posAnimController.value);
    final lat = _previousPosition!.latitude +
        (_currentPosition!.latitude - _previousPosition!.latitude) * t;
    final lng = _previousPosition!.longitude +
        (_currentPosition!.longitude - _previousPosition!.longitude) * t;

    final interpolated = LatLng(lat, lng);

    setState(() => _displayPosition = interpolated);

    // Modo seguimiento activo: cámara persigue al usuario
    if (_isTrackingActive) {
      _mapController.move(interpolated, _mapController.camera.zoom);
    }
  }

  /// Debounce para recalcular la ruta cuando el GPS se mueve durante
  /// una navegación activa. Usa la posición interpolada para snap al
  /// nodo más cercano del grafo y relanzar Dijkstra.
  void _scheduleRouteRecalc(LatLng rawPos) {
    _routeRecalcTimer?.cancel();
    _routeRecalcTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || !_isNavigating || _destinationLatLng == null) return;

      final navService = ref.read(navigationServiceProvider);
      final graph = navService.graph;
      if (graph == null) return;

      // Usar la posición interpolada actual para mayor suavidad
      final snapPos = _displayPosition ?? rawPos;

      // Encontrar el corredor/entrada más cercano a la posición GPS
      final corridors = graph.nodes.values
          .where((n) => n.type == NodeType.corridor || n.type == NodeType.entrance)
          .toList();
      final nearest = _closestNodeTo(corridors, snapPos, maxDistanceM: 100);
      if (nearest == null) return;

      // Solo recalcular si el nodo cambió
      if (nearest.id == navService.currentNodeId) return;

      // Encontrar nodo destino
      final destNode = _closestNodeTo(graph.nodes.values.toList(), _destinationLatLng!);
      if (destNode == null) return;

      final route = navService.calculateRouteById(nearest.id, destNode.id);
      if (route != null) {
        final notifier = ref.read(navigationProvider.notifier);
        notifier.setPosition(nearest.id);
        notifier.navigateTo(destNode.id);

        final points = route.steps.map((s) => LatLng(s.node.lat, s.node.lng)).toList();
        setState(() {
          _polylines = [
            Polyline(points: points, color: const Color(0xFF00E5FF), strokeWidth: 6),
          ];
        });
      }
    });
  }

  /// Marcador del usuario con anillo de precisión pulsante.
  Marker _buildUserMarker(LatLng position) {
    // Anillo de precisión GPS (animación sutil de escala)
    final pulse = 1.0 + 0.08 * math.sin(
      DateTime.now().millisecondsSinceEpoch / 600.0,
    );

    return Marker(
      point: position,
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anillo de precisión pulsante
          Transform.scale(
            scale: pulse,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFAB00).withValues(alpha: 0.12),
                border: Border.all(
                  color: const Color(0xFFFFAB00).withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
            ),
          ),
          // Punto central del usuario
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFFFAB00),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFAB00).withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(
              Icons.person_pin_circle_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          // Indicador de seguimiento activo
          if (_isTrackingActive)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _currentMapCenter = camera.center;
    // Gesto del usuario rompe el seguimiento automático
    if (hasGesture && _isTrackingActive) {
      setState(() => _isTrackingActive = false);
    }
    if (hasGesture) {
      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 600), () {
        _announceNearestPlace(_currentMapCenter!);
      });
    }
  }

  void _announceNearestPlace(LatLng center) {
    final placesAsyncValue = ref.read(placesStreamProvider);

    placesAsyncValue.whenData((places) {
      if (places.isEmpty) return;

      PlaceNode? nearestPlace;
      double minDistance = double.infinity;

      for (var place in places) {
        final distance = Geolocator.distanceBetween(
          center.latitude,
          center.longitude,
          place.latitude,
          place.longitude,
        );

        if (distance < minDistance) {
          minDistance = distance;
          nearestPlace = place;
        }
      }

      if (nearestPlace != null && minDistance < 150) {
        _flutterTts.stop();
        _speak('Viendo zona cerca de: ${nearestPlace.name}');
      }
    });
  }

  // --- STT Logic ---
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
        _lastRecognizedWords = result.recognizedWords;
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
    debugPrint("Comando recibido: $lowerText");

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
          .trim();

      if (searchTarget.isEmpty) return;

      final placesAsync = ref.read(placesStreamProvider);
      placesAsync.whenData((places) {
        PlaceNode? bestMatch;
        
        String removeAccents(String s) {
          return s.replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u');
        }
        
        final normalizedSearch = removeAccents(searchTarget);

        for (var place in places) {
          final normalizedName = removeAccents(place.name.toLowerCase());
          final normalizedType = removeAccents(place.type.toLowerCase());

          if (normalizedName.contains(normalizedSearch) ||
              normalizedType.contains(normalizedSearch)) {
            bestMatch = place;
            break;
          }
        }

        if (bestMatch != null) {
          calculateAccessibleRoute(
              LatLng(bestMatch.latitude, bestMatch.longitude),
              bestMatch.name);
        } else {
          _speak(
              'No encontré el lugar: $searchTarget. Intenta decirlo de otra forma.');
        }
      });
    }
  }

  void _showAccessibleBottomSheet(PlaceNode place) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D1B2A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 5),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
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
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                    ),
                    child: Icon(
                      place.type.toLowerCase().contains('cafetería') 
                          ? Icons.coffee_rounded 
                          : Icons.business_rounded,
                      color: const Color(0xFF00E5FF),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          place.type.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'DETALLES DE ACCESIBILIDAD',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoBadge(
                    Icons.accessible_rounded,
                    'Nivel: ${place.accessibilityLevel.toUpperCase()}',
                    place.accessibilityLevel.toLowerCase() == 'alto' ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildInfoBadge(
                    Icons.map_rounded,
                    'Piso: Planta Baja',
                    Colors.blueAccent,
                  ),
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.directions_walk_rounded, size: 22, color: Color(0xFF0D1B2A)),
                        label: const Text(
                          'Trazar Ruta',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0D1B2A)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          calculateAccessibleRoute(
                            LatLng(place.latitude, place.longitude),
                            place.name,
                          );
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
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.05),
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.location_on_rounded, size: 22, color: Color(0xFF00E5FF)),
                        label: const Text(
                          'Estoy Aquí',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF00E5FF)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
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
        );
      },
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
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> calculateAccessibleRoute(LatLng destination,
      [String? destinationName]) async {
    _destinationLatLng = destination;
    _isNavigating = true;

    try {
      final notifier = ref.read(navigationProvider.notifier);
      final navService = ref.read(navigationServiceProvider);
      final graph = navService.graph;

      if (graph == null) {
        _speak('El mapa aún no está listo. Intenta de nuevo.');
        return;
      }

      // 1. Encontrar el nodo destino en el grafo por coordenadas
      final destNode = _closestNodeTo(graph.nodes.values.toList(), destination);
      if (destNode == null) {
        _speak('No encontré ese lugar en el mapa.');
        return;
      }

      // 2. Determinar origen: QR escaneado tiene prioridad.
      //    Si no hay QR, usar GPS para encontrar el hall más cercano.
      String? fromId = navService.currentNodeId;

      if (fromId == null) {
        // Sin QR: intentar GPS (preferir posición interpolada)
        final gpsPos = _displayPosition ?? _currentPosition;
        if (gpsPos != null) {
          final corridors = graph.nodes.values
              .where((n) => n.type == NodeType.corridor || n.type == NodeType.entrance)
              .toList();
          final nearest = _closestNodeTo(corridors, gpsPos, maxDistanceM: 500);
          if (nearest != null) {
            fromId = nearest.id;
          }
        }

        if (fromId == null) {
          // Sin GPS ni QR: pedir escaneo
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Color(0xFF0D1B2A), size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Activa el GPS o escanea el QR del pasillo más cercano para trazar tu ruta.',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0D1B2A)),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Color(0xFF00E5FF),
                behavior: SnackBarBehavior.fixed,
                duration: Duration(seconds: 4),
              ),
            );
          }
          setState(() { _isNavigating = false; });
          return;
        }
      }

      // 3. Fijar el origen en el servicio y calcular ruta por IDs
      notifier.setPosition(fromId);
      final route = navService.calculateRouteById(fromId, destNode.id);

      if (route != null) {
        notifier.navigateTo(destNode.id);

        final List<LatLng> points =
            route.steps.map((s) => LatLng(s.node.lat, s.node.lng)).toList();

        setState(() {
          _polylines = [
            Polyline(points: points, color: const Color(0xFF00E5FF), strokeWidth: 6),
          ];
        });

        _fitBounds(points);
        _speak('Ruta trazada hacia ${destinationName ?? destNode.name}. '
            '${route.totalDistance.round()} metros.');
      } else {
        _speak('No encontré una ruta hacia ${destinationName ?? destNode.name}.');
      }
    } catch (e) {
      debugPrint('Error en ruta: $e');
      _speak('Ocurrió un error al calcular la ruta.');
    }
  }

  /// Nodo del grafo más cercano a [target]. Retorna null si el más cercano
  /// supera [maxDistanceM] metros (por defecto sin límite).
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

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlaceNode?>(selectedPlaceProvider, (previous, next) {
      if (next != null) {
        _showAccessibleBottomSheet(next);
        Future.delayed(const Duration(milliseconds: 100), () {
          ref.read(selectedPlaceProvider.notifier).state = null;
        });
      }
    });

    ref.listen<AsyncValue<Position>>(currentLocationStreamProvider,
        (previous, next) {
      next.whenData((position) {
        final latLng = LatLng(position.latitude, position.longitude);

        // Rutear a través del motor de interpolación para movimiento suave
        _onNewGpsPosition(latLng);

        // Centrar el mapa automáticamente solo la primera vez que llega GPS,
        // pero SOLO después de que _initializeGpsAndCenter haya terminado
        // para evitar una race-condition entre ambos flujos.
        if (!_centeredOnUser && _gpsInitDone) {
          _centeredOnUser = true;
          _mapController.move(latLng, 17.5);
        }

        // Detección de llegada al destino
        if (_isNavigating &&
            _destinationLatLng != null &&
            !_isSimulatingLocation) {
          final distanceToTarget = Geolocator.distanceBetween(
            latLng.latitude,
            latLng.longitude,
            _destinationLatLng!.latitude,
            _destinationLatLng!.longitude,
          );
          if (distanceToTarget <= 10.0) _handleArrival();
        }
      });
    });

    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.currentNode != previous?.currentNode && next.currentNode != null) {
        // Mover el mapa al nuevo nodo (Estoy Aquí o QR)
        _mapController.move(
          LatLng(next.currentNode!.lat, next.currentNode!.lng),
          _mapController.camera.zoom,
        );
      }
      
      if (next.activeRoute != previous?.activeRoute) {
        if (next.activeRoute != null) {
          final points = next.activeRoute!.steps.map((s) => LatLng(s.node.lat, s.node.lng)).toList();
          setState(() {
            _polylines = [
              Polyline(points: points, color: const Color(0xFF00E5FF), strokeWidth: 6)
            ];
            _isNavigating = true;
          });
        } else {
          setState(() {
            _polylines = [];
            _isNavigating = false;
          });
        }
      }
    });

    final currentTheme = ref.watch(mapThemeProvider);
    final isDark = currentTheme == 'dark';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      appBar: _buildPremiumAppBar(isDark),
      floatingActionButton: _buildFABs(isDark),
      body: Stack(
        children: [
          Consumer(
            builder: (context, ref, child) {
              final markers = ref.watch(filteredMapMarkersProvider);
              final allMarkers = [...markers];

              final navState = ref.watch(navigationProvider);
              LatLng? actualUserPos;

              // Prioridad: Si hay un nodo fijado manualmente (QR/Estoy Aquí), usar ese.
              // Si no, usar la posición INTERPOLADA para movimiento suave.
              if (navState.currentNode != null) {
                actualUserPos = LatLng(navState.currentNode!.lat, navState.currentNode!.lng);
              } else if (_displayPosition != null) {
                actualUserPos = _displayPosition;
              } else if (_currentPosition != null) {
                actualUserPos = _currentPosition;
              }

              if (actualUserPos != null) {
                allMarkers.add(_buildUserMarker(actualUserPos));
              }

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _mapInitialCenter,
                  initialZoom: _mapInitialZoom,
                  onPositionChanged: _onPositionChanged,
                  onMapReady: _initializeGpsAndCenter,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.sinait.app',
                    retinaMode: RetinaMode.isHighDensity(context),
                  ),
                  PolylineLayer(polylines: _polylines),
                  MarkerLayer(markers: allMarkers),
                ],
              );
            },
          ),
          // Gradient top overlay for filters
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    (isDark ? const Color(0xFF0D1B2A) : Colors.white).withValues(alpha: 0.95),
                    (isDark ? const Color(0xFF0D1B2A) : Colors.white).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(top: 12, left: 0, right: 0, child: _buildFiltersRow()),
          // Voice indicator
          if (_isListening)
            Positioned(
              bottom: 120, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      blurRadius: 20,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.graphic_eq, color: Color(0xFF00E5FF), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lastRecognizedWords.isEmpty ? "Escuchando..." : _lastRecognizedWords,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Navigation status bar
          if (_isNavigating)
            Positioned(
              top: 70, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2E45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_walk, color: Color(0xFF00E5FF), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Navegando en curso...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() { _isNavigating = false; _polylines = []; _destinationLatLng = null; }),
                      child: const Icon(Icons.close, color: Colors.white54, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildPremiumAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF0D1B2A) : const Color(0xFF0D1B2A),
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 36, height: 36,
            margin: const EdgeInsets.only(left: 4, right: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.5),
            ),
            child: const Icon(Icons.school_rounded, color: Color(0xFF00E5FF), size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SINAIT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2.5)),
              Text(
                _mapInitialCenter.latitude == 19.27580 
                  ? 'Plaza Sendera' 
                  : (_mapInitialCenter.latitude == 19.26691 ? 'Plaza Zentralia' : 'TecNM Campus Colima'), 
                style: const TextStyle(fontSize: 10, color: Color(0xFF90CAF9), letterSpacing: 0.5, fontWeight: FontWeight.w400)
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: const Color(0xFF00E5FF),
          ),
          onPressed: () {
            ref.read(mapThemeProvider.notifier).state = isDark ? 'light' : 'dark';
            _speak('Cambiando a modo ${isDark ? "claro" : "oscuro"}');
          },
          tooltip: 'Cambiar tema',
        ),
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1B2A), Color(0xFF1A2E45)],
          ),
        ),
      ),
    );
  }

  Widget _buildFABs(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [

          // Location button — refleja estado de seguimiento activo
          FloatingActionButton(
            heroTag: 'center_button',
            onPressed: _centerOnUser,
            backgroundColor: _isTrackingActive
                ? const Color(0xFF00E5FF)
                : const Color(0xFF1A2E45),
            elevation: _isTrackingActive ? 8 : 4,
            child: Icon(
              _isTrackingActive
                  ? Icons.gps_fixed_rounded
                  : Icons.my_location_rounded,
              color: _isTrackingActive
                  ? const Color(0xFF0D1B2A)
                  : const Color(0xFF00E5FF),
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          // Mic button with label
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
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
                      ),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? const Color(0xFFFF5252) : const Color(0xFF00E5FF)).withValues(alpha: 0.5),
                    blurRadius: _isListening ? 20 : 12,
                    spreadRadius: _isListening ? 4 : 2,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
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
        children: filters.map((filterData) {
          final filter = filterData.$1;
          final icon = filterData.$2;
          final isSelected = currentFilter.toLowerCase() == filter.toLowerCase();
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                ref.read(categoryFilterProvider.notifier).state = filter;
                _speak('Filtrando por: $filter');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : const Color(0xFF0D1B2A).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : const Color(0xFF00E5FF).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 15,
                        color: isSelected ? Colors.white : const Color(0xFF90CAF9)),
                    const SizedBox(width: 6),
                    Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF90CAF9),
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _handleArrival() {
    setState(() {
      _isNavigating = false;
      _polylines = [];
      _destinationLatLng = null;
    });
    _speak('Has llegado a tu destino. SINAIT te desea un excelente día.');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF0D1B2A), size: 24),
            SizedBox(width: 10),
            Text('¡Has llegado a tu destino!', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D1B2A))),
          ],
        ),
        backgroundColor: const Color(0xFF00E5FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
