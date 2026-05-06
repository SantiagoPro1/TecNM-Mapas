import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sinait/core/constants/campus_locations.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/providers/navigation_provider.dart';
import 'package:sinait/data/providers/voice_provider.dart';
import 'package:sinait/data/providers/feed_provider.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';
import 'package:sinait/data/models/campus_node.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scanAnimation;
  bool _scanned = false;
  bool _isCameraActive = false;
  String? _result;
  String? _scannedNodeId;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_animController);
  }

  @override
  void dispose() {
    _animController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final String code = barcodes.first.rawValue!;
      String? nodeId;

      // Intentar parsear como SINAIT:ID o JSON {"node_id": "ID"}
      if (code.startsWith('SINAIT:')) {
        nodeId = CampusLocations.parseQrCode(code);
      } else {
        try {
          final data = jsonDecode(code);
          nodeId = data['node_id'];
        } catch (_) {}
      }

      if (nodeId != null) {
        setState(() => _isCameraActive = false);
        _simulateScan(nodeId);
      }
    }
  }

  void _simulateScan(String nodeId) {
    final parsedId = CampusLocations.parseQrCode('SINAIT:$nodeId') ?? nodeId;
    final navNotifier = ref.read(navigationProvider.notifier);
    navNotifier.setPosition(parsedId);
    final navState = ref.read(navigationProvider);

    if (navState.currentNode != null) {
      setState(() {
        _scanned = true;
        _scannedNodeId = parsedId;
        _result =
            '${navState.currentNode!.name}\n${navState.currentNode!.description}';
      });

      ref.read(feedProvider.notifier).loadForZone(parsedId);
      ref.read(voiceProvider.notifier).speakAnnouncement(
            'Posición confirmada: ${navState.currentNode!.name}.',
          );
    } else {
      setState(() {
        _scanned = true;
        _result = 'Ubicación no reconocida: $parsedId';
      });
    }
  }

  void _resetScan() {
    setState(() {
      _scanned = false;
      _result = null;
      _scannedNodeId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);

    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    });
    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      appBar: AppBar(
        title: const Text('POSICIONAMIENTO'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              Text(
                'Confirma tu posición escaneando el código QR más cercano',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 40),
              _ScanViewport(
                animation: _scanAnimation,
                scanned: _scanned,
                isCameraActive: _isCameraActive,
                controller: _scannerController,
                onDetect: _onDetect,
                onTap: () => setState(() => _isCameraActive = !_isCameraActive),
              ),
              const SizedBox(height: 32),
              // El botón _PremiumScanButton ha sido eliminado para evitar duplicidad
              const SizedBox(height: 16),
              if (_scanned && _result != null) ...[
                _ResultCard(
                  result: _result!,
                  nodeId: _scannedNodeId,
                  onNavigate: _scannedNodeId != null
                      ? () => _showNavigateDialog(context)
                      : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _resetScan,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('REINTENTAR ESCANEO'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: BorderSide(color: AppTheme.accent.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ] else
                TextButton.icon(
                  onPressed: () => _showDemoSelector(context),
                  icon: const Icon(Icons.touch_app_rounded,
                      color: AppTheme.accent),
                  label: const Text('¿No puedes escanear? Selecciona dónde estás',
                      style: TextStyle(
                          color: AppTheme.accent, fontWeight: FontWeight.w800)),
                ),
              if (navState.currentNode != null && !_scanned) ...[
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: AppTheme.success.withOpacity(0.1)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 10)
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.location_on_rounded,
                            color: AppTheme.success, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('UBICACIÓN ACTUAL',
                                style: TextStyle(
                                    color: AppTheme.success,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0)),
                            const SizedBox(height: 4),
                            Text(navState.currentNode!.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _useGpsPosition() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Buscando señal GPS...')),
    );

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Activa el GPS en tu dispositivo.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Permiso de GPS denegado.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      ref.read(navigationProvider.notifier).setPositionByCoordinates(pos.latitude, pos.longitude);

      final navState = ref.read(navigationProvider);
      if (navState.currentNode != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Ubicación: ${navState.currentNode!.name}')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No se encontró un punto de navegación cercano.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener el GPS. Verifica permisos.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _showDemoSelector(BuildContext context) {
    final navNotifier = ref.read(navigationProvider.notifier);
    final allNodes = navNotifier.allDestinations;

    // Agrupar nodos por venue (insensible a mayúsculas/minúsculas)
    final tecNodes = allNodes.where((n) {
      final id = n.id.toLowerCase();
      return !id.contains('sendera') && !id.contains('zentralia');
    }).toList();
    
    final senderaNodes = allNodes.where((n) {
      final id = n.id.toLowerCase();
      return id.contains('sendera');
    }).toList();
    
    final zentraliaNodes = allNodes.where((n) {
      final id = n.id.toLowerCase();
      return id.contains('zentralia');
    }).toList();

    // Ordenar alfabéticamente
    tecNodes.sort((a, b) => a.name.compareTo(b.name));
    senderaNodes.sort((a, b) => a.name.compareTo(b.name));
    zentraliaNodes.sort((a, b) => a.name.compareTo(b.name));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 24),
              const Text('SELECCIONA TU UBICACIÓN ACTUAL', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildVenueSection('SISTEMA GPS', [
                      (null, '📍 Usar mi ubicación real (GPS)', Icons.my_location_rounded, Colors.blueAccent)
                    ], isGps: true),
                    if (tecNodes.isNotEmpty)
                      _buildVenueSection('TECNM CAMPUS COLIMA', tecNodes.map((n) => (n.id, n.name, _getIconForType(n.type))).toList(), color: const Color(0xFF00E5FF)),
                    if (senderaNodes.isNotEmpty)
                      _buildVenueSection('PLAZA SENDERA', senderaNodes.map((n) => (n.id, n.name, _getIconForType(n.type))).toList(), color: const Color(0xFFFF9800)),
                    if (zentraliaNodes.isNotEmpty)
                      _buildVenueSection('PLAZA ZENTRALIA', zentraliaNodes.map((n) => (n.id, n.name, _getIconForType(n.type))).toList(), color: const Color(0xFFE040FB)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(NodeType type) {
    switch (type) {
      case NodeType.building: return Icons.business_rounded;
      case NodeType.entrance: return Icons.door_front_door_rounded;
      case NodeType.area: return Icons.park_rounded;
      case NodeType.corridor: return Icons.directions_walk_rounded;
      default: return Icons.location_on_rounded;
    }
  }

  Widget _buildVenueSection(String title, List<dynamic> locations, {Color color = Colors.white24, bool isGps = false, bool isDestination = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Text(title, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ),
        ...locations.map((loc) {
          final id = loc.$1 as String?;
          final name = loc.$2 as String;
          final icon = loc.$3 as IconData;
          final iconColor = isGps ? (loc.$4 as Color) : color;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ListTile(
              onTap: () {
                Navigator.pop(context);
                if (isGps) {
                  _useGpsPosition();
                } else if (isDestination) {
                  final navNotifier = ref.read(navigationProvider.notifier);
                  navNotifier.navigateTo(name);
                  final navState = ref.read(navigationProvider);
                  if (navState.activeRoute != null) {
                    ref.read(voiceProvider.notifier).speakAnnouncement(navState.activeRoute!.voiceSummary);
                  }
                  Navigator.pushReplacementNamed(context, '/home');
                } else {
                  _simulateScan(id!);
                }
              },
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              subtitle: id != null ? Text('ID: ${id.toUpperCase()}', style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w800)) : null,
              tileColor: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showNavigateDialog(BuildContext context) {
    final navNotifier = ref.read(navigationProvider.notifier);
    final allNodes = navNotifier.allDestinations.where((d) => d.id != _scannedNodeId).toList();

    // Agrupar nodos por venue (insensible a mayúsculas/minúsculas)
    final tecNodes = allNodes.where((n) {
      final id = n.id.toLowerCase();
      return !id.contains('sendera') && !id.contains('zentralia');
    }).toList();
    
    final senderaNodes = allNodes.where((n) {
      final id = n.id.toLowerCase();
      return id.contains('sendera');
    }).toList();
    
    final zentraliaNodes = allNodes.where((n) {
      final id = n.id.toLowerCase();
      return id.contains('zentralia');
    }).toList();

    // Ordenar alfabéticamente
    tecNodes.sort((a, b) => a.name.compareTo(b.name));
    senderaNodes.sort((a, b) => a.name.compareTo(b.name));
    zentraliaNodes.sort((a, b) => a.name.compareTo(b.name));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 24),
              const Text('SELECCIONA DESTINO', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (tecNodes.isNotEmpty)
                      _buildVenueSection('TECNM CAMPUS COLIMA', tecNodes.map((n) => (n.id, n.name, _getIconForType(n.type))).toList(), color: const Color(0xFF00E5FF), isDestination: true),
                    if (senderaNodes.isNotEmpty)
                      _buildVenueSection('PLAZA SENDERA', senderaNodes.map((n) => (n.id, n.name, _getIconForType(n.type))).toList(), color: const Color(0xFFFF9800), isDestination: true),
                    if (zentraliaNodes.isNotEmpty)
                      _buildVenueSection('PLAZA ZENTRALIA', zentraliaNodes.map((n) => (n.id, n.name, _getIconForType(n.type))).toList(), color: const Color(0xFFE040FB), isDestination: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanViewport extends StatelessWidget {
  final Animation<double> animation;
  final bool scanned;
  final bool isCameraActive;
  final MobileScannerController controller;
  final Function(BarcodeCapture) onDetect;
  final VoidCallback onTap;

  const _ScanViewport({
    required this.animation,
    required this.scanned,
    required this.isCameraActive,
    required this.controller,
    required this.onDetect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: scanned ? null : onTap,
      child: Container(
        width: 320,
        height: 320,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scanned ? AppTheme.success.withOpacity(0.05) : const Color(0xFF0D1B2A).withOpacity(0.4),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: scanned ? AppTheme.success : const Color(0xFF00E5FF).withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (scanned ? AppTheme.success : const Color(0xFF00E5FF)).withOpacity(0.15),
              blurRadius: 30,
              spreadRadius: 2,
            )
          ],
        ),
        child: scanned
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle_rounded,
                        color: AppTheme.success, size: 64),
                  ),
                  const SizedBox(height: 20),
                  const Text('CONFIRMADO',
                      style: TextStyle(
                          color: AppTheme.success,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0)),
                ],
              )
            : isCameraActive
                ? MobileScanner(
                    controller: controller,
                    onDetect: onDetect,
                  )
                : Stack(
                    children: [
                      // Center circle with QR icon
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2), width: 1),
                                color: const Color(0xFF00E5FF).withOpacity(0.05),
                              ),
                              child: const Icon(Icons.qr_code_2_rounded, size: 48, color: Color(0xFF00E5FF)),
                            ),
                            const SizedBox(height: 32),
                            const Text(
                              'Haz click aquí',
                              style: TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'PARA ESCANEAR EL QR DE LAS AULAS',
                              style: TextStyle(
                                color: const Color(0xFF00E5FF).withOpacity(0.4),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Corner markers
                      const _ScannerCorners(),
                    ],
                  ),
      ),
    );
  }
}

class _ScannerCorners extends StatelessWidget {
  const _ScannerCorners();
  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(top: 30, left: 30, child: _Corner(quarterTurns: 0)),
        Positioned(top: 30, right: 30, child: _Corner(quarterTurns: 1)),
        Positioned(bottom: 30, left: 30, child: _Corner(quarterTurns: 3)),
        Positioned(bottom: 30, right: 30, child: _Corner(quarterTurns: 2)),
      ],
    );
  }
}

class _Corner extends StatelessWidget {
  final int quarterTurns;
  const _Corner({required this.quarterTurns});
  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Container(
        width: 35,
        height: 35,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF00E5FF), width: 3),
            left: BorderSide(color: Color(0xFF00E5FF), width: 3),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String result;
  final String? nodeId;
  final VoidCallback? onNavigate;
  const _ResultCard({required this.result, this.nodeId, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: AppTheme.success.withOpacity(0.3), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppTheme.success, size: 20),
              const SizedBox(width: 8),
              Text('ESTÁS EN:',
                  style: TextStyle(
                      color: AppTheme.success.withOpacity(0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.4),
          ),
          if (onNavigate != null) ...[
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF0091EA)]),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.accent.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.directions_walk_rounded,
                    size: 22, color: Color(0xFF0D1B2A)),
                label: const Text('SELECCIONAR DESTINO',
                    style: TextStyle(
                        color: Color(0xFF0D1B2A),
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
