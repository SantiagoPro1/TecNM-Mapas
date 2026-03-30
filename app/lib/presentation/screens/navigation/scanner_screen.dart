import 'package:flutter/material.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scanAnimation;
  bool _scanned = false;
  String? _result;

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

  void _simulateScan() {
    setState(() {
      _scanned = true;
      _result = 'Pasillo A — Frente a Laboratorio de Cómputo 1\nEdificio B, Planta baja';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      appBar: AppBar(title: const Text('Escanear QR')),
      body: SafeArea(
        child: Padding(
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
                onTap: _simulateScan,
              ),
              const SizedBox(height: 32),
              if (_scanned && _result != null) ...[
                _ResultCard(result: _result!),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => setState(() {
                    _scanned = false;
                    _result = null;
                  }),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Escanear otro'),
                ),
              ] else
                TextButton.icon(
                  onPressed: _simulateScan,
                  icon: const Icon(Icons.touch_app_rounded),
                  label: const Text('Simular escaneo (demo)'),
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
  const _ResultCard({required this.result});

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
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.navigation_rounded, size: 18),
            label: const Text('Navegar desde aquí'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }
}