import 'package:flutter/material.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;

  const BottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Navegación principal',
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: cs.outline)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Inicio',
                  isActive: currentIndex == 0,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.home),
                ).expandido,
                _NavItem(
                  icon: Icons.badge_rounded,
                  label: 'ID',
                  isActive: currentIndex == 1,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, AppRoutes.credential),
                ).expandido,
                _NavItem(
                  icon: Icons.public_rounded,
                  label: 'Mapa abierto',
                  isActive: currentIndex == 3,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, AppRoutes.openMap),
                ).expandido,
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Perfil',
                  isActive: currentIndex == 2,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, AppRoutes.profile),
                ).expandido,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inactiveColor = cs.onSurface.withValues(alpha: 0.35);
    return Semantics(
      button: true,
      label: label,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: isActive
              ? BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? cs.primary : inactiveColor,
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? cs.primary : inactiveColor,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _NavItem {
  /// Cada botón ocupa una cuarta parte exacta del ancho. Sin esto, la
  /// etiqueta "Mapa abierto" hace que la fila se desborde en teléfonos
  /// angostos (320-360 px de ancho lógico).
  ///
  /// `heightFactor: 1` es obligatorio: la barra la coloca el Scaffold con
  /// altura libre, así que un `Center` normal (que crece todo lo que pueda)
  /// estiraba la barra hasta ocupar la pantalla completa y tapaba el
  /// contenido de la pantalla, dejando los botones flotando a media altura.
  /// Con el factor, el alto lo manda el botón, como debe ser.
  Widget get expandido =>
      Expanded(child: Center(heightFactor: 1, child: this));
}
