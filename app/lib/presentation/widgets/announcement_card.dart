import 'package:flutter/material.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/models/announcement.dart';

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
    return Dismissible(
      key: Key(announcement.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.close_rounded,
            color: AppTheme.error, size: 24),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _borderColor,
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
                  color: _iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: _iconColor, size: 22),
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
                        color: _iconColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Título
                    Text(
                      announcement.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
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
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
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

  Color get _borderColor {
    switch (announcement.type) {
      case AnnouncementType.warning:
        return const Color(0xFFFF9800);
      case AnnouncementType.closure:
        return AppTheme.error;
      case AnnouncementType.event:
        return const Color(0xFF2196F3);
      case AnnouncementType.service:
        return AppTheme.success;
      case AnnouncementType.info:
        return const Color(0xFF333333);
    }
  }

  Color get _iconColor {
    switch (announcement.type) {
      case AnnouncementType.warning:
        return const Color(0xFFFF9800);
      case AnnouncementType.closure:
        return AppTheme.error;
      case AnnouncementType.event:
        return const Color(0xFF2196F3);
      case AnnouncementType.service:
        return AppTheme.success;
      case AnnouncementType.info:
        return AppTheme.accent;
    }
  }

  Color get _iconBgColor => _iconColor.withValues(alpha: 0.12);

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
