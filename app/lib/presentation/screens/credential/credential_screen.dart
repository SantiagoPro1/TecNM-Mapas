import 'package:flutter/material.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

class CredentialScreen extends StatefulWidget {
  const CredentialScreen({super.key});

  @override
  State<CredentialScreen> createState() => _CredentialScreenState();
}

class _CredentialScreenState extends State<CredentialScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.95, end: 1.05).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      appBar: AppBar(title: const Text('Credencial Digital')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _CredentialCard(pulseAnimation: _pulseAnimation),
              const SizedBox(height: 28),
              _InfoSection(),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.share_rounded, size: 22),
                label: const Text('Compartir credencial'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CredentialCard extends StatelessWidget {
  final Animation<double> pulseAnimation;
  const _CredentialCard({required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2744), Color(0xFF0D1B35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TECNOLÓGICO NACIONAL DE MÉXICO',
                      style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  SizedBox(height: 2),
                  Text('Campus Colima',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.success.withValues(alpha: 0.5)),
                ),
                child: const Text('ACTIVA',
                    style: TextStyle(
                        color: AppTheme.success,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 42,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
            child: const Icon(Icons.person_rounded,
                size: 52, color: AppTheme.accent),
          ),
          const SizedBox(height: 16),
          const Text('Juanpablo E. Gómez Domínguez',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('22460290',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Ing. en Sistemas Computacionales',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          ScaleTransition(
            scale: pulseAnimation,
            child: Container(
              width: 140,
              height: 140,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.qr_code_2_rounded,
                    size: 100, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'El QR se actualiza automáticamente cada 60 segundos',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.calendar_today_rounded, 'Semestre activo', '2025-A'),
      (Icons.school_rounded, 'Nivel', 'Licenciatura'),
      (Icons.verified_rounded, 'Estado', 'Alumno regular'),
    ];
    return Column(
      children: items
          .map((item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF333333)),
                ),
                child: Row(
                  children: [
                    Icon(item.$1, color: AppTheme.accent, size: 24),
                    const SizedBox(width: 14),
                    Text(item.$2,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14)),
                    const Spacer(),
                    Text(item.$3,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}