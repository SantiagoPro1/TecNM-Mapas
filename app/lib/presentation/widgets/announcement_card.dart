import 'package:flutter/material.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/models/announcement.dart';

/// Tarjeta de aviso contextual para el feed del HomeScreen.
///
/// Muestra avisos geoposicionados con estilo según su tipo,
/// con soporte para dismiss por deslizamiento.
class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    this.onDismiss,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: Key(announcement.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Icon(Icons.close_rounded, color: cs.error, size: 24),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: _borderColor(context, cs),
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícono del tipo
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _iconColor(context, cs).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(_icon, color: _iconColor(context, cs), size: 22),
              ),
              const SizedBox(width: 14),
              // Contenido
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Etiqueta de tipo
                    Text(
                      announcement.typeLabel,
                      style: TextStyle(
                        color: _iconColor(context, cs),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Título
                    Text(
                      announcement.title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Cuerpo
                    Text(
                      announcement.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.55),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Estilos según tipo de aviso ─────────────────────────────

  Color _warningColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppWarning.dark
          : AppWarning.light;

  Color _borderColor(BuildContext context, ColorScheme cs) {
    switch (announcement.type) {
      case AnnouncementType.warning:
        return _warningColor(context);
      case AnnouncementType.closure:
        return cs.error;
      case AnnouncementType.event:
        return cs.secondary;
      case AnnouncementType.service:
        return cs.tertiary;
      case AnnouncementType.info:
        return cs.onSurface.withValues(alpha: 0.2);
    }
  }

  Color _iconColor(BuildContext context, ColorScheme cs) {
    switch (announcement.type) {
      case AnnouncementType.warning:
        return _warningColor(context);
      case AnnouncementType.closure:
        return cs.error;
      case AnnouncementType.event:
        return cs.secondary;
      case AnnouncementType.service:
        return cs.tertiary;
      case AnnouncementType.info:
        return cs.primary;
    }
  }

  IconData get _icon {
    switch (announcement.type) {
      case AnnouncementType.warning:
        return Icons.warning_rounded;
      case AnnouncementType.closure:
        return Icons.block_rounded;
      case AnnouncementType.event:
        return Icons.event_rounded;
      case AnnouncementType.service:
        return Icons.build_rounded;
      case AnnouncementType.info:
        return Icons.info_rounded;
    }
  }
}
