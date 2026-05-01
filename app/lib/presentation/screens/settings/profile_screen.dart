import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // PopScope detecta cuando el usuario intenta ir "atrás" con los gestos del cel
    return PopScope(
      canPop: false, // Bloqueamos la salida directa
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // En lugar de cerrar la app, lo mandamos al Home de forma segura
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Perfil estudiantil'),
          // Botón de regreso manual en el AppBar
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.home),
          ),
        ),
        body: authState.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: authState.isAuthenticated
                    ? _buildProfileState(context, ref, authState)
                    : _buildLoginState(context, ref, authState),
              ),
      ),
    );
  }

  // --- WIDGETS DE ESTADO ---

  Widget _buildLoginState(BuildContext context, WidgetRef ref, AuthState authState) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Icon(Icons.account_circle_rounded, 
             size: 100, 
             color: AppTheme.textSecondary.withValues(alpha: 0.5)),
        const SizedBox(height: 24),
        const Text(
          'Inicia sesión con tu cuenta institucional para sincronizar tus datos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
        // Mostrar error si lo hay
        if (authState.errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    authState.errorMessage!,
                    style: const TextStyle(color: AppTheme.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () => ref.read(authProvider.notifier).signInWithGoogle(),
          icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
          label: const Text('Ingresar con Google'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileState(BuildContext context, WidgetRef ref, AuthState authState) {
    return Column(
      children: [
        _AvatarSection(authState: authState),
        const SizedBox(height: 32),
        _InfoCard(
          title: 'Datos académicos',
          items: [
            (Icons.badge_rounded, 'Matrícula', authState.matricula),
            (Icons.school_rounded, 'Carrera', 'Ing. Sistemas Computacionales'),
            (Icons.location_city_rounded, 'Campus', 'TecNM Colima'),
            (Icons.email_rounded, 'Correo', authState.user?.email ?? 'Sin correo'),
          ],
        ),
        const SizedBox(height: 16),
        const _InfoCard(
          title: 'Accesibilidad configurada',
          items: [
            (Icons.mic_rounded, 'Voz', 'Activada'),
            (Icons.translate_rounded, 'Idioma', 'Español (México)'),
            (Icons.speed_rounded, 'Velocidad de voz', '1.0x'),
          ],
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => ref.read(authProvider.notifier).signOut(),
          icon: const Icon(Icons.logout_rounded, size: 20, color: AppTheme.error),
          label: const Text('Cerrar sesión', style: TextStyle(color: AppTheme.error)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.error),
          ),
        ),
      ],
    );
  }
}

// --- SUB-WIDGETS ---

class _AvatarSection extends StatelessWidget {
  final AuthState authState;
  const _AvatarSection({required this.authState});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
              backgroundImage: authState.photoUrl != null
                  ? NetworkImage(authState.photoUrl!)
                  : null,
              child: authState.photoUrl == null
                  ? const Icon(Icons.person_rounded, size: 64, color: AppTheme.accent)
                  : null,
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_rounded, size: 16, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          authState.displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(IconData, String, String)> items;

  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 16),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(item.$1, color: AppTheme.accent, size: 22),
                    const SizedBox(width: 12),
                    Text(item.$2,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14)),
                    const Spacer(),
                    Expanded(
                      child: Text(
                        item.$3,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}