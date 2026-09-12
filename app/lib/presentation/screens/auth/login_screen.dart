import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/providers/auth_provider.dart';

/// Pantalla de entrada mostrada una sola vez, justo después del onboarding:
/// deja elegir entre navegar como Invitado o iniciar sesión institucional
/// (Jugador/Staff TecNM). El rol de Administrador no es una tercera opción
/// aquí — se detecta automáticamente después de iniciar sesión, según el
/// documento `admins/{uid}` en Firestore (ver isAdminProvider). Una vez
/// elegido, no se vuelve a mostrar (ver `hasChosenEntryMode` en main.dart);
/// quien entró como Invitado puede iniciar sesión más tarde desde Perfil.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  Future<void> _markChosenAndGo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasChosenEntryMode', true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }

  Future<void> _continueAsGuest() async {
    await _markChosenAndGo();
  }

  Future<void> _signIn() async {
    await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    if (ref.read(authProvider).isAuthenticated) {
      await _markChosenAndGo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                ),
                child: Icon(Icons.near_me_rounded, color: cs.onPrimary, size: 32),
              ),
              const SizedBox(height: 28),
              Text(
                '¿Cómo quieres continuar?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 10),
              Text(
                'Puedes cambiar esto después desde tu perfil.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13.5),
              ),
              const SizedBox(height: 36),
              if (authState.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: cs.error.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_rounded, color: cs.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(authState.errorMessage!,
                            style: TextStyle(color: cs.error, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _EntryOptionCard(
                icon: Icons.badge_rounded,
                title: 'Jugador / Staff TecNM',
                description:
                    'Inicia sesión con tu correo institucional (@tecnm.mx) para tu credencial digital con QR.',
                filled: true,
                loading: authState.isLoading,
                onTap: authState.isLoading ? null : _signIn,
              ),
              const SizedBox(height: 12),
              _EntryOptionCard(
                icon: Icons.explore_rounded,
                title: 'Invitado',
                description: 'Explora el mapa y las sedes del evento sin iniciar sesión.',
                filled: false,
                loading: false,
                onTap: authState.isLoading ? null : _continueAsGuest,
              ),
              const Spacer(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  const _EntryOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.filled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = filled ? cs.primary : cs.surfaceContainerHighest;
    final iconColor = filled ? cs.onPrimary : cs.onSurface;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: filled ? cs.primary : cs.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(AppRadius.md)),
                child: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: iconColor),
                      )
                    : Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(description,
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.55),
                            fontSize: 12,
                            height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
