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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('PERFIL ESTUDIANTIL'),
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.home),
          ),
        ),
        body: authState.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: authState.isAuthenticated
                    ? _buildProfileState(context, ref, authState)
                    : _buildLoginState(context, ref, authState),
              ),
      ),
    );
  }

  Widget _buildLoginState(BuildContext context, WidgetRef ref, AuthState authState) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), shape: BoxShape.circle),
          child: Icon(Icons.account_circle_rounded, size: 100, color: Colors.white.withOpacity(0.1)),
        ),
        const SizedBox(height: 32),
        const Text(
          'IDENTIDAD INSTITUCIONAL',
          style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2.0),
        ),
        const SizedBox(height: 12),
        Text(
          'Inicia sesión para acceder a tu credencial y sincronizar tu progreso en el campus.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15, height: 1.5),
        ),
        if (authState.errorMessage != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_rounded, color: AppTheme.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(authState.errorMessage!, style: const TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 48),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF0091EA)]),
          ),
          child: ElevatedButton.icon(
            onPressed: () => ref.read(authProvider.notifier).signInWithGoogle(),
            icon: const Icon(Icons.g_mobiledata_rounded, size: 36, color: Color(0xFF0D1B2A)),
            label: const Text('INGRESAR CON GOOGLE', style: TextStyle(color: Color(0xFF0D1B2A), fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              minimumSize: const Size(double.infinity, 64),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileState(BuildContext context, WidgetRef ref, AuthState authState) {
    return Column(
      children: [
        _AvatarSection(authState: authState),
        const SizedBox(height: 40),
        _InfoCard(
          title: 'DATOS ACADÉMICOS',
          items: [
            (Icons.badge_rounded, 'MATRÍCULA', authState.matricula),
            (Icons.school_rounded, 'CARRERA', 'ING. EN SISTEMAS'),
            (Icons.location_city_rounded, 'CAMPUS', 'TECNM COLIMA'),
            (Icons.email_rounded, 'CORREO', authState.user?.email ?? '---'),
          ],
        ),
        const SizedBox(height: 20),
        const _InfoCard(
          title: 'CONFIGURACIÓN DE ACCESIBILIDAD',
          items: [
            (Icons.record_voice_over_rounded, 'GUÍA POR VOZ', 'ACTIVA'),
            (Icons.translate_rounded, 'LENGUAJE', 'ESPAÑOL (MX)'),
            (Icons.speed_rounded, 'RITMO DE VOZ', '1.0X'),
          ],
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => ref.read(authProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
            label: const Text('CERRAR SESIÓN', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: AppTheme.error.withOpacity(0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppTheme.error.withOpacity(0.2)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF0091EA)]),
                boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)],
              ),
              child: CircleAvatar(
                radius: 56,
                backgroundColor: AppTheme.surface,
                backgroundImage: authState.photoUrl != null ? NetworkImage(authState.photoUrl!) : null,
                child: authState.photoUrl == null ? const Icon(Icons.person_rounded, size: 64, color: Colors.white24) : null,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded, size: 18, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          authState.displayName.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2.0),
          ),
          const SizedBox(height: 20),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  children: [
                    Icon(item.$1, color: Colors.white.withOpacity(0.3), size: 20),
                    const SizedBox(width: 14),
                    Text(item.$2, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(item.$3, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}