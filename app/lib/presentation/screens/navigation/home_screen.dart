import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/constants/campus_locations.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/providers/auth_provider.dart';
import 'package:sinait/data/providers/navigation_provider.dart';
import 'package:sinait/data/providers/voice_provider.dart';
import 'package:sinait/data/providers/feed_provider.dart';
import 'package:sinait/services/voice/voice_service.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';
import 'package:sinait/presentation/widgets/announcement_card.dart';
import 'package:sinait/data/models/announcement.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    Future.microtask(() {
      ref.read(voiceProvider.notifier).initialize();
      ref.read(feedProvider.notifier).loadAll();
    });
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final navState = ref.watch(navigationProvider);
    final voiceState = ref.watch(voiceProvider);
    final feedState = ref.watch(feedProvider);

    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.status == NavStatus.error && next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!, style: const TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF070E1A),
      bottomNavigationBar: const BottomNav(currentIndex: 0),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(authState),
                    const SizedBox(height: 24),
                    _buildVoiceCard(voiceState),
                    const SizedBox(height: 20),
                    if (navState.currentNode != null) ...[
                      _buildLocationChip(navState),
                      const SizedBox(height: 16),
                    ],
                    if (navState.hasActiveRoute) ...[
                      _buildActiveNav(navState),
                      const SizedBox(height: 20),
                    ],
                    // Venues Section
                    _sectionTitle('Explora un lugar'),
                    const SizedBox(height: 14),
                    _buildVenueCards(),
                    const SizedBox(height: 28),
                    // Quick Actions
                    _sectionTitle('Acciones rápidas'),
                    const SizedBox(height: 14),
                    _buildQuickActions(),
                    const SizedBox(height: 28),
                    // Destinations
                    _sectionTitle('Destinos populares'),
                    const SizedBox(height: 14),
                    _buildDestinations(),
                    // Announcements
                    if (feedState.announcements.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _sectionTitle('Avisos'),
                      const SizedBox(height: 14),
                      ...feedState.announcements.map((a) =>
                        AnnouncementCard(
                          announcement: a,
                          onDismiss: () => ref.read(feedProvider.notifier).dismiss(a.id),
                          onTap: () => _showAnnouncementDetails(context, a),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3));
  }

  // ─── HEADER ───
  Widget _buildHeader(AuthState authState) {
    final name = authState.isAuthenticated ? authState.displayName.split(' ').first : 'Invitado';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_getGreeting()} 👋', style: TextStyle(color: const Color(0xFF00E5FF).withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF0077B6)]),
              boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), blurRadius: 12)],
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF0D1B2A),
              backgroundImage: authState.photoUrl != null ? NetworkImage(authState.photoUrl!) : null,
              child: authState.photoUrl == null ? const Icon(Icons.person_rounded, color: Color(0xFF00E5FF), size: 22) : null,
            ),
          ),
        ),
      ],
    );
  }

  // ─── VOICE CARD ───
  Widget _buildVoiceCard(VoiceControlState voiceState) {
    final isListening = voiceState.voiceState == VoiceState.listening;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(voiceProvider.notifier).listenAndExecute(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isListening
                ? [const Color(0xFFFF5252), const Color(0xFFFF1744)]
                : [const Color(0xFF00E5FF), const Color(0xFF0077B6)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: (isListening ? const Color(0xFFFF5252) : const Color(0xFF00E5FF)).withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(isListening ? Icons.graphic_eq_rounded : Icons.mic_rounded, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isListening ? 'ESCUCHANDO...' : 'ASISTENTE DE VOZ',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(
                    isListening ? (voiceState.recognizedText.isEmpty ? 'Habla ahora...' : voiceState.recognizedText) : '¿A dónde quieres ir?',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.5), size: 18),
          ],
        ),
      ),
    );
  }

  // ─── LOCATION CHIP ───
  Widget _buildLocationChip(NavigationState navState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF00E676).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location_rounded, color: Color(0xFF00E676), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(navState.currentNode!.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pushNamed(context, AppRoutes.scanner),
            child: Text('CAMBIAR', style: TextStyle(color: const Color(0xFF00E676).withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  // ─── VENUE CARDS (Horizontal scroll) ───
  Widget _buildVenueCards() {
    final venues = [
      ('TecNM Colima', 'Campus universitario', Icons.school_rounded, const Color(0xFF00E5FF), '30+ edificios', 19.2628, -103.7233, 17.0),
      ('Sendera', 'Centro comercial', Icons.shopping_bag_rounded, const Color(0xFFFF9800), '15+ tiendas', 19.27580, -103.71730, 17.5),
      ('Zentralia', 'Centro comercial', Icons.store_rounded, const Color(0xFFE040FB), '25+ tiendas', 19.26691, -103.69754, 17.5),
    ];

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: venues.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final v = venues[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pushNamed(context, AppRoutes.map, arguments: {'lat': v.$6, 'lng': v.$7, 'zoom': v.$8}),
            child: Container(
              width: 200,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [v.$4.withValues(alpha: 0.15), v.$4.withValues(alpha: 0.05)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: v.$4.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: v.$4.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(v.$3, color: v.$4, size: 24),
                  ),
                  const Spacer(),
                  Text(v.$1, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(v.$5, style: TextStyle(color: v.$4.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── QUICK ACTIONS (Row of 4) ───
  Widget _buildQuickActions() {
    final actions = [
      (Icons.qr_code_scanner_rounded, 'Escanear', AppRoutes.scanner, const Color(0xFF00E5FF)),
      (Icons.map_rounded, 'Mapa', AppRoutes.map, const Color(0xFF69F0AE)),
      (Icons.explore_rounded, 'Explorar', AppRoutes.map, const Color(0xFFFFAB40)),
      (Icons.settings_rounded, 'Ajustes', AppRoutes.settings, const Color(0xFF90CAF9)),
    ];

    return Row(
      children: actions.map((a) {
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pushNamed(context, a.$3),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: a.$4.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: a.$4.withValues(alpha: 0.15)),
                  ),
                  child: Icon(a.$1, color: a.$4, size: 26),
                ),
                const SizedBox(height: 8),
                Text(a.$2, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── DESTINATIONS ───
  Widget _buildDestinations() {
    final destinations = [
      (Icons.computer_rounded, 'Sistemas y Computación', 'Edificio R · TecNM', CampusLocations.sistemas, const Color(0xFF00E5FF)),
      (Icons.local_library_rounded, 'Centro de Información', 'Edificio B · TecNM', CampusLocations.edificioB, const Color(0xFF69F0AE)),
      (Icons.restaurant_rounded, 'Cafetería Norte', 'Edificio C · TecNM', CampusLocations.cafeteria, const Color(0xFFFFAB40)),
    ];

    return Column(
      children: destinations.map((d) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final navState = ref.read(navigationProvider);
            if (navState.currentNode == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Primero indica dónde estás', style: TextStyle(fontWeight: FontWeight.w600)),
                  backgroundColor: AppTheme.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
              Navigator.pushNamed(context, AppRoutes.scanner);
              return;
            }
            ref.read(navigationProvider.notifier).navigateTo(d.$4);
            Navigator.pushNamed(context, AppRoutes.map);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: d.$5.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(d.$1, color: d.$5, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.$2, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(d.$3, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.2), size: 22),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── ACTIVE NAV BANNER ───
  Widget _buildActiveNav(NavigationState navState) {
    final route = navState.activeRoute!;
    final step = route.steps[navState.currentStepIndex];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.08), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation_rounded, color: Color(0xFF00E5FF), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('RUTA A ${route.destination.name.toUpperCase()}', style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.read(navigationProvider.notifier).cancelNavigation(),
                child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(step.voiceInstruction, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: navState.progress, minHeight: 6, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation(Color(0xFF00E5FF))),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => ref.read(voiceProvider.notifier).speakCurrentStep(),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text('REPETIR', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF00E5FF), padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (navState.status == NavStatus.arrived) {
                      ref.read(navigationProvider.notifier).cancelNavigation();
                    } else {
                      ref.read(voiceProvider.notifier).nextStepAndSpeak();
                    }
                  },
                  icon: Icon(
                    navState.status == NavStatus.arrived ? Icons.check_circle_outline_rounded : Icons.arrow_forward_rounded,
                    size: 18,
                  ),
                  label: Text(
                    navState.status == NavStatus.arrived ? 'FINALIZAR' : 'SIGUIENTE',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navState.status == NavStatus.arrived ? Colors.greenAccent : const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF0D1B2A),
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

  void _showAnnouncementDetails(BuildContext context, Announcement a) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 32),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.campaign_rounded, color: AppTheme.accent, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(a.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2))),
              ],
            ),
            const SizedBox(height: 24),
            Text(a.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16, height: 1.5)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: const Color(0xFF0D1B2A),
                  padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                child: const Text('ENTENDIDO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}