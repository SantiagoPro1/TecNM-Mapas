import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/core/constants/app_version.dart';
import 'package:navia/services/update/app_update_service.dart';

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
                    const SizedBox(height: 32),
                    _SectionHeader('SISTEMA Y ACTUALIZACIONES',
                        accentColor: cs.primary),
                    _NavTile(
                      icon: Icons.system_update_rounded,
                      label: 'Buscar actualizaciones',
                      subtitle:
                          'Versión actual: v${AppVersion.version} (Build ${AppVersion.buildNumber})',
                      onTap: () => AppUpdateService.verificarActualizacion(
                        context,
                        manualCheck: true,
                      ),
                    ),
                    _NavTile(
                      icon: Icons.info_rounded,
                      label: 'Acerca de NAVIA',
                      onTap: () => _showAbout(context),
                    ),
                    _NavTile(
                      icon: Icons.security_rounded,
                      label: 'Privacidad y Seguridad',
                      onTap: () => _showPrivacy(context),
                    ),
                    const SizedBox(height: 48),
                    Center(
                      child: Text(
                        'NAVIA v${AppVersion.version} (Build ${AppVersion.buildNumber}) · TecNM Campus Colima',
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.35),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('NAVIA',
            style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versión ${AppVersion.version} (Build ${AppVersion.buildNumber})',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
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
              '• El asistente de voz solo lee indicaciones en voz alta (texto a voz); la app no graba ni envía audio a servidores externos.\n\n'
              '• Los datos que capturas tú mismo en tu perfil (carrera, NSS del IMSS, tipo de sangre, contacto de emergencia y padecimientos) se guardan ÚNICAMENTE en este dispositivo: no se suben a internet, no se comparten y no viajan dentro del código QR de tu credencial. Solo son visibles para quien tenga tu teléfono en la mano.\n\n'
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

/// Selector de apariencia: claro / oscuro / seguir sistema. NAVIA tiene una
/// sola identidad visual — esto no elige "un tema" distinto, solo su brillo.
class _ThemeSelector extends ConsumerWidget {
  static const _options = [
    (mode: ThemeMode.system, label: 'Automático', icon: Icons.brightness_auto_rounded),
    (mode: ThemeMode.light, label: 'Claro', icon: Icons.light_mode_rounded),
    (mode: ThemeMode.dark, label: 'Oscuro', icon: Icons.dark_mode_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeProvider);
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: _options.map((option) {
          final isSelected = current == option.mode;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(themeProvider.notifier).setMode(option.mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? cs.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: isSelected
                      ? Border.all(color: cs.outline)
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(option.icon,
                        size: 20,
                        color: isSelected
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(height: 6),
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline),
      ),
      child: SwitchListTile(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm)),
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

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadius.sm)),
          child:
              Icon(icon, color: cs.onSurface.withValues(alpha: 0.7), size: 22),
        ),
        title: Text(label,
            style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              )
            : null,
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: cs.onSurface.withValues(alpha: 0.24)),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
    );
  }
}
