import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/providers/auth_provider.dart';
import 'package:sinait/data/providers/navigation_provider.dart';
import 'package:sinait/data/providers/voice_provider.dart';
import 'package:sinait/data/providers/feed_provider.dart';
import 'package:sinait/services/voice/voice_service.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';
import 'package:sinait/presentation/widgets/announcement_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(voiceProvider.notifier).initialize();
      ref.read(feedProvider.notifier).loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final navState = ref.watch(navigationProvider);
    final voiceState = ref.watch(voiceProvider);
    final feedState = ref.watch(feedProvider);

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 0),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context, authState),
                    const SizedBox(height: 24),
                    if (navState.currentNode != null)
                      _positionBanner(navState),
                    const SizedBox(height: 12),
                    _voiceButton(context, voiceState),
                    if (navState.hasActiveRoute) ...[
                      const SizedBox(height: 16),
                      _activeNavBanner(navState),
                    ],
                    const SizedBox(height: 32),
                    if (feedState.announcements.isNotEmpty) ...[
                      Text(
                        'Avisos del campus',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 14),
                      ...feedState.announcements.map((a) =>
                        AnnouncementCard(
                          announcement: a,
                          onDismiss: () => ref.read(feedProvider.notifier).dismiss(a.id),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'Accesos rápidos',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    _quickGrid(context),
                    const SizedBox(height: 32),
                    Text(
                      'Últimos destinos',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 18),
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

  Widget _header(BuildContext context, AuthState authState) {
    final name = authState.isAuthenticated ? authState.displayName.split(' ').first : '';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authState.isAuthenticated ? 'Hola, $name 👋' : 'Hola 👋',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '¿A dónde vas hoy?',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accent.withOpacity(0.2), width: 1.5),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.surface,
              backgroundImage: authState.photoUrl != null ? NetworkImage(authState.photoUrl!) : null,
              child: authState.photoUrl == null ? const Icon(Icons.person_rounded, color: AppTheme.textSecondary, size: 20) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _positionBanner(NavigationState navState) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.success.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: AppTheme.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Posición: ${navState.currentNode!.name}',
              style: const TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.scanner),
            child: Text('ACTUALIZAR',
                style: TextStyle(color: AppTheme.success.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _voiceButton(BuildContext context, VoiceControlState voiceState) {
    final isListening = voiceState.voiceState == VoiceState.listening;
    const softBlue = AppTheme.accent;
    const deepBlue = Color(0xFF0EA5E9);

    return GestureDetector(
      onTap: () => ref.read(voiceProvider.notifier).listenAndExecute(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: isListening
              ? const LinearGradient(colors: [Color(0xFFF87171), Color(0xFFEF4444)])
              : const LinearGradient(
                  colors: [softBlue, deepBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: (isListening ? const Color(0xFFF87171) : softBlue).withOpacity(0.25),
              blurRadius: isListening ? 25 : 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isListening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isListening ? 'ESCUCHANDO...' : 'ASISTENTE SINAIT',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isListening
                        ? (voiceState.recognizedText.isEmpty ? 'Te escucho...' : voiceState.recognizedText)
                        : '¿A dónde quieres ir?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeNavBanner(NavigationState navState) {
    final route = navState.activeRoute!;
    final step = route.steps[navState.currentStepIndex];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.accent.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation_rounded, color: AppTheme.accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'RUTA A ${route.destination.name.toUpperCase()}',
                  style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                ),
              ),
              GestureDetector(
                onTap: () => ref.read(navigationProvider.notifier).cancelNavigation(),
                child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: 18),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            step.voiceInstruction,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: navState.progress,
                    minHeight: 6,
                    backgroundColor: Colors.white.withOpacity(0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '${route.totalDistance.round()}m',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => ref.read(voiceProvider.notifier).speakCurrentStep(),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text('REPETIR'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppTheme.accent.withOpacity(0.2))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => ref.read(voiceProvider.notifier).nextStepAndSpeak(),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('SIGUIENTE'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickGrid(BuildContext context) {
    final items = [
      (Icons.school_rounded, 'Aulas', AppRoutes.map),
      (Icons.science_rounded, 'Laboratorios', AppRoutes.map),
      (Icons.qr_code_scanner_rounded, 'Escanear', AppRoutes.scanner),
      (Icons.map_rounded, 'Mapa', AppRoutes.map),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.35,
      children: items.map((item) => _QuickCard(icon: item.$1, label: item.$2, route: item.$3)).toList(),
    );
  }

  Widget _recentList() {
    final recents = [
      (Icons.computer_rounded, 'Lab. de Cómputo 1', '2 min'),
      (Icons.local_library_rounded, 'Biblioteca', '5 min'),
      (Icons.sports_soccer_rounded, 'Cancha deportiva', '8 min'),
    ];
    return Column(
      children: recents.map((r) => _RecentTile(icon: r.$1, label: r.$2, time: r.$3)).toList(),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  const _QuickCard({required this.icon, required this.label, required this.route});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.03)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.accent.withOpacity(0.8), size: 30),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
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
  const _RecentTile({required this.icon, required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.02)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary.withOpacity(0.5), size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Text('~$time', style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.white.withOpacity(0.1)),
        ],
      ),
    );
  }
}