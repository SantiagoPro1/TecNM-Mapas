import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/providers/auth_provider.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';
import 'package:navia/presentation/screens/settings/credits_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Comportamiento edge-to-edge limpio
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBody:
          true, // Permite que el diseño use el espacio debajo de la barra
      bottomNavigationBar: const BottomNav(currentIndex: 5),
      appBar: AppBar(
        title: const Text('AJUSTES'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Padding dinámico inferior para evitar que la barra del sistema tape contenido
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                48 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionHeader('TEMA VISUAL', accentColor: cs.primary),
                    _ThemeSelector(),
                    const SizedBox(height: 32),
                    _SectionHeader('ACCESIBILIDAD', accentColor: cs.primary),
                    _SwitchTile(
                      icon: Icons.record_voice_over_rounded,
                      label: 'Navegación Asistida',
                      subtitle: 'Guía por voz en tiempo real',
                      value: settings.voiceEnabled,
                      onChanged: (v) {
                        notifier.toggleVoice(v);
                        if (v) {
                          ref.read(voiceProvider.notifier).speakAnnouncement(
                              'Navegación asistida activada');
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
                        ref.read(mapThemeProvider.notifier).state =
                            v ? 'dark' : 'light';
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
                    _SectionHeader('CUENTA ESTUDIANTIL',
                        accentColor: cs.primary),
                    _NavTile(
                      icon: Icons.account_circle_rounded,
                      label: 'Perfil del Alumno',
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.profile),
                    ),
                    _NavTile(
                      icon: Icons.badge_rounded,
                      label: 'Credencial Digital NAVIA',
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.credential),
                    ),
                    const SizedBox(height: 32),
                    _SectionHeader('SOPORTE Y APP', accentColor: cs.primary),
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
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CreditsScreen())),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.read(authProvider.notifier).signOut(),
                        icon: Icon(Icons.logout_rounded,
                            color: cs.error, size: 20),
                        label: Text('CERRAR SESIÓN',
                            style: TextStyle(
                                color: cs.error,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: cs.error.withValues(alpha: 0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                                color: cs.error.withValues(alpha: 0.2)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text('NAVIA v1.0.0 (InnovaTec Edition)',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.2),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static void _haptic(bool enabled) {
    if (enabled) HapticFeedback.lightImpact();
  }

  void _showAbout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('NAVIA',
            style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versión 1.0.0 (Stable)',
                style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
            const SizedBox(height: 16),
            Text(
              'Sistema de Navegación Inteligente Accesible (NAVIA).\n\n'
              'Desarrollado para el InnovaTecNM 2026 por estudiantes del Campus Colima.\n\n'
              'NAVIA es una plataforma innovadora que busca mejorar la accesibilidad y movilidad '
              'dentro del campus, utilizando inteligencia artificial, geolocalización y '
              'realidad aumentada para guiar a los usuarios de manera autónoma y segura.',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6), height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ENTENDIDO',
                style:
                    TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  void _showPrivacy(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Privacidad',
            style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• Los datos de tu cuenta se almacenan de forma segura en Firebase con encriptación de extremo a extremo.\n\n'
              '• Tu ubicación se usa exclusivamente para navegación dentro del campus y NO se comparte con terceros bajo ninguna circunstancia.\n\n'
              '• Las grabaciones de voz se procesan localmente mediante procesamiento On-Device y no se envían a servidores externos, garantizando tu anonimato.\n\n'
              '• El escaneo de cámara para NAVIA AR se procesa sin almacenar imágenes.\n\n'
              '• Cumplimos estrictamente con la Ley Federal de Protección de Datos Personales en Posesión de los Particulares.',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  height: 1.6,
                  fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ENTENDIDO',
                style:
                    TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

// ─── Theme Selector ─────────────────────────────────────────────

class _ThemeSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentIndex = themeNotifier.currentIndex;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: List.generate(availableThemes.length, (i) {
        final info = availableThemes[i];
        final isSelected = currentIndex == i;

        return GestureDetector(
          onTap: () => ref.read(themeProvider.notifier).setTheme(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? info.previewColor.withValues(alpha: 0.12)
                  : cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? info.previewColor.withValues(alpha: 0.6)
                    : cs.onSurface.withValues(alpha: 0.05),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Preview circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: info.previewColor,
                    shape: BoxShape.circle,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: info.previewColor.withValues(alpha: 0.4),
                                blurRadius: 12)
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 20)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.label,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.description,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.palette_rounded,
                      color: info.previewColor, size: 20),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ─── Helper Widgets ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color accentColor;
  const _SectionHeader(this.title, {required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 16),
      child: Text(
        title,
        style: TextStyle(
          color: accentColor,
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: SwitchListTile(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: cs.primary, size: 22),
        ),
        title: Text(label,
            style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle,
            style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.4), fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: cs.primary,
        activeTrackColor: cs.primary.withValues(alpha: 0.3),
        inactiveTrackColor: cs.onSurface.withValues(alpha: 0.1),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(display,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
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
              activeColor: cs.primary,
              inactiveColor: cs.onSurface.withValues(alpha: 0.1),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10)),
          child:
              Icon(icon, color: cs.onSurface.withValues(alpha: 0.7), size: 22),
        ),
        title: Text(label,
            style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: cs.onSurface.withValues(alpha: 0.24)),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
