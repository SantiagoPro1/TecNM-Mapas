import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:dio/dio.dart';

import 'package:sinait/presentation/widgets/bottom_nav.dart';
import 'package:sinait/data/models/place_node.dart';
import 'package:sinait/presentation/screens/map/providers/map_providers.dart';
import 'package:sinait/core/constants/campus_locations.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  List<Polyline> _polylines = [];
  LatLng? _currentPosition;
  Marker? _userLocationMarker;

  // Coordenadas iniciales (TecNM Campus Colima)
  final LatLng _initialPosition =
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
  bool _isSimulatingLocation = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initStt();
    _determinePosition();
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
    _flutterTts.speak(text);
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
    _debounceTimer?.cancel();
    _flutterTts.stop();
    _speechToText.stop();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    final latLng = LatLng(position.latitude, position.longitude);

    setState(() {
      _currentPosition = latLng;
      _userLocationMarker = Marker(
        point: _currentPosition!,
        width: 30,
        height: 30,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      );
    });

    _mapController.move(_currentPosition!, 17.5);
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _currentMapCenter = camera.center;
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
  void _startListening(LongPressStartDetails details) async {
    _flutterTts.stop();
    if (!_speechToText.isAvailable) {
      bool available = await _speechToText.initialize();
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

  void _stopListening(LongPressEndDetails details) async {
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
        for (var place in places) {
          if (place.name.toLowerCase().contains(searchTarget) ||
              place.type.toLowerCase().contains(searchTarget)) {
            bestMatch = place;
            break;
          }
        }

        if (bestMatch != null) {
          if (_currentPosition != null) {
            calculateAccessibleRoute(
                _currentPosition!,
                LatLng(bestMatch.latitude, bestMatch.longitude),
                bestMatch.name);
          } else {
            _speak('Aún no tengo tu ubicación actual para trazar la ruta.');
          }
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
                      color: const Color(0xFF00E5FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
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
                            color: const Color(0xFF00E5FF).withOpacity(0.8),
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
              SizedBox(
                width: double.infinity,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.directions_walk_rounded, size: 28, color: Color(0xFF0D1B2A)),
                    label: const Text(
                      'Trazar Ruta Accesible',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      if (_currentPosition != null) {
                        calculateAccessibleRoute(
                          _currentPosition!,
                          LatLng(place.latitude, place.longitude),
                          place.name,
                        );
                      }
                    },
                  ),
                ),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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

  Future<void> calculateAccessibleRoute(LatLng origin, LatLng destination,
      [String? destinationName]) async {
    _destinationLatLng = destination;
    _isNavigating = true;

    try {
      const backendUrl = 'http://localhost:3000';
      final originStr = '${origin.latitude},${origin.longitude}';
      final destinationStr = '${destination.latitude},${destination.longitude}';

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));

      final url =
          '$backendUrl/api/directions?origin=$originStr&destination=$destinationStr&mode=walking';
      debugPrint('Solicitando ruta a: $url');

      final response = await dio.get(url);
      final json = response.data;

      if (json['success'] != true) throw Exception(json['error']);

      final List<dynamic> pointsList = json['data']['points'] ?? [];
      final List<LatLng> polylineCoordinates = pointsList
          .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
          .toList();

      if (polylineCoordinates.isNotEmpty) {
        setState(() {
          _polylines = [
            Polyline(
              points: polylineCoordinates,
              color: const Color(0xFF00E5FF),
              strokeWidth: 6,
            ),
          ];
        });

        _fitBounds([origin, destination, ...polylineCoordinates]);

        final distance = json['data']['distance'] as int? ?? 0;
        _speak(
            'Ruta trazada hacia ${destinationName ?? "destino"}. Distancia: ${(distance / 1000).toStringAsFixed(1)} km.');
      } else {
        _drawFallbackStraightLine(origin, destination);
      }
    } catch (e) {
      debugPrint('Error en ruta: $e');
      _drawFallbackStraightLine(origin, destination);
    }
  }

  void _drawFallbackStraightLine(LatLng origin, LatLng destination) {
    setState(() {
      _polylines = [
        Polyline(
          points: [origin, destination],
          color: const Color(0xFF00E5FF).withOpacity(0.5),
          strokeWidth: 4,
        ),
      ];
    });
    _fitBounds([origin, destination]);
    _speak('No pude calcular la ruta peatonal. Mostrando línea de guía.');
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
        setState(() {
          _currentPosition = latLng;
          _userLocationMarker = Marker(
            point: _currentPosition!,
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFAB00),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFAB00).withOpacity(0.5),
                    blurRadius: 15,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 24),
            ),
          );
        });

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
              if (_userLocationMarker != null)
                allMarkers.add(_userLocationMarker!);

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _initialPosition,
                  initialZoom: 17.0,
                  onPositionChanged: _onPositionChanged,
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
                    (isDark ? const Color(0xFF0D1B2A) : Colors.white).withOpacity(0.95),
                    (isDark ? const Color(0xFF0D1B2A) : Colors.white).withOpacity(0.0),
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
                  color: const Color(0xFF0D1B2A).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.2),
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
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
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
              color: const Color(0xFF00E5FF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1.5),
            ),
            child: const Icon(Icons.school_rounded, color: Color(0xFF00E5FF), size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('SINAIT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2.5)),
              Text('TecNM Campus Colima', style: TextStyle(fontSize: 10, color: Color(0xFF90CAF9), letterSpacing: 0.5, fontWeight: FontWeight.w400)),
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
          // Location button
          FloatingActionButton(
            heroTag: 'center_button',
            onPressed: _determinePosition,
            backgroundColor: const Color(0xFF1A2E45),
            elevation: 4,
            child: const Icon(Icons.my_location_rounded, color: Color(0xFF00E5FF), size: 26),
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
                    color: (_isListening ? const Color(0xFFFF5252) : const Color(0xFF00E5FF)).withOpacity(0.5),
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
                  color: isSelected ? null : const Color(0xFF0D1B2A).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : const Color(0xFF00E5FF).withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.35),
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
