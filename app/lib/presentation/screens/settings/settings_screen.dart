import 'package:flutter/material.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _voiceEnabled = true;
  bool _highContrast = false;
  bool _vibrationEnabled = true;
  double _speechRate = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 5),
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('Accesibilidad'),  
          _SwitchTile(
            icon: Icons.mic_rounded,
            label: 'Navegación por voz',
            subtitle: 'Comandos de voz en español mexicano',
            value: _voiceEnabled,
            onChanged: (v) => setState(() => _voiceEnabled = v),
          ),
          _SwitchTile(
            icon: Icons.contrast_rounded,
            label: 'Alto contraste',
            subtitle: 'Mayor legibilidad en pantalla',
            value: _highContrast,
            onChanged: (v) => setState(() => _highContrast = v),
          ),
          _SwitchTile(
            icon: Icons.vibration_rounded,
            label: 'Vibración',
            subtitle: 'Retroalimentación háptica al navegar',
            value: _vibrationEnabled,
            onChanged: (v) => setState(() => _vibrationEnabled = v),
          ),
          const SizedBox(height: 8),
          _SliderTile(
            icon: Icons.speed_rounded,
            label: 'Velocidad de voz',
            value: _speechRate,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            display: '${_speechRate.toStringAsFixed(1)}x',
            onChanged: (v) => setState(() => _speechRate = v),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('Cuenta'),
          _NavTile(
            icon: Icons.person_rounded,
            label: 'Perfil estudiantil',
            onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
          ),
          _NavTile(
            icon: Icons.badge_rounded,
            label: 'Credencial digital',
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.credential),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('Applicación'),
          _NavTile(
            icon: Icons.info_outline_rounded,
            label: 'Acerca de SINAIT',
            onTap: () => _showAbout(context),
          ),
          _NavTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Aviso de privacidad',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.logout_rounded,
                color: AppTheme.error, size: 20),
            label: const Text('Cerrar sesión',
                style: TextStyle(color: AppTheme.error)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.error),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text('SINAIT v1.0.0',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Sistema de Navegación Inteligente Accesible del Instituto Tecnológico.\n\nDesarrollado por estudiantes del TecNM Campus Colima para el InnovaTecNM 2026.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: AppTheme.accent, size: 26),
        title: Text(label,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.accent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accent, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              Text(display,
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppTheme.accent,
            inactiveColor: const Color(0xFF333333),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.accent, size: 26),
        title: Text(label,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: AppTheme.textSecondary),
        onTap: onTap,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}