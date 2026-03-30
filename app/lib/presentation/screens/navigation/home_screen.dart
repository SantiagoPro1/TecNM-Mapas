import 'package:flutter/material.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 0),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),
                    const SizedBox(height: 28),
                    _voiceButton(context),
                    const SizedBox(height: 28),
                    Text(
                      'Accesos rápidos',
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    _quickGrid(context),
                    const SizedBox(height: 28),
                    Text(
                      'Últimos destinos',
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    _recentList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Builder(builder: (context) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola 👋',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '¿A dónde vas hoy?',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.profile),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
              child: const Icon(Icons.person_rounded, color: AppTheme.accent),
            ),
          ),
        ],
      );
    });
  }

  Widget _voiceButton(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.mic_rounded, size: 40, color: Colors.black),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doble toque o di',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '"Llévame a..."',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickGrid(BuildContext context) {
    final items = [
      (Icons.school_rounded, 'Aulas', AppRoutes.map),
      (Icons.science_rounded, 'Laboratorios', AppRoutes.map),
      (Icons.qr_code_scanner_rounded, 'Escanear QR', AppRoutes.scanner),
      (Icons.map_rounded, 'Mapa', AppRoutes.map),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: items
          .map((item) => _QuickCard(
              icon: item.$1, label: item.$2, route: item.$3))
          .toList(),
    );
  }

  Widget _recentList() {
    final recents = [
      (Icons.computer_rounded, 'Laboratorio de Cómputo 1', '2 min'),
      (Icons.local_library_rounded, 'Biblioteca', '5 min'),
      (Icons.sports_soccer_rounded, 'Cancha deportiva', '8 min'),
    ];
    return Column(
      children: recents
          .map((r) => _RecentTile(icon: r.$1, label: r.$2, time: r.$3))
          .toList(),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  const _QuickCard(
      {required this.icon, required this.label, required this.route});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.accent, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  const _RecentTile(
      {required this.icon, required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 16)),
          ),
          Text('~$time',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: AppTheme.textSecondary),
        ],
      ),
    );
  }
}