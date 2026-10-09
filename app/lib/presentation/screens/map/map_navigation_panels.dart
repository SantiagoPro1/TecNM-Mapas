import 'package:flutter/material.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/data/providers/navigation_provider.dart';

/// Encabezado superior de navegación activa giro a giro estilo Google Maps.
class MapNavigationHeader extends StatelessWidget {
  final RouteStep step;
  final VoidCallback onRepeatVoice;
  final VoidCallback onCancel;

  const MapNavigationHeader({
    super.key,
    required this.step,
    required this.onRepeatVoice,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final distMeters = step.distanceMeters.round();
    final distLabel = distMeters > 0 ? 'En $distMeters m' : 'Ahora';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(step.maneuverIcon, color: cs.onPrimary, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(distLabel,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
                Text(step.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  step.voiceInstruction,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onRepeatVoice,
            tooltip: 'Repetir indicación',
            icon: Icon(Icons.volume_up_rounded, color: cs.primary),
            iconSize: 22,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: 'Detener navegación',
            icon: Icon(Icons.close_rounded,
                color: cs.onSurface.withValues(alpha: 0.6)),
            iconSize: 22,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// Panel inferior de control y progreso de ruta activa estilo Google Maps.
class MapNavigationSummary extends StatelessWidget {
  final NavigationState navState;
  final NavRoute route;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onCancel;

  const MapNavigationSummary({
    super.key,
    required this.navState,
    required this.route,
    required this.onPrevious,
    required this.onNext,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isArrived = navState.status == NavStatus.arrived;

    final distanceMeters =
        navState.routeDistanceMeters ?? route.totalDistance.round();
    final etaMinutes = navState.routeDistanceMeters != null
        ? (navState.routeDistanceMeters! / 72).round()
        : route.estimatedMinutes.round();
    final distanceLabel = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '$distanceMeters m';
    final etaLabel = etaMinutes < 1 ? '<1 min' : '$etaMinutes min';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isArrived
              ? cs.tertiary.withValues(alpha: 0.6)
              : cs.outline.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fila 1: Tiempo estimado, distancia y progreso
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isArrived
                      ? cs.tertiary.withValues(alpha: 0.15)
                      : cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isArrived
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      color: isArrived ? cs.tertiary : cs.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(isArrived ? 'Llegaste' : etaLabel,
                          style: TextStyle(
                            color: isArrived ? cs.tertiary : cs.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          )),
                    ),
                  ],
                ),
              ),
              Text(
                distanceLabel,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.65),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Paso ${navState.currentStepIndex + 1} de ${route.steps.length}',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Nombre del destino
          Row(
            children: [
              Icon(Icons.place_rounded, color: cs.primary, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  route.destination.name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Barra de progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: navState.progress,
              minHeight: 5,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(
                isArrived ? cs.tertiary : cs.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!isArrived) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Paso anterior',
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Siguiente paso',
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCancel,
                icon: Icon(
                  isArrived
                      ? Icons.check_circle_outline_rounded
                      : Icons.close_rounded,
                  size: 18,
                ),
                label: Text(
                  isArrived ? 'FINALIZAR' : 'DETENER RUTA',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isArrived ? cs.tertiary : const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
