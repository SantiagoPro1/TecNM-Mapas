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
    // Inicializar voz y cargar feed general al entrar
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context, authState),
                    const SizedBox(height: 20),

                    // Indicador de posición actual
                    if (navState.currentNode != null)
                      _positionBanner(navState),

                    const SizedBox(height: 12),

                    // Botón de voz principal
                    _voiceButton(context, voiceState),

                    // Navegación activa
                    if (navState.hasActiveRoute) ...[
                      const SizedBox(height: 16),
                      _activeNavBanner(navState),
                    ],

                    const SizedBox(height: 28),

                    // Feed contextual
                    if (feedState.announcements.isNotEmpty) ...[
                      Text(
                        'Avisos del campus',
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 12),
                      ...feedState.announcements.map((a) =>
                        AnnouncementCard(
                          announcement: a,
                          onDismiss: () =>
                            ref.read(feedProvider.notifier).dismiss(a.id),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

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

  Widget _header(BuildContext context, AuthState authState) {
    final name = authState.isAuthenticated
        ? authState.displayName.split(' ').first
        : '';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authState.isAuthenticated ? 'Hola, $name 👋' : 'Hola 👋',
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
          onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
            backgroundImage: authState.photoUrl != null
                ? NetworkImage(authState.photoUrl!)
                : null,
            child: authState.photoUrl == null
                ? const Icon(Icons.person_rounded, color: AppTheme.accent)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _positionBanner(NavigationState navState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded,
              color: AppTheme.success, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Posición: ${navState.currentNode!.name}',
              style: const TextStyle(
                  color: AppTheme.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.scanner),
            child: const Text('Actualizar',
                style: TextStyle(
                    color: AppTheme.success,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }

  Widget _voiceButton(BuildContext context, VoiceControlState voiceState) {
    final isListening = voiceState.voiceState == VoiceState.listening;

    return GestureDetector(
      onTap: () => ref.read(voiceProvider.notifier).listenAndExecute(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: isListening
              ? const LinearGradient(colors: [Color(0xFFFF5252), Color(0xFFFF1744)])
              : const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (isListening ? const Color(0xFFFF5252) : const Color(0xFF00E5FF)).withOpacity(0.4),
              blurRadius: isListening ? 30 : 15,
              spreadRadius: isListening ? 5 : 0,
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isListening ? Icons.hearing_rounded : Icons.mic_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isListening ? 'ESCUCHANDO...' : 'SISTEMA DE VOZ',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isListening
                        ? (voiceState.recognizedText.isEmpty
                            ? 'Esperando...'
                            : voiceState.recognizedText)
                        : '¿A dónde quieres ir?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation_rounded,
                  color: AppTheme.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Navegando a ${route.destination.name}',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: () => ref.read(navigationProvider.notifier).cancelNavigation(),
                child: const Icon(Icons.close_rounded,
                    color: AppTheme.textSecondary, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step.voiceInstruction,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          // Progress + controls
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: navState.progress,
                  backgroundColor: const Color(0xFF333333),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${route.totalDistance.round()}m · ~${route.estimatedMinutes.round()} min',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(voiceProvider.notifier).speakCurrentStep(),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text('Repetir'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: const BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(voiceProvider.notifier).nextStepAndSpeak(),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Siguiente'),
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.accent.withOpacity(0.15), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.accent, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.accent.withOpacity(0.7), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Text('~$time',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: AppTheme.accent.withOpacity(0.5)),
        ],
      ),
    );
  }
}