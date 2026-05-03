import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sinait/core/constants/campus_locations.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/providers/navigation_provider.dart';
import 'package:sinait/data/providers/voice_provider.dart';
import 'package:sinait/data/providers/feed_provider.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

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
                  label: const Text('Simular escaneo (demo)',
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

  void _showDemoSelector(BuildContext context) {
    final demoLocations = [
      (
        CampusLocations.entradaPrincipal,
        'Acceso Principal',
        Icons.door_front_door_rounded
      ),
      (
        CampusLocations.edificioB,
        'Centro de Información',
        Icons.local_library_rounded
      ),
      (
        CampusLocations.sistemas,
        'Sistemas y Computación',
        Icons.computer_rounded
      ),
      (CampusLocations.cafeteria, 'Cafetería Norte', Icons.restaurant_rounded),
      (CampusLocations.edificioA, 'Administrativo', Icons.business_rounded),
      (CampusLocations.edificioP, 'Edificio P', Icons.school_rounded),
      (CampusLocations.cecum, 'CECUM', Icons.event_rounded),
      (
        CampusLocations.canchas,
        'Canchas Techadas',
        Icons.sports_soccer_rounded
      ),
      (CampusLocations.mecatronica, 'Lab. Mecatrónica', Icons.memory_rounded),
      (CampusLocations.explanadaPrincipal, 'Patio Cívico', Icons.park_rounded),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('SIMULAR ESCANEO',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: demoLocations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final loc = demoLocations[i];
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(loc.$3, color: AppTheme.accent, size: 22),
                    ),
                    title: Text(loc.$2,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    subtitle: Text('ZONA: ${loc.$1.toUpperCase()}',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                    tileColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side:
                            BorderSide(color: Colors.white.withOpacity(0.05))),
                    onTap: () {
                      Navigator.pop(context);
                      _simulateScan(loc.$1);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNavigateDialog(BuildContext context) {
    final navNotifier = ref.read(navigationProvider.notifier);
    final destinations = navNotifier.allDestinations
        .where((d) => d.id != _scannedNodeId)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 24),
              const Text('SELECCIONA DESTINO',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  itemCount: destinations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final dest = destinations[i];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.place_rounded,
                            color: AppTheme.accent, size: 22),
                      ),
                      title: Text(dest.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      subtitle: Text(dest.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 12)),
                      tileColor: AppTheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.05))),
                      onTap: () {
                        Navigator.pop(context);
                        navNotifier.navigateTo(dest.name);
                        final navState = ref.read(navigationProvider);
                        if (navState.activeRoute != null) {
                          ref.read(voiceProvider.notifier).speakAnnouncement(
                              navState.activeRoute!.voiceSummary);
                        }
                        Navigator.pushReplacementNamed(context, '/home');
                      },
                    );
                  },
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
        width: 280,
        height: 280,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color:
              scanned ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color:
                scanned ? AppTheme.success : AppTheme.accent.withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (scanned ? AppTheme.success : AppTheme.accent)
                  .withOpacity(0.1),
              blurRadius: 20,
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
                      // Contenido de "Haz click aquí" cuando está inactivo
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color:
                                        AppTheme.accent.withValues(alpha: 0.2),
                                    width: 1.5),
                              ),
                              child: const Icon(Icons.qr_code_scanner_rounded,
                                  color: AppTheme.accent, size: 52),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Haz click aquí',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'PARA ESCANEAR EL QR DE LAS AULAS',
                              style: TextStyle(
                                color: AppTheme.accent.withValues(alpha: 0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
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
        Positioned(top: 20, left: 20, child: _Corner(quarterTurns: 0)),
        Positioned(top: 20, right: 20, child: _Corner(quarterTurns: 1)),
        Positioned(bottom: 20, left: 20, child: _Corner(quarterTurns: 3)),
        Positioned(bottom: 20, right: 20, child: _Corner(quarterTurns: 2)),
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
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.accent, width: 4),
            left: BorderSide(color: AppTheme.accent, width: 4),
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
                label: const Text('TRAZAR RUTA AQUÍ',
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
