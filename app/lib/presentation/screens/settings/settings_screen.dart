import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/providers/auth_provider.dart';
import 'package:sinait/data/providers/voice_provider.dart';
import 'package:sinait/data/providers/settings_provider.dart';
import 'package:sinait/presentation/screens/map/providers/map_providers.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';
import 'package:sinait/presentation/screens/settings/credits_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: const BottomNav(currentIndex: 5),
      appBar: AppBar(
        title: const Text('AJUSTES'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          const _SectionHeader('ACCESIBILIDAD'),
          _SwitchTile(
            icon: Icons.record_voice_over_rounded,
            label: 'Navegación Asistida',
            subtitle: 'Guía por voz en tiempo real',
            value: settings.voiceEnabled,
            onChanged: (v) {
              notifier.toggleVoice(v);
              if (v) {
                ref.read(voiceProvider.notifier).speakAnnouncement('Navegación asistida activada');
              }
              _haptic(settings.vibrationEnabled);
            },
          ),
          _SwitchTile(
            icon: Icons.visibility_rounded,
            label: 'Modo Alto Contraste',
            subtitle: 'Cambia el mapa a modo oscuro',
            value: settings.highContrast,
            onChanged: (v) {
              notifier.toggleHighContrast(v);
              // Sincronizar con el tema del mapa
              ref.read(mapThemeProvider.notifier).state = v ? 'dark' : 'light';
              _haptic(settings.vibrationEnabled);
            },
          ),
          _SwitchTile(
            icon: Icons.sensors_rounded,
            label: 'Respuesta Háptica',
            subtitle: 'Vibración al interactuar',
            value: settings.vibrationEnabled,
            onChanged: (v) {
              notifier.toggleVibration(v);
              if (v) HapticFeedback.mediumImpact();
            },
          ),
          const SizedBox(height: 12),
          _SliderTile(
            icon: Icons.speed_rounded,
            label: 'Velocidad de Voz',
            value: settings.speechRate,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            display: '${settings.speechRate.toStringAsFixed(1)}x',
            onChanged: (v) {
              notifier.setSpeechRate(v);
              ref.read(voiceProvider.notifier).setSpeechRate(v);
              _haptic(settings.vibrationEnabled);
            },
          ),
          const SizedBox(height: 32),
          const _SectionHeader('CUENTA ESTUDIANTIL'),
          _NavTile(
            icon: Icons.account_circle_rounded,
            label: 'Perfil del Alumno',
            onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
          ),
          _NavTile(
            icon: Icons.badge_rounded,
            label: 'Credencial Digital SINAIT',
            onTap: () => Navigator.pushNamed(context, AppRoutes.credential),
          ),
          const SizedBox(height: 32),
          const _SectionHeader('SOPORTE Y APP'),
          _NavTile(
            icon: Icons.info_rounded,
            label: 'Acerca de la Plataforma',
            onTap: () => _showAbout(context),
          ),
          _NavTile(
            icon: Icons.security_rounded,
            label: 'Privacidad y Seguridad',
            onTap: () => _showPrivacy(context),
          ),
          _NavTile(
            icon: Icons.groups_rounded,
            label: 'Créditos del Proyecto',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreditsScreen())),
          ),
          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => ref.read(authProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
              label: const Text('CERRAR SESIÓN',
                style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: AppTheme.error.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: AppTheme.error.withOpacity(0.2)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('SINAIT v1.0.0 (InnovaTec Edition)',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  static void _haptic(bool enabled) {
    if (enabled) HapticFeedback.lightImpact();
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('SINAIT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Versión 1.0.0 (Stable)', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 16),
            Text(
              'Sistema de Navegación Inteligente Accesible del Instituto Tecnológico.\n\nDesarrollado para el InnovaTecNM 2026 por estudiantes del Campus Colima.',
              style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ENTENDIDO', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  void _showPrivacy(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Privacidad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• Los datos de tu cuenta se almacenan de forma segura en Firebase.\n\n'
              '• Tu ubicación se usa exclusivamente para navegación dentro del campus y NO se comparte con terceros.\n\n'
              '• Las grabaciones de voz se procesan localmente y no se envían a servidores externos.\n\n'
              '• Cumplimos con la Ley Federal de Protección de Datos Personales.',
              style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.6, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ENTENDIDO', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w900)),
          ),
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
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 16),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: SwitchListTile(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppTheme.accent, size: 22),
        ),
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.accent,
        activeTrackColor: AppTheme.accent.withOpacity(0.3),
        inactiveTrackColor: Colors.white10,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(display, style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: AppTheme.accent,
              inactiveColor: Colors.white10,
              onChanged: onChanged,
            ),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: Colors.white70, size: 22),
        ),
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white24),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}