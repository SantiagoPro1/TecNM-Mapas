import 'package:flutter/material.dart';
import 'package:navia/core/constants/app_routes.dart';

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
          border: Border(
            top: BorderSide(
                color: cs.primary.withValues(alpha: 0.08), width: 1.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Inicio',
                  isActive: currentIndex == 0,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.home),
                ),
                _NavItem(
                  icon: Icons.map_rounded,
                  label: 'Mapa',
                  isActive: currentIndex == 1,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.map),
                ),
                _NavItem(
                  icon: Icons.view_in_ar_rounded,
                  label: 'NAVIA AR',
                  isActive: currentIndex == 2,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, AppRoutes.scanner),
                ),
                _NavItem(
                  icon: Icons.badge_rounded,
                  label: 'ID',
                  isActive: currentIndex == 3,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, AppRoutes.credential),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Perfil',
                  isActive: currentIndex == 4,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, AppRoutes.profile),
                ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: isActive
              ? BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
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
