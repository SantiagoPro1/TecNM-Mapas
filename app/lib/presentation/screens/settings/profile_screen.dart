import 'package:flutter/material.dart';
import 'package:sinait/core/theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil estudiantil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _AvatarSection(),
            const SizedBox(height: 32),
            const _InfoCard(
              title: 'Datos académicos',
              items: [
                (Icons.badge_rounded, 'Matrícula', '22460290'),
                (Icons.school_rounded, 'Carrera', 'Ing. Sistemas Computacionales'),
                (Icons.location_city_rounded, 'Campus', 'TecNM Colima'),
                (Icons.calendar_today_rounded, 'Semestre', '8vo — 2025-A'),
              ],
            ),
            const SizedBox(height: 16),
            const _InfoCard(
              title: 'Accesibilidad configurada',
              items: [
                (Icons.mic_rounded, 'Voz', 'Activada'),
                (Icons.translate_rounded, 'Idioma', 'Español (México)'),
                (Icons.speed_rounded, 'Velocidad de voz', '1.0x'),
              ],
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.edit_rounded, size: 20),
              label: const Text('Editar perfil'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
              child: const Icon(Icons.person_rounded,
                  size: 64, color: AppTheme.accent),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  size: 16, color: Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Juanpablo E. Gómez Domínguez',
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'juanpablo.gomez@colima.tecnm.mx',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(IconData, String, String)> items;

  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 16),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(item.$1, color: AppTheme.accent, size: 22),
                    const SizedBox(width: 12),
                    Text(item.$2,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14)),
                    const Spacer(),
                    Text(item.$3,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}