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
import 'package:sinait/presentation/screens/vision/qr_scanner_screen.dart';

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
  final LatLng _initialPosition = const LatLng(19.261914, -103.723674);

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
    final isDark = ref.read(mapThemeProvider) == 'dark';
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place.name,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Tipo: ${place.type.toUpperCase()}  |  Accesibilidad: ${place.accessibilityLevel.toUpperCase()}',
                  style: TextStyle(
                      fontSize: 16,
                      color: isDark ? const Color(0xFFE0E0E0) : Colors.black87,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.directions_walk,
                      size: 28, color: Colors.black),
                  label: const Text(
                    'Navegar hacia aquí',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF64FFDA),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    if (_currentPosition != null) {
                      calculateAccessibleRoute(_currentPosition!,
                          LatLng(place.latitude, place.longitude), place.name);
                    }
                  },
                ),
              )
            ],
          ),
        );
      },
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
      
      final url = '$backendUrl/api/directions?origin=$originStr&destination=$destinationStr&mode=walking';
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
              color: const Color(0xFF64FFDA),
              strokeWidth: 6,
            ),
          ];
        });

        _fitBounds([origin, destination, ...polylineCoordinates]);

        final distance = json['data']['distance'] as int? ?? 0;
        _speak('Ruta trazada hacia ${destinationName ?? "destino"}. Distancia: ${(distance / 1000).toStringAsFixed(1)} km.');
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
          color: const Color(0xFF64FFDA).withOpacity(0.5),
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

    ref.listen<AsyncValue<Position>>(currentLocationStreamProvider, (previous, next) {
      next.whenData((position) {
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
              ),
            ),
          );
        });

        if (_isNavigating && _destinationLatLng != null && !_isSimulatingLocation) {
          final distanceToTarget = Geolocator.distanceBetween(
            latLng.latitude, latLng.longitude,
            _destinationLatLng!.latitude, _destinationLatLng!.longitude,
          );

          if (distanceToTarget <= 10.0) {
            _handleArrival();
          }
        }
      });
    });

    final currentTheme = ref.watch(mapThemeProvider);
    final isDark = currentTheme == 'dark';

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      drawer: _buildDevDrawer(),
      appBar: AppBar(
        title: const Text('Explorador SINAIT'),
        backgroundColor: isDark ? Colors.black87 : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              ref.read(mapThemeProvider.notifier).state = isDark ? 'light' : 'dark';
              _speak('Cambiando a modo ${isDark ? "claro" : "oscuro"}');
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen())),
          )
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'center_button',
            onPressed: _determinePosition,
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Icon(Icons.my_location, color: isDark ? const Color(0xFF64FFDA) : Colors.blue),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onLongPressStart: _startListening,
            onLongPressEnd: _stopListening,
            child: FloatingActionButton.large(
              heroTag: 'voice_button',
              onPressed: () {},
              backgroundColor: _isListening ? Colors.redAccent : (isDark ? const Color(0xFF64FFDA) : Colors.blueAccent),
              child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: isDark ? Colors.black : Colors.white, size: 40),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Consumer(
            builder: (context, ref, child) {
              final markers = ref.watch(filteredMapMarkersProvider);
              final allMarkers = [...markers];
              if (_userLocationMarker != null) allMarkers.add(_userLocationMarker!);

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
                  ),
                  PolylineLayer(polylines: _polylines),
                  MarkerLayer(markers: allMarkers),
                ],
              );
            },
          ),
          Positioned(top: 16, left: 0, right: 0, child: _buildFiltersRow()),
          if (_isListening)
            Positioned(
              bottom: 120, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                child: Text(_lastRecognizedWords.isEmpty ? "Escuchando..." : _lastRecognizedWords,
                    style: const TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.center),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    final currentFilter = ref.watch(categoryFilterProvider);
    final isDark = ref.watch(mapThemeProvider) == 'dark';
    final filters = ['Todo', 'Edificio', 'Cafetería', 'Servicios', 'Parque'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filters.map((filter) {
          final isSelected = currentFilter.toLowerCase() == filter.toLowerCase();
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              label: Text(filter),
              onPressed: () {
                ref.read(categoryFilterProvider.notifier).state = filter;
                _speak('Filtrando por: $filter');
              },
              backgroundColor: isSelected 
                  ? (isDark ? const Color(0xFF64FFDA) : Colors.blueAccent) 
                  : (isDark ? const Color(0xFF1E1E1E) : Colors.grey[200]),
              labelStyle: TextStyle(
                color: isSelected ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white : Colors.black), 
                fontWeight: FontWeight.bold
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : (isDark ? const Color(0xFF64FFDA).withOpacity(0.3) : Colors.grey[300]!),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Has llegado!'), backgroundColor: Color(0xFF64FFDA)));
  }

  Widget _buildDevDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(20.0), child: Text('PANEL DE DESARROLLO', style: TextStyle(color: Color(0xFF64FFDA), fontSize: 20, fontWeight: FontWeight.bold))),
            Expanded(child: ListView.builder(itemCount: _ttsHistory.length, itemBuilder: (context, index) => ListTile(title: Text(_ttsHistory[index], style: const TextStyle(color: Colors.white70, fontSize: 12))))),
            const Divider(color: Colors.white24),
            SwitchListTile(title: const Text('Simular Ubicación (Dev)', style: TextStyle(color: Colors.white)), value: _isSimulatingLocation, onChanged: (val) => setState(() => _isSimulatingLocation = val), activeThumbColor: const Color(0xFF64FFDA)),
          ],
        ),
      ),
    );
  }
}
