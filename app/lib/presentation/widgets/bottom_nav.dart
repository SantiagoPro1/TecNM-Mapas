import 'package:flutter/material.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;

  const BottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Navegación principal',
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: Color(0xFF333333), width: 1),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Inicio',
                  isActive: currentIndex == 0,
                  onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.home),
                ),
                _NavItem(
                  icon: Icons.map_rounded,
                  label: 'Mapa',
                  isActive: currentIndex == 1,
                  onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.map),
                ),
                _NavItem(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Escanear',
                  isActive: currentIndex == 2,
                  onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.scanner),
                ),
                _NavItem(
                  icon: Icons.badge_rounded,
                  label: 'Credencial',
                  isActive: currentIndex == 3,
                  onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.credential),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Perfil',
                  isActive: currentIndex == 4,
                  onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.profile),
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
    return Semantics(
      button: true,
      label: label,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: isActive
              ? BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? AppTheme.accent : AppTheme.textSecondary,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? AppTheme.accent : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}