import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String? _result;
  String? _scannedNodeId;

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
    super.dispose();
  }

  /// Simula el escaneo de un QR del campus (demo).
  /// En producción, se reemplazará con mobile_scanner real.
  void _simulateScan(String nodeId) {
    final parsedId = CampusLocations.parseQrCode('SINAIT:$nodeId') ?? nodeId;

    // Establecer posición en el grafo
    final navNotifier = ref.read(navigationProvider.notifier);
    navNotifier.setPosition(parsedId);

    final navState = ref.read(navigationProvider);

    if (navState.currentNode != null) {
      setState(() {
        _scanned = true;
        _scannedNodeId = parsedId;
        _result = '${navState.currentNode!.name}\n${navState.currentNode!.description}';
      });

      // Cargar feed contextual para la nueva zona
      ref.read(feedProvider.notifier).loadForZone(parsedId);

      // Anunciar posición por voz
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
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      appBar: AppBar(title: const Text('Escanear QR')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Apunta la cámara al código QR del pasillo para confirmar tu posición',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              _ScanViewport(
                animation: _scanAnimation,
                scanned: _scanned,
                onTap: () => _showDemoSelector(context),
              ),
              const SizedBox(height: 32),
              if (_scanned && _result != null) ...[
                _ResultCard(
                  result: _result!,
                  nodeId: _scannedNodeId,
                  onNavigate: _scannedNodeId != null
                      ? () => _showNavigateDialog(context)
                      : null,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _resetScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Escanear otro'),
                ),
              ] else
                TextButton.icon(
                  onPressed: () => _showDemoSelector(context),
                  icon: const Icon(Icons.touch_app_rounded),
                  label: const Text('Simular escaneo (demo)'),
                ),

              // Mostrar posición actual
              if (navState.currentNode != null && !_scanned) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppTheme.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppTheme.success, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Posición actual',
                                style: TextStyle(
                                    color: AppTheme.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(navState.currentNode!.name,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
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

  /// Muestra un selector de ubicaciones demo para simular escaneo.
  void _showDemoSelector(BuildContext context) {
    final demoLocations = [
      ('entrada_principal', 'Entrada Principal', Icons.door_front_door_rounded),
      ('biblioteca', 'Biblioteca', Icons.local_library_rounded),
      ('centro_computo', 'Centro de Cómputo', Icons.computer_rounded),
      ('cafeteria', 'Cafetería', Icons.restaurant_rounded),
      ('edificio_a', 'Edificio A', Icons.school_rounded),
      ('edificio_b', 'Edificio B', Icons.school_rounded),
      ('direccion', 'Dirección General', Icons.business_rounded),
      ('auditorio', 'Auditorio', Icons.event_rounded),
      ('cancha', 'Cancha Deportiva', Icons.sports_soccer_rounded),
      ('lab_electronica', 'Lab. Electrónica', Icons.memory_rounded),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Simular escaneo QR',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Selecciona una ubicación del campus:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: demoLocations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final loc = demoLocations[i];
                  return ListTile(
                    leading: Icon(loc.$3, color: AppTheme.accent),
                    title: Text(loc.$2,
                        style: const TextStyle(color: AppTheme.textPrimary)),
                    subtitle: Text('QR: SINAIT:${loc.$1}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                    tileColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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

  /// Diálogo para seleccionar destino de navegación.
  void _showNavigateDialog(BuildContext context) {
    final navNotifier = ref.read(navigationProvider.notifier);
    final destinations = navNotifier.allDestinations
        .where((d) => d.id != _scannedNodeId)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿A dónde quieres ir?',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  itemCount: destinations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final dest = destinations[i];
                    return ListTile(
                      leading: const Icon(Icons.place_rounded,
                          color: AppTheme.accent),
                      title: Text(dest.name,
                          style:
                              const TextStyle(color: AppTheme.textPrimary)),
                      subtitle: Text(dest.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                      tileColor: AppTheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onTap: () {
                        Navigator.pop(context);
                        navNotifier.navigateTo(dest.name);

                        // Anunciar ruta por voz
                        final navState = ref.read(navigationProvider);
                        if (navState.activeRoute != null) {
                          ref.read(voiceProvider.notifier).speakAnnouncement(
                            navState.activeRoute!.voiceSummary,
                          );
                        }

                        // Ir al Home para ver la navegación
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
  final VoidCallback onTap;

  const _ScanViewport({
    required this.animation,
    required this.scanned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: scanned ? null : onTap,
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          color: scanned
              ? AppTheme.success.withValues(alpha: 0.1)
              : AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scanned ? AppTheme.success : AppTheme.accent,
            width: 2,
          ),
        ),
        child: scanned
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppTheme.success, size: 64),
                  SizedBox(height: 12),
                  Text('¡Posición confirmada!',
                      style: TextStyle(
                          color: AppTheme.success,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              )
            : Stack(
                children: [
                  Center(
                    child: Icon(Icons.qr_code_rounded,
                        size: 80,
                        color: AppTheme.accent.withValues(alpha: 0.3)),
                  ),
                  AnimatedBuilder(
                    animation: animation,
                    builder: (_, __) => Positioned(
                      top: animation.value * 220 + 20,
                      left: 20,
                      right: 20,
                      child: Container(
                        height: 2,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ],
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.success, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on_rounded,
                  color: AppTheme.success, size: 22),
              SizedBox(width: 8),
              Text('Tu ubicación actual',
                  style: TextStyle(
                      color: AppTheme.success,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                height: 1.5),
          ),
          if (onNavigate != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Navegar desde aquí'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ],
      ),
    );
  }
}