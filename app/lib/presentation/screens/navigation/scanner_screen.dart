import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/data/providers/vision_provider.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';
import 'package:navia/services/vision/camera_feed_handler.dart';
import 'package:navia/services/vision/ml_vision_service.dart';
import 'package:navia/services/vision/model_manager_service.dart';
import 'package:navia/services/vision/marker_recognizer.dart';
import 'package:navia/services/vision/models/detected_object.dart';

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
    _initPipeline();
    // Garantizar que voz y grafo estén listos aunque el usuario llegue aquí
    // directamente sin pasar por HomeScreen primero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(voiceProvider.notifier).initialize();
      ref.read(navigationProvider.notifier).initialize();
    });
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

      // 4. Crear CameraFeedHandler
      final feedHandler = CameraFeedHandler(
        camera: backCamera,
        isDetectionActive: () =>
            _isPipelineReady || ref.read(visionProvider).isActive,
        mlService: modelLoaded ? detector : null,
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
    final now = DateTime.now();
    if (now.difference(_lastVoiceAt) < _kVoiceCooldown) return;
    _lastVoiceAt = now;

    final closest = objects.first;
    final distanceStr = _distanceToMeters(closest.distance);
    final labelName = closest.label.toUpperCase();
    final article = _getArticle(labelName);

    String announcement = '';

    if (labelName == 'ESCALERAS' || labelName == 'ESCALONES') {
      announcement = 'PRECAUCION, EN $distanceStr HAY ESCALONES o ESCALERAS';
    } else if (labelName == 'BARDAS') {
      announcement = 'CUIDADO, EN $distanceStr HAY UNAS BARDAS';
    } else if (closest.distance == 'inmediato') {
      announcement = 'CUIDADO A $distanceStr ESTA $article $labelName';
    } else if (closest.distance == 'cercano') {
      announcement = 'PRECAUCION, EN $distanceStr HAY $article $labelName';
    } else {
      announcement = 'EN $distanceStr ESTA $article $labelName FRENTE A TI';
    }

    ref.read(voiceProvider.notifier).speakAnnouncement(announcement);
  }

  String _getArticle(String label) {
    if (label == 'PARED' || label.endsWith('A')) return 'UNA';
    if (label == 'BARDAS') return 'UNAS';
    return 'UN';
  }

  String _distanceToMeters(String distance) {
    switch (distance) {
      case 'inmediato':
        return '1 METRO';
      case 'cercano':
        return '2 METROS';
      case 'medio':
        return '3 METROS';
      case 'lejano':
        return '5 METROS';
      default:
        return 'UNOS METROS';
    }
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

          // 6. Mini-mapa de ruta (solo si hay navegación activa)
          Consumer(
            builder: (context, ref, _) {
              final navState = ref.watch(navigationProvider);
              if (!navState.hasActiveRoute || navState.activeRoute == null) {
                return const SizedBox.shrink();
              }
              return Positioned(
                right: 12,
                bottom: 160,
                child: _MiniRouteMap(
                  route: navState.activeRoute!,
                  currentStep: navState.currentStepIndex,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.map),
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

    if (navState.currentNode == null && navState.activeRoute == null) {
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

class _MiniRouteMap extends StatelessWidget {
  final NavRoute route;
  final int currentStep;
  final VoidCallback onTap;

  const _MiniRouteMap({
    required this.route,
    required this.currentStep,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = route.steps
        .map((s) => ll.LatLng(s.node.lat, s.node.lng))
        .toList();

    if (points.isEmpty) return const SizedBox.shrink();

    final safeStep = currentStep.clamp(0, points.length - 1);

    final minLat = points.map((p) => p.latitude).reduce(math.min);
    final maxLat = points.map((p) => p.latitude).reduce(math.max);
    final minLng = points.map((p) => p.longitude).reduce(math.min);
    final maxLng = points.map((p) => p.longitude).reduce(math.max);
    final center = ll.LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 155,
        height: 155,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 16, spreadRadius: 2),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(24),
                  ),
                  initialCenter: center,
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
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        color: cs.primary,
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      // Posición actual en la ruta
                      Marker(
                        point: points[safeStep],
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.primary, width: 2.5),
                          ),
                        ),
                      ),
                      // Marcador del destino
                      Marker(
                        point: points.last,
                        width: 22,
                        height: 22,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Gradiente inferior con nombre del destino
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Text(
                    route.destination.name.split(' - ').first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Ícono de tap para expandir
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    color: Colors.white70,
                    size: 10,
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
