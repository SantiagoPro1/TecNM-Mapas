import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/providers/auth_provider.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/venue_provider.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:navia/data/providers/feed_provider.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';
import 'package:navia/presentation/widgets/announcement_card.dart';
import 'package:navia/data/models/announcement.dart';
import 'package:navia/services/update/app_update_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 1. Cargar avisos (feed visual)
      ref.read(feedProvider.notifier).loadAll();

      // 2. Escalonar inicializaciones en segundo plano para que la UI entre fluida a 60/120 FPS
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        ref.read(voiceProvider.notifier).initialize();
      });

      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        _warmUpLocationPermission();
      });

      Future.delayed(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        AppUpdateService.verificarActualizacion(context);
      });
    });
  }

  /// Pide el permiso de ubicación de forma no intrusiva tras abrir Inicio.
  /// Antes, el primer diálogo del sistema ("¿Permitir que TecNM Mapas acceda a tu ubicación?")
  /// aparecía justo al entrar al mapa, así que la primera vez que alguien lo abría,
  /// veía el mapa sin GPS por un momento mientras decidía.
  Future<void> _warmUpLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {
      // Silencioso a propósito — ver comentario arriba.
    }
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
    final feedState = ref.watch(feedProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Solo re-render aquí cuando estos booleanos cambian de valor (p.ej. al
    // iniciar/cancelar una ruta), no en cada actualización de GPS — el
    // contenido que sí cambia con el GPS vive en _LocationChip/_ActiveNavCard,
    // que se re-renderizan solos sin arrastrar toda esta pantalla con ellos.
    final hasCurrentNode =
        ref.watch(navigationProvider.select((s) => s.currentNode != null));
    final hasActiveRoute =
        ref.watch(navigationProvider.select((s) => s.hasActiveRoute));

    // Mantener la posición sincronizada por GPS en segundo plano SOLO si hay una ruta activa.
    // Esto evita activar el hardware de GPS a alta precisión (bestForNavigation) en reposo,
    // eliminando por completo el congelamiento (freeze) de varios segundos al entrar a Inicio.
    if (hasActiveRoute) {
      ref.listen<AsyncValue<Position>>(currentLocationStreamProvider, (_, next) {
        next.whenData((position) {
          ref.read(navigationProvider.notifier).setPositionByCoordinates(
                position.latitude,
                position.longitude,
              );
        });
      });
    }

    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.status == NavStatus.error &&
          next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: cs.error,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
                    if (hasCurrentNode) ...[
                      const _LocationChip(),
                      const SizedBox(height: 16),
                    ],
                    if (hasActiveRoute) ...[
                      const _ActiveNavCard(),
                      const SizedBox(height: 20),
                    ],
                    // Venues Section
                    _sectionTitle('Sedes'),
                    const SizedBox(height: 14),
                    _buildVenueCards(),
                    // Announcements
                    if (feedState.announcements.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _sectionTitle('Avisos'),
                      const SizedBox(height: 14),
                      ...feedState.announcements.map(
                        (a) => AnnouncementCard(
                          announcement: a,
                          onDismiss: () =>
                              ref.read(feedProvider.notifier).dismiss(a.id),
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
    final cs = Theme.of(context).colorScheme;
    return Text(text,
        style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3));
  }

  // ─── HEADER ───
  Widget _buildHeader(AuthState authState) {
    final cs = Theme.of(context).colorScheme;
    final name = authState.isAuthenticated
        ? authState.displayName.split(' ').first
        : 'Invitado';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_getGreeting(),
                  style: TextStyle(
                      color: cs.primary.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(name,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Ajustes',
          icon: Icon(
            Icons.settings_outlined,
            color: cs.onSurface.withValues(alpha: 0.8),
            size: 24,
          ),
          onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outline),
            ),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHighest,
              ),
              clipBehavior: Clip.antiAlias,
              child: authState.photoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: authState.photoUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(Icons.person_rounded,
                            color: cs.primary, size: 22),
                      ),
                    )
                  : Center(
                      child: Icon(Icons.person_rounded,
                          color: cs.primary, size: 22),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── VENUE CARDS (grid de 3 columnas) ───
  Widget _buildVenueCards() {
    final cs = Theme.of(context).colorScheme;
    // Las 9 sedes (TecNM Colima + las 8 del Evento Nacional Deportivo) se
    // muestran todas de un vistazo, en cuadrícula de 3x3 — sin necesidad de
    // deslizar. El mapa de las sedes sin coordenadas reales todavía cae a un
    // pin genérico en su centro hasta que el admin les asigne su
    // ubicación/POIs reales.
    final venues = ref.watch(venueRegistryProvider);

    // Ancho máximo para que las tarjetas no se estiren en ventanas anchas
    // (escritorio/web) — en celular (la plataforma principal) esto no hace
    // ninguna diferencia, ya ocupa todo el ancho disponible de por sí.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          children: venues.map((v) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pushReplacementNamed(
                  context, AppRoutes.map,
                  arguments: {
                    'venueId': v.id,
                    'lat': v.centerLat,
                    'lng': v.centerLng,
                    'zoom': v.defaultZoom,
                  }),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Icon(v.icon, color: cs.primary, size: 18),
                    ),
                    const Spacer(),
                    Text(v.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(v.shortDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.55),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showAnnouncementDetails(BuildContext context, Announcement a) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 32),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child:
                      Icon(Icons.campaign_rounded, color: cs.primary, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                    child: Text(a.title,
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.2))),
              ],
            ),
            const SizedBox(height: 24),
            Text(a.body,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontSize: 16,
                    height: 1.5)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md))),
                child: const Text('ENTENDIDO',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── LOCATION CHIP ───
// Widget aparte (no un método de HomeScreen) para que solo esta tarjeta se
// vuelva a dibujar cuando cambia el nodo actual (cada pocos metros de GPS
// mientras hay una ruta activa) en vez de toda la pantalla de inicio.
class _LocationChip extends ConsumerWidget {
  const _LocationChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = ref.watch(navigationProvider.select((s) => s.currentNode));
    if (node == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.tertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.my_location_rounded, color: cs.tertiary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(node.name,
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.map),
            child: Text('CAMBIAR',
                style: TextStyle(
                    color: cs.tertiary.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }
}

// ─── ACTIVE NAV CARD (estilo Google Maps) ───
// Igual que _LocationChip: widget propio para que la barra de progreso y el
// paso actual se actualicen con el GPS sin re-renderizar toda la pantalla.
class _ActiveNavCard extends ConsumerWidget {
  const _ActiveNavCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);
    final route = navState.activeRoute;
    if (route == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final step = route.steps[navState.currentStepIndex];
    final isArrived = navState.status == NavStatus.arrived;

    final distanceMeters =
        navState.routeDistanceMeters ?? route.totalDistance.round();
    final etaMinutes = navState.routeDistanceMeters != null
        ? (navState.routeDistanceMeters! / 72).round()
        : route.estimatedMinutes.round();
    final distanceLabel = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '$distanceMeters m';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.navigation_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('RUTA A ${route.destination.name.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              ),
              if (!isArrived) ...[
                const SizedBox(width: 8),
                Icon(Icons.straighten_rounded,
                    color: cs.onSurface.withValues(alpha: 0.4), size: 13),
                const SizedBox(width: 3),
                Text(distanceLabel,
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Icon(Icons.schedule_rounded,
                    color: cs.onSurface.withValues(alpha: 0.4), size: 13),
                const SizedBox(width: 3),
                Text(etaMinutes < 1 ? '<1 min' : '$etaMinutes min',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
              const SizedBox(width: 8),
              Tooltip(
                message: 'Finalizar ruta',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      ref.read(navigationProvider.notifier).cancelNavigation(),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded,
                        color: cs.onSurface.withValues(alpha: 0.6), size: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(step.voiceInstruction,
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.4)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
                value: navState.progress,
                minHeight: 6,
                backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(cs.primary)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: cs.outline),
                ),
                child: IconButton(
                  onPressed: () =>
                      ref.read(voiceProvider.notifier).speakCurrentStep(),
                  icon: Icon(Icons.volume_up_rounded, color: cs.primary),
                  tooltip: 'Repetir indicación',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (isArrived) {
                      ref.read(navigationProvider.notifier).cancelNavigation();
                    } else {
                      ref.read(voiceProvider.notifier).nextStepAndSpeak();
                    }
                  },
                  icon: Icon(
                    isArrived
                        ? Icons.check_circle_outline_rounded
                        : Icons.arrow_forward_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isArrived ? 'FINALIZAR' : 'SIGUIENTE',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isArrived ? cs.tertiary : cs.primary,
                    foregroundColor: isArrived ? Colors.white : cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
