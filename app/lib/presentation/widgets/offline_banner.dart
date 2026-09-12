import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/services/offline/connectivity_service.dart';

/// Banner compacto que se muestra cuando la app está sin conexión.
///
/// Se posiciona en la parte superior del mapa, debajo de los filtros,
/// con una animación suave de deslizamiento vertical.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityAsync = ref.watch(connectivityStatusProvider);

    return connectivityAsync.when(
      data: (status) {
        final isOffline = status == ConnectivityStatus.offline;
        final warningColor = Theme.of(context).brightness == Brightness.dark
            ? AppWarning.dark
            : AppWarning.light;
        return AnimatedSlide(
          offset: isOffline ? Offset.zero : const Offset(0, -1.5),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isOffline ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: warningColor.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: warningColor,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Modo offline — navegación y mapa con datos locales',
                      style: TextStyle(
                        color: warningColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.cloud_off_rounded,
                    color: warningColor,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
