import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/data/providers/vision_provider.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';
import 'package:navia/services/vision/camera_feed_handler.dart';
import 'package:navia/services/vision/ml_vision_service.dart';
import 'package:navia/services/vision/model_manager_service.dart';
import 'package:navia/services/vision/marker_recognizer.dart';
import 'package:navia/services/vision/models/detected_object.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// ScannerScreen - NAVIA AR con pipeline TFLite completo
// ---------------------------------------------------------------------------

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  // --- Pipeline de vision ---
  CameraFeedHandler? _feedHandler;
  TfliteObstacleDetector? _detector;
  bool _isPipelineReady = false;
  String? _pipelineError;
  bool _isInitializing = false;

  /// Future del dispose de la instancia anterior — se espera en _initPipeline
  /// para evitar crash cuando el usuario vuelve a la pantalla antes de que la
  /// cámara anterior haya terminado de liberarse.
  static Future<void>? _sPendingDispose;

  // --- Cooldown de voz ---
  DateTime _lastVoiceAt = DateTime(2000);
  static const Duration _kVoiceCooldown = Duration(seconds: 3);

  // --- Filtro de consenso temporal ---
  String? _lastAnnouncedLabel;
  int _consensusFrames = 0;
  static const int _kConsensusRequired = 2;

  // --- Perfil de aprendizaje adaptativo ---
  SharedPreferences? _prefs;
  final Map<String, int> _classFrequencies = {};
  int _sessionOpenCount = 0;

  // --- Demo ---
  static const List<_DemoPlace> _kDemoPlaces = [
    _DemoPlace('BIBLIOTECA', 'Biblioteca', Icons.menu_book_rounded),
    _DemoPlace('EDIFICIO-H', 'Centro de Computo', Icons.computer_rounded),
    _DemoPlace('CAFETERIA-NORTE', 'Cafeteria Norte', Icons.restaurant_rounded),
    _DemoPlace('CAFETERIA-SUR', 'Cafeteria Sur', Icons.local_cafe_rounded),
    _DemoPlace('EDIFICIO-D', 'Edificio D - Aulas', Icons.school_rounded),
    _DemoPlace('EDIFICIO-A', 'Edificio A - Direccion', Icons.business_rounded),
    _DemoPlace(
        'EDIFICIO-R', 'Sistemas y Computacion', Icons.developer_board_rounded),
    _DemoPlace('ENTRADA', 'Acceso Principal', Icons.door_front_door_rounded),
  ];

  CameraController? get _cameraController => _feedHandler?.controller;

  // --- Lifecycle ---

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initLearningProfile();
    _initPipeline();
    // Garantizar que voz y grafo estén listos aunque el usuario llegue aquí
    // directamente sin pasar por HomeScreen primero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(voiceProvider.notifier).initialize();
      ref.read(navigationProvider.notifier).initialize();
    });
  }

  Future<void> _initLearningProfile() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _sessionOpenCount = (_prefs!.getInt('navia_sessions_count') ?? 0) + 1;
      await _prefs!.setInt('navia_sessions_count', _sessionOpenCount);

      final keys = _prefs!.getKeys();
      for (final key in keys) {
        if (key.startsWith('navia_freq_')) {
          final className = key.replaceFirst('navia_freq_', '');
          _classFrequencies[className] = _prefs!.getInt(key) ?? 0;
        }
      }
      debugPrint('SINAIT Learning Profile: Sesión $_sessionOpenCount cargada.');
      _applyLearningToDetector();
    } catch (e) {
      debugPrint('SINAIT Learning Profile: Error cargando perfil - $e');
    }
  }

  void _applyLearningToDetector() {
    if (_detector == null) return;
    // Si ya abrimos la app varias veces y detectamos objetos escolares, 
    // adaptamos los umbrales del detector.
    if (_sessionOpenCount > 3) {
      _detector!.dynamicConfidenceThreshold = 0.25;
      debugPrint('SINAIT Learning Profile: Umbral de confianza adaptativo reducido a 0.25.');
    }
  }

  void _recordDetection(String label) {
    if (_prefs == null) return;
    final cleanLabel = label.toLowerCase();
    final count = (_classFrequencies[cleanLabel] ?? 0) + 1;
    _classFrequencies[cleanLabel] = count;
    _prefs!.setInt('navia_freq_$cleanLabel', count);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Store the async dispose future so the next instance can await it before
    // initializing its own camera (prevents "camera already in use" crashes).
    _sPendingDispose = _disposePipeline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _feedHandler?.stopStream();
      ref.read(visionProvider.notifier).pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_isPipelineReady) {
        _feedHandler?.startStream();
        ref.read(visionProvider.notifier).resume();
      }
    }
  }

  // --- Pipeline init ---

  Future<void> _initPipeline() async {
    if (_isInitializing || !mounted) return;
    _isInitializing = true;

    // Esperar a que la instancia anterior libere la cámara antes de continuar.
    final pending = _sPendingDispose;
    if (pending != null) {
      _sPendingDispose = null;
      await pending;
    }
    if (!mounted) {
      _isInitializing = false;
      return;
    }

    // Limpiar pipeline anterior si existe (fix: multiples clicks en NAVIA AR)
    await _disposePipeline();
    if (!mounted) {
      _isInitializing = false;
      return;
    }

    ref.read(visionProvider.notifier).reset();

    setState(() {
      _isPipelineReady = false;
      _pipelineError = null;
    });

    try {
      // 1. Obtener camara trasera
      final cameras = await availableCameras();
      if (!mounted) {
        _isInitializing = false;
        return;
      }
      if (cameras.isEmpty) {
        setState(() => _pipelineError = 'No se encontro camara disponible.');
        _isInitializing = false;
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // 2. Crear detector TFLite
      final detector = TfliteObstacleDetector(
        onResult: (objects) {
          if (mounted) {
            ref
                .read(visionProvider.notifier)
                .updateDetections(objects: objects);
          }
        },
        onError: (msg) {
          if (mounted) {
            ref.read(visionProvider.notifier).activateVoiceOnlyFallback(msg);
            ref.read(voiceProvider.notifier).speakAnnouncement(
                  'Modo de asistencia activado. Usando guia de voz.',
                );
          }
        },
      );

      // 3. Cargar modelo TFLite
      final modelManager = ref.read(modelManagerServiceProvider);
      final modelLoaded = await detector.initialize(modelManager);
      if (!mounted) {
        _isInitializing = false;
        return;
      }

      if (!modelLoaded) {
        setState(() =>
            _pipelineError = 'Modelo no disponible. Modo Solo Voz activo.');
      }

      // 4. Crear CameraFeedHandler con targets
      final feedHandler = CameraFeedHandler(
        camera: backCamera,
        isDetectionActive: () =>
            _isPipelineReady || ref.read(visionProvider).isActive,
        mlService: modelLoaded ? detector : null,
        targetWidth: modelLoaded ? detector.inputSizeWidth : 0,
        targetHeight: modelLoaded ? detector.inputSizeHeight : 0,
      );

      await feedHandler.initialize();
      if (!mounted) {
        await feedHandler.dispose();
        _isInitializing = false;
        return;
      }

      // 5. Guardar referencias
      _detector = detector;
      _feedHandler = feedHandler;
      _applyLearningToDetector();

      // 6. Marcar pipeline listo
      ref.read(visionProvider.notifier).markReady();
      setState(() {
        _isPipelineReady = true;
        _pipelineError = null;
      });

      // 7. Arrancar stream
      feedHandler.startStream();

      // 8. Anuncio de voz
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          ref.read(voiceProvider.notifier).speakAnnouncement(
                'INICIANDO NAVIA AR. NAVIA AR funcionando correctamente. Elige destino.',
              );
        }
      }

      debugPrint('ScannerScreen: pipeline NAVIA AR iniciado correctamente.');
    } catch (e) {
      debugPrint('ScannerScreen: error pipeline - $e');
      if (mounted) {
        setState(() => _pipelineError = 'Error al iniciar la camara: $e');
      }
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _disposePipeline() async {
    _detector?.dispose();
    _detector = null;
    await _feedHandler?.dispose();
    _feedHandler = null;
    _isPipelineReady = false;
  }

  // --- Voz con cooldown ---

  void _announceObstacle(List<DetectedObject> objects) {
    if (objects.isEmpty) return;

    final closest = objects.first;
    final labelName = closest.label.toLowerCase();

    // Filtro de Consenso: requiere 2 frames consecutivos con el mismo objeto antes de anunciar
    if (labelName != _lastAnnouncedLabel) {
      _lastAnnouncedLabel = labelName;
      _consensusFrames = 1;
      return;
    } else {
      _consensusFrames++;
      if (_consensusFrames < _kConsensusRequired) {
        return;
      }
      // Reseteamos contador para el siguiente anuncio
      _consensusFrames = 0;
    }

    // Cooldown temporal general
    final now = DateTime.now();
    if (now.difference(_lastVoiceAt) < _kVoiceCooldown) return;
    _lastVoiceAt = now;

    // Registrar en el historial de aprendizaje
    _recordDetection(labelName);

    final article = _getArticle(labelName);
    String announcement = '';

    if (labelName == 'escaleras' || labelName == 'escalones') {
      if (closest.distance == 'inmediato') {
        announcement = 'A un metro hay escaleras, cuidado.';
      } else if (closest.distance == 'cercano') {
        announcement = 'A dos metros hay escalones, precaución.';
      } else {
        announcement = 'Hay escaleras frente a ti.';
      }
    } else if (labelName == 'bardas') {
      if (closest.distance == 'inmediato') {
        announcement = 'A un metro hay una barda, cuidado.';
      } else if (closest.distance == 'cercano') {
        announcement = 'A dos metros hay una barda, precaución.';
      } else {
        announcement = 'Hay una barda frente a ti.';
      }
    } else {
      switch (closest.distance) {
        case 'inmediato':
          announcement = 'A un metro está $article ${closest.label}, cuidado.';
          break;
        case 'cercano':
          announcement = 'A dos metros hay $article ${closest.label}, precaución.';
          break;
        case 'medio':
          announcement = 'A tres metros está $article ${closest.label}.';
          break;
        case 'lejano':
          announcement = 'A unos cinco metros está $article ${closest.label}.';
          break;
        default:
          announcement = 'A unos metros está $article ${closest.label} frente a ti.';
      }
    }

    ref.read(voiceProvider.notifier).speakAnnouncement(announcement);
  }

  String _getArticle(String label) {
    final lower = label.toLowerCase();
    if (lower == 'pared' ||
        lower == 'banca' ||
        lower == 'silla' ||
        lower == 'taza' ||
        lower == 'botella' ||
        lower == 'mochila' ||
        lower == 'computadora portátil' ||
        lower == 'pantalla o proyector' ||
        lower == 'puerta' ||
        lower == 'ventana' ||
        lower == 'maceta' ||
        lower == 'camilla' ||
        lower == 'tijeras' ||
        lower.endsWith('a')) {
      return 'una';
    }
    if (lower == 'bardas' || lower == 'escaleras' || lower == 'escalones') {
      return 'unas';
    }
    return 'un';
  }

  // --- Demo BottomSheet ---

  void _showDemoSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DemoBottomSheet(
        places: _kDemoPlaces,
        onSelected: (place) {
          Navigator.of(context).pop();
          final recognizer = ref.read(markerRecognizerProvider);
          recognizer.simulateMarkerDetection(place.markerId, ref);
        },
        colorScheme: cs,
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final visionState = ref.watch(visionProvider);
    final detectedObjects = visionState.detectedObjects;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Escuchar GPS en tiempo real para actualizar la posición en el mapa/ruta
    ref.listen<AsyncValue<Position>>(currentLocationStreamProvider, (_, next) {
      next.whenData((position) {
        ref.read(navigationProvider.notifier).setPositionByCoordinates(
              position.latitude,
              position.longitude,
            );
      });
    });

    // Escuchar cambios de paso en la navegación para leerlos en voz alta
    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.currentStepIndex != previous?.currentStepIndex) {
        ref.read(voiceProvider.notifier).speakCurrentStep();
      }
    });

    // Disparar voz post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announceObstacle(detectedObjects);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview
          _buildCameraPreview(),

          // 2. Bounding Boxes
          if (_isPipelineReady && detectedObjects.isNotEmpty)
            CustomPaint(
              painter: _BoundingBoxPainter(
                objects: detectedObjects,
                frameWidth: _cameraController?.value.previewSize?.height ?? 480,
                frameHeight: _cameraController?.value.previewSize?.width ?? 640,
              ),
              child: const SizedBox.expand(),
            ),

          // 3. HUD superior
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _HudBar(visionState: visionState, colorScheme: cs),
          ),

          // 4. Barra de obstaculo cercano
          if (detectedObjects.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _BottomObstacleBar(
                closest: detectedObjects.first,
                accentColor: cs.primary,
              ),
            ),

          // 5. Nav status
          if (detectedObjects.isEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _NavStatusBar(colorScheme: cs),
            ),

          // 6. Mini-mapa de ruta (solo si hay navegacion activa)
          Consumer(
            builder: (context, ref, _) {
              final navState = ref.watch(navigationProvider);
              final gpsAsync = ref.watch(currentLocationStreamProvider);

              // Mostrar si hay ruta Dijkstra O ruta Google Routes
              final hasRoute = navState.hasActiveRoute || navState.hasGoogleRoute;
              if (!hasRoute) return const SizedBox.shrink();

              // Validar que haya al menos 2 puntos para dibujar la polyline
              final polyCount = navState.routePolylinePoints?.length ??
                  navState.activeRoute?.steps.length ?? 0;
              if (polyCount < 2) return const SizedBox.shrink();

              // Posicion GPS actual
              ll.LatLng? currentGps;
              gpsAsync.whenData((pos) {
                currentGps = ll.LatLng(pos.latitude, pos.longitude);
              });

              // Bottom = altura BottomNav (~56) + barra estado (~80) + margen (16)
              final bottomOffset = MediaQuery.of(context).padding.bottom + 156.0;

              return Positioned(
                right: 12,
                bottom: bottomOffset,
                child: _MiniRouteMap(
                  route: navState.activeRoute,
                  currentStep: navState.currentStepIndex,
                  googlePolyline: navState.routePolylinePoints,
                  destinationName: navState.destinationName,
                  distanceMeters: navState.routeDistanceMeters,
                  currentGps: currentGps,
                  onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.map),
                ),
              );
            },
          ),


          // 7. Boton demo
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: GestureDetector(
              onTap: _showDemoSheet,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Icon(
                  Icons.help_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_pipelineError != null && !_isPipelineReady) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded,
                  color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              Text(_pipelineError!,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _initPipeline,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _cameraController;
    if (!_isPipelineReady ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white54),
            SizedBox(height: 16),
            Text('Iniciando NAVIA AR...',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (_, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? constraints.maxWidth,
            height:
                controller.value.previewSize?.width ?? constraints.maxHeight,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BoundingBoxPainter
// ---------------------------------------------------------------------------

class _BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final double frameWidth;
  final double frameHeight;

  _BoundingBoxPainter({
    required this.objects,
    required this.frameWidth,
    required this.frameHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final obj in objects) {
      final color = _colorForDistance(obj.distance);

      final scaleX = size.width / frameWidth;
      final scaleY = size.height / frameHeight;

      final scaledRect = Rect.fromLTRB(
        obj.boundingBox.left * scaleX,
        obj.boundingBox.top * scaleY,
        obj.boundingBox.right * scaleX,
        obj.boundingBox.bottom * scaleY,
      );

      // Fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaledRect, const Radius.circular(8)),
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill,
      );

      // Stroke
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaledRect, const Radius.circular(8)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Label
      final pct = (obj.confidence * 100).round();
      final textSpan = TextSpan(
        text: '${obj.label}  ${obj.distance}  $pct%',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
        ..layout(maxWidth: scaledRect.width.clamp(50, size.width));

      final labelBg = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top - 20,
        tp.width + 8,
        20,
      );
      canvas.drawRect(labelBg, Paint()..color = const Color(0xCC000000));
      tp.paint(canvas, Offset(scaledRect.left + 4, scaledRect.top - 18));
    }
  }

  Color _colorForDistance(String distance) {
    switch (distance) {
      case 'inmediato':
        return const Color(0xFFFF1744);
      case 'cercano':
        return const Color(0xFFFF6D00);
      case 'medio':
        return const Color(0xFFFFD600);
      case 'lejano':
        return const Color(0xFF00E676);
      default:
        return const Color(0xFF00E5FF);
    }
  }

  @override
  bool shouldRepaint(_BoundingBoxPainter old) => objects != old.objects;
}

// ---------------------------------------------------------------------------
// HUD superior
// ---------------------------------------------------------------------------

class _HudBar extends StatelessWidget {
  final VisionState visionState;
  final ColorScheme colorScheme;
  const _HudBar({required this.visionState, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (visionState.status) {
      case VisionStatus.processing:
        statusColor = const Color(0xFF00E5FF);
        statusLabel = 'DETECTANDO';
        statusIcon = Icons.remove_red_eye_rounded;
      case VisionStatus.ready:
        statusColor = Colors.greenAccent;
        statusLabel = 'LISTO';
        statusIcon = Icons.check_circle_outline_rounded;
      case VisionStatus.paused:
        statusColor = Colors.amber;
        statusLabel = 'PAUSADO';
        statusIcon = Icons.pause_circle_outline_rounded;
      case VisionStatus.error:
        statusColor = colorScheme.error;
        statusLabel = 'ERROR';
        statusIcon = Icons.error_outline_rounded;
      case VisionStatus.voiceOnlyFallback:
        statusColor = Colors.orange;
        statusLabel = 'SOLO VOZ';
        statusIcon = Icons.volume_up_rounded;
      case VisionStatus.uninitialized:
        statusColor = Colors.white54;
        statusLabel = 'INICIANDO';
        statusIcon = Icons.hourglass_empty_rounded;
    }

    final count = visionState.detectedObjects.length;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 8, 56, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          const Text('NAVIA  AR',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 14),
                const SizedBox(width: 4),
                Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2)),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barra inferior de obstaculo
// ---------------------------------------------------------------------------

class _BottomObstacleBar extends StatelessWidget {
  final DetectedObject closest;
  final Color accentColor;
  const _BottomObstacleBar({required this.closest, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final isUrgent =
        closest.distance == 'inmediato' || closest.distance == 'cercano';
    final barColor = isUrgent ? const Color(0xFFFF1744) : accentColor;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: barColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
              isUrgent
                  ? Icons.warning_amber_rounded
                  : Icons.remove_red_eye_rounded,
              color: barColor,
              size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(closest.label.toUpperCase(),
                    style: TextStyle(
                        color: barColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(_distLabel(closest.distance),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Text('${(closest.confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: barColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _distLabel(String d) {
    switch (d) {
      case 'inmediato':
        return 'MUY CERCA - Precaucion';
      case 'cercano':
        return 'A pocos metros';
      case 'medio':
        return 'Distancia media';
      case 'lejano':
        return 'A lo lejos';
      default:
        return 'Detectado';
    }
  }
}

// ---------------------------------------------------------------------------
// Barra inferior de navegacion
// ---------------------------------------------------------------------------

class _NavStatusBar extends ConsumerWidget {
  final ColorScheme colorScheme;
  const _NavStatusBar({required this.colorScheme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);
    final cs = colorScheme;

    // Mostrar si hay nodo actual, ruta Dijkstra, o ruta Google Routes
    if (navState.currentNode == null &&
        navState.activeRoute == null &&
        !navState.hasGoogleRoute) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (navState.currentNode != null) ...[
            Row(children: [
              Icon(Icons.location_on_rounded, color: cs.primary, size: 16),
              const SizedBox(width: 6),
              Text('UBICACION ACTUAL',
                  style: TextStyle(
                      color: cs.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
            ]),
            const SizedBox(height: 4),
            Text(navState.currentNode!.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ],
          if (navState.activeRoute != null &&
              navState.currentInstruction != null) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.directions_walk_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(navState.currentInstruction!,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
            ]),
          ],
          // Info de Google Routes cuando no hay ruta Dijkstra
          if (navState.activeRoute == null && navState.hasGoogleRoute) ...[
            if (navState.currentNode != null)
              const SizedBox(height: 8),
            if (navState.currentNode != null)
              const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.navigation_rounded, color: cs.primary, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Navegando a ${navState.destinationName ?? "destino"}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            if (navState.routeDistanceMeters != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.straighten_rounded,
                    color: Colors.white54, size: 14),
                const SizedBox(width: 6),
                Text(
                  navState.routeDistanceMeters! >= 1000
                      ? '${(navState.routeDistanceMeters! / 1000).toStringAsFixed(1)} km'
                      : '${navState.routeDistanceMeters} m',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.schedule_rounded,
                    color: Colors.white54, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${(navState.routeDistanceMeters! / 72).round()} min',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Demo BottomSheet
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Mini-mapa de ruta (estilo Uber/Didi)
// ---------------------------------------------------------------------------

class _MiniRouteMap extends StatefulWidget {
  final NavRoute? route;
  final int currentStep;
  final List<List<double>>? googlePolyline;
  final String? destinationName;
  final int? distanceMeters;
  final ll.LatLng? currentGps;
  final VoidCallback onTap;

  const _MiniRouteMap({
    this.route,
    required this.currentStep,
    this.googlePolyline,
    this.destinationName,
    this.distanceMeters,
    this.currentGps,
    required this.onTap,
  });

  @override
  State<_MiniRouteMap> createState() => _MiniRouteMapState();
}

class _MiniRouteMapState extends State<_MiniRouteMap> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(covariant _MiniRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentGps != null && widget.currentGps != oldWidget.currentGps) {
      _mapController.move(widget.currentGps!, _mapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Construir puntos de la polilínea (priorizar Google Routes)
    List<ll.LatLng> polyPoints = [];
    if (widget.googlePolyline != null && widget.googlePolyline!.isNotEmpty) {
      polyPoints = widget.googlePolyline!
          .map((p) => ll.LatLng(p[0], p[1]))
          .toList();
    } else if (widget.route != null) {
      polyPoints = widget.route!.steps
          .map((s) => ll.LatLng(s.node.lat, s.node.lng))
          .toList();
    }

    if (polyPoints.isEmpty) return const SizedBox.shrink();

    // Calcular centro y bounds
    final minLat = polyPoints.map((p) => p.latitude).reduce(math.min);
    final maxLat = polyPoints.map((p) => p.latitude).reduce(math.max);
    final minLng = polyPoints.map((p) => p.longitude).reduce(math.min);
    final maxLng = polyPoints.map((p) => p.longitude).reduce(math.max);
    final center = ll.LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    // Info para overlay
    final displayName = widget.destinationName ??
        widget.route?.destination.name.split(' - ').first ??
        'Destino';
    final distance = widget.distanceMeters ?? widget.route?.totalDistance.round();
    final etaMinutes = distance != null
        ? (distance / 72).round() // ~1.2 m/s velocidad peatonal
        : widget.route?.estimatedMinutes.round();

    // Posicion del paso actual en la ruta Dijkstra
    final safeStep = widget.route != null
        ? widget.currentStep.clamp(0, polyPoints.length - 1)
        : 0;

    // Progreso de la ruta
    final progress = widget.route != null && widget.route!.steps.isNotEmpty
        ? widget.currentStep / widget.route!.steps.length
        : 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 165,
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary.withValues(alpha: 0.6), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              spreadRadius: 3,
            ),
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.15),
              blurRadius: 12,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Fondo oscuro inmediato mientras cargan los tiles OSM
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF1A2332)),
              ),
              // Mapa base
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(polyPoints),
                      padding: const EdgeInsets.all(28),
                    ),
                    initialCenter: widget.currentGps ?? center,
                    initialZoom: 16.5,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'mx.edu.tecnm.colima.navia',
                      fallbackUrl:
                          'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
                      maxZoom: 19,
                      errorTileCallback: (tile, error, stack) {
                        debugPrint('MiniMap tile error (silenced): $error');
                      },
                    ),
                    // Polilinea de la ruta
                    PolylineLayer(
                      polylines: [
                        // Sombra de la ruta
                        Polyline(
                          points: polyPoints,
                          color: cs.primary.withValues(alpha: 0.3),
                          strokeWidth: 8,
                        ),
                        // Ruta principal
                        Polyline(
                          points: polyPoints,
                          color: cs.primary,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // GPS actual (punto pulsante)
                        if (widget.currentGps != null)
                          Marker(
                            point: widget.currentGps!,
                            width: 20,
                            height: 20,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFAB00),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFAB00).withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Posicion en la ruta (si no hay GPS y hay ruta Dijkstra)
                        if (widget.currentGps == null && widget.route != null)
                          Marker(
                            point: polyPoints[safeStep],
                            width: 16,
                            height: 16,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: cs.primary, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Inicio
                        Marker(
                          point: polyPoints.first,
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                        // Destino
                        Marker(
                          point: polyPoints.last,
                          width: 24,
                          height: 24,
                          child: Icon(
                            Icons.location_pin,
                            color: cs.primary,
                            size: 24,
                            shadows: const [
                              Shadow(color: Colors.black87, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Encabezado: nombre destino + ETA
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xE50F172A), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.navigation_rounded,
                          color: cs.primary, size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          displayName.toUpperCase(),
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Footer: distancia + ETA + boton expandir
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xE50F172A), Colors.transparent],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Barra de progreso
                      if (progress > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation(cs.primary),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          if (distance != null) ...[
                            _InfoChip(
                              icon: Icons.straighten_rounded,
                              text: distance >= 1000
                                  ? '${(distance / 1000).toStringAsFixed(1)} km'
                                  : '$distance m',
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (etaMinutes != null)
                            _InfoChip(
                              icon: Icons.schedule_rounded,
                              text: etaMinutes < 1
                                  ? '<1 min'
                                  : '$etaMinutes min',
                            ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.open_in_full_rounded,
                              color: cs.primary,
                              size: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip informativo para el mini-mapa
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 9),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _DemoPlace {
  final String markerId;
  final String displayName;
  final IconData icon;
  const _DemoPlace(this.markerId, this.displayName, this.icon);
}

class _DemoBottomSheet extends StatelessWidget {
  final List<_DemoPlace> places;
  final void Function(_DemoPlace) onSelected;
  final ColorScheme colorScheme;
  const _DemoBottomSheet(
      {required this.places,
      required this.onSelected,
      required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.place_rounded, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('MODO DEMO',
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5)),
                const Text('Simular llegada a...',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: places.length,
              itemBuilder: (_, i) {
                final place = places[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onSelected(place),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12)),
                            child:
                                Icon(place.icon, color: cs.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(place.displayName,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text('ID: ${place.markerId}',
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.8)),
                                ]),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.3),
                              size: 22),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
