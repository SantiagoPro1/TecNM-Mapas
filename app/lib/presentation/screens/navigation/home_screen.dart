import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/providers/auth_provider.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/venue_provider.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';
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
      // Escalonar inicializaciones en segundo plano para que la UI entre fluida a 60/120 FPS
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Solo re-render aquí cuando estos booleanos cambian de valor (p.ej. al
    // iniciar/cancelar una ruta), no en cada actualización de GPS — el
    // contenido que sí cambia con el GPS vive en _LocationChip/_ActiveNavCard,
    // que se re-renderizan solos sin arrastrar toda esta pantalla con ellos.
    final hasCurrentNode = ref.watch(navigationProvider.select(
        (s) => s.currentNode != null && s.currentNode!.name.trim().isNotEmpty));
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
                    _buildVenueCards(),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${_getGreeting()}, ',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.65),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(context, AppRoutes.settings);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.settings_outlined,
                color: cs.onSurface.withValues(alpha: 0.75),
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pushNamed(context, AppRoutes.profile);
          },
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Container(
              width: 40,
              height: 40,
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
                            color: cs.primary, size: 20),
                      ),
                    )
                  : Center(
                      child: Icon(Icons.person_rounded,
                          color: cs.primary, size: 20),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── VENUE CARDS (Campus Principal destacado + Sedes Deportivas) ───
  Widget _buildVenueCards() {
    final cs = Theme.of(context).colorScheme;
    final venues = ref.watch(venueRegistryProvider);
    final mainVenue = venues.firstWhere(
      (v) => v.id == 'tec_colima',
      orElse: () => venues.first,
    );
    final sportVenues = venues.where((v) => v.id != mainVenue.id).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título de sección Sedes
            Row(
              children: [
                _sectionTitle('Campus Principal'),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'En vivo',
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Tarjeta destacada del Campus Principal
            Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.map,
                    arguments: {
                      'venueId': mainVenue.id,
                      'lat': mainVenue.centerLat,
                      'lng': mainVenue.centerLng,
                      'zoom': mainVenue.defaultZoom,
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.22),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.10),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: cs.primary.withValues(alpha: 0.20),
                                width: 0.8,
                              ),
                            ),
                            child: Icon(
                              mainVenue.icon,
                              color: cs.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mainVenue.label,
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '30+ edificios • Navegación guiada paso a paso',
                                  style: TextStyle(
                                    color: cs.onSurface.withValues(alpha: 0.60),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: cs.primary,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Sección Sedes Deportivas
            Row(
              children: [
                _sectionTitle('Sedes Deportivas'),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${sportVenues.length} sedes',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sedes oficiales del LXVIII Evento Nacional Deportivo TecNM',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),

            // Grid de 2 columnas para las sedes deportivas
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sportVenues.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.45,
              ),
              itemBuilder: (context, index) {
                final v = sportVenues[index];
                return Material(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.map,
                        arguments: {
                          'venueId': v.id,
                          'lat': v.centerLat,
                          'lng': v.centerLng,
                          'zoom': v.defaultZoom,
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.18),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Icon(
                                  v.icon,
                                  color: cs.primary,
                                  size: 16,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurface.withValues(alpha: 0.3),
                                size: 16,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            v.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            v.shortDescription,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.55),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
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
    if (node == null || node.name.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'UBICACIÓN ACTUAL',
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  node.name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushReplacementNamed(context, AppRoutes.map);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'CAMBIAR',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pushReplacementNamed(context, AppRoutes.map);
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.primary.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(step.maneuverIcon, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('RUTA EN CURSO',
                            style: TextStyle(
                                color: cs.primary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 2),
                        Text(
                          route.destination.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isArrived) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_walk_rounded,
                              color: cs.onSurface.withValues(alpha: 0.6), size: 14),
                          const SizedBox(width: 4),
                          Text(distanceLabel,
                              style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Text('·',
                              style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          Text(etaMinutes < 1 ? '<1 min' : '$etaMinutes min',
                              style: TextStyle(
                                  color: cs.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Finalizar ruta',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(navigationProvider.notifier).cancelNavigation();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.displayTitle,
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.voiceInstruction,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                    value: navState.progress,
                    minHeight: 6,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(cs.primary)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                    ),
                    child: IconButton(
                      onPressed: () =>
                          ref.read(voiceProvider.notifier).speakCurrentStep(),
                      icon: Icon(Icons.volume_up_rounded, color: cs.primary),
                      tooltip: 'Repetir indicación',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pushReplacementNamed(context, AppRoutes.map);
                      },
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text(
                        'VER EN EL MAPA',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.3),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                    ),
                  ),
                  if (isArrived) ...[
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(navigationProvider.notifier).cancelNavigation();
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('FINALIZAR',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.tertiary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
