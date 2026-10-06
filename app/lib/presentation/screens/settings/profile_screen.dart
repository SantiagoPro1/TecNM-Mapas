import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/providers/auth_provider.dart';
import 'package:navia/data/providers/student_data_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';
import 'package:navia/core/constants/app_version.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('PERFIL ESTUDIANTIL'),
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () =>
                Navigator.pushReplacementNamed(context, AppRoutes.home),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Ajustes',
              onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            ),
          ],
        ),
        body: authState.isLoading
            ? Center(child: CircularProgressIndicator(color: cs.primary))
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: authState.isAuthenticated
                    ? _buildProfileState(context, ref, authState)
                    : _buildLoginState(context, ref, authState),
              ),
      ),
    );
  }

  Widget _buildLoginState(
      BuildContext context, WidgetRef ref, AuthState authState) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.03),
              shape: BoxShape.circle),
          child: Icon(Icons.account_circle_rounded,
              size: 100, color: cs.onSurface.withValues(alpha: 0.15)),
        ),
        const SizedBox(height: 32),
        Text(
          'IDENTIDAD INSTITUCIONAL',
          style: TextStyle(
              color: cs.primary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0),
        ),
        const SizedBox(height: 12),
        Text(
          'Inicia sesión con tu cuenta institucional para acceder a tu credencial digital.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 15,
              height: 1.5),
        ),
        if (authState.errorMessage != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.error.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_rounded, color: cs.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(authState.errorMessage!,
                      style: TextStyle(
                          color: cs.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: () => ref.read(authProvider.notifier).signInWithGoogle(),
            icon:
                Icon(Icons.g_mobiledata_rounded, size: 36, color: cs.onPrimary),
            label: Text('INGRESAR CON GOOGLE',
                style: TextStyle(
                    color: cs.onPrimary, fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: Icon(Icons.settings_outlined, size: 20, color: cs.primary),
            label: Text(
              'AJUSTES Y ACTUALIZACIONES',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileState(
      BuildContext context, WidgetRef ref, AuthState authState) {
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final student = ref.watch(studentDataProvider);
    final carrera = student.carrera;
    final nss = student.nss;
    return Column(
      children: [
        _AvatarSection(authState: authState),
        const SizedBox(height: 40),
        _InfoCard(
          title: 'DATOS INSTITUCIONALES',
          items: [
            (Icons.badge_rounded, 'MATRÍCULA', authState.matricula, null),
            (Icons.location_city_rounded, 'CAMPUS',
                authState.campusLabel.toUpperCase(), null),
            (Icons.email_rounded, 'CORREO', authState.user?.email ?? '---',
                null),
            (
              Icons.school_rounded,
              'CARRERA',
              (carrera == null || carrera.isEmpty)
                  ? 'TOCA PARA AGREGAR'
                  : carrera.toUpperCase(),
              () => _editCarrera(context, ref, carrera),
            ),
            (
              Icons.local_hospital_rounded,
              'NSS (IMSS)',
              (nss == null || nss.isEmpty)
                  ? 'TOCA PARA AGREGAR'
                  : StudentData.formatNss(nss),
              () => _editNss(context, ref, nss),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _InfoCard(
          title: 'DATOS DE EMERGENCIA',
          items: [
            (
              Icons.bloodtype_rounded,
              'TIPO DE SANGRE',
              student.bloodType ?? 'TOCA PARA AGREGAR',
              () => _editBloodType(context, ref, student.bloodType),
            ),
            (
              Icons.contact_emergency_rounded,
              'CONTACTO',
              student.emergencyLabel ?? 'TOCA PARA AGREGAR',
              () => _editEmergency(
                  context, ref, student.emergencyName, student.emergencyPhone),
            ),
            (
              Icons.medical_information_rounded,
              'ALERGIAS',
              student.medicalNotes ?? 'NINGUNA',
              () => _editMedicalNotes(context, ref, student.medicalNotes),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _InfoCard(
          title: 'CONFIGURACIÓN DE ACCESIBILIDAD',
          items: [
            (Icons.record_voice_over_rounded, 'GUÍA POR VOZ',
                settings.voiceEnabled ? 'ACTIVA' : 'DESACTIVADA', null),
            (Icons.translate_rounded, 'LENGUAJE', 'ESPAÑOL (MX)', null),
          ],
        ),
        const SizedBox(height: 20),
        _InfoCard(
          title: 'SISTEMA Y ACTUALIZACIONES',
          items: [
            (
              Icons.system_update_rounded,
              'ACTUALIZACIONES',
              'VERSIÓN ${AppVersion.version} (TOCA PARA COMPROBAR)',
              () => Navigator.pushNamed(context, AppRoutes.settings),
            ),
            (
              Icons.settings_rounded,
              'AJUSTES COMPLETOS',
              'ACCESIBILIDAD Y OPCIONES',
              () => Navigator.pushNamed(context, AppRoutes.settings),
            ),
          ],
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => ref.read(authProvider.notifier).signOut(),
            icon: Icon(Icons.logout_rounded, color: cs.error, size: 20),
            label: Text('CERRAR SESIÓN',
                style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: cs.error.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: cs.error.withValues(alpha: 0.2)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editCarrera(
      BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Tu carrera'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TecNM Mapas no tiene forma de saber tu carrera automáticamente — '
              'escríbela tal como quieres que aparezca en tu credencial.',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  hintText: 'Ej. Ingeniería en Sistemas Computacionales'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(studentDataProvider.notifier).setCarrera(result);
    }
  }

  /// El NSS son 11 dígitos que asigna el IMSS — no se puede deducir del
  /// correo institucional ni de la matrícula (esta última solo codifica año
  /// de inscripción, plantel y consecutivo, según la guía oficial del
  /// TecNM). Por eso se captura a mano, una sola vez.
  Future<void> _editNss(
      BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            void trySave() {
              final v = controller.text;
              if (v.trim().isEmpty) {
                Navigator.pop(ctx, '');
                return;
              }
              if (!StudentData.isValidNss(v)) {
                setLocalState(() => error = 'El NSS debe tener 11 dígitos.');
                return;
              }
              Navigator.pop(ctx, v);
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
              title: const Text('Tu NSS del IMSS'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Son los 11 dígitos de tu Número de Seguridad Social. '
                    'Sirve para que el personal médico del evento pueda '
                    'atenderte más rápido si llegas a necesitarlo.',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '12345678901',
                      errorText: error,
                      counterText: '',
                    ),
                    maxLength: 14, // permite espacios/guiones al escribir
                    onSubmitted: (_) => trySave(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.45)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Se guarda solo en este teléfono. No se sube a '
                          'internet ni viaja en el código QR.',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.45),
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: trySave,
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      await ref.read(studentDataProvider.notifier).setNss(result);
    }
  }

  Future<void> _editBloodType(
      BuildContext context, WidgetRef ref, String? current) async {
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Tipo de sangre'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: StudentData.bloodTypes.map((t) {
            final selected = t == current;
            return ChoiceChip(
              label: Text(t),
              selected: selected,
              onSelected: (_) => Navigator.pop(ctx, t),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text('Quitar', style: TextStyle(color: cs.error)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(studentDataProvider.notifier).setBloodType(result);
    }
  }

  Future<void> _editEmergency(BuildContext context, WidgetRef ref,
      String? currentName, String? currentPhone) async {
    final nameCtrl = TextEditingController(text: currentName ?? '');
    final phoneCtrl = TextEditingController(text: currentPhone ?? '');
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Contacto de emergencia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿A quién hay que avisar si te pasa algo durante el evento?',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nombre', hintText: 'Ej. María López'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono', hintText: 'Ej. 312 123 4567'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(studentDataProvider.notifier)
          .setEmergencyContact(nameCtrl.text, phoneCtrl.text);
    }
  }

  Future<void> _editMedicalNotes(
      BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Alergias o padecimientos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lo que deba saber quien te atienda: alergias a medicamentos, '
              'asma, diabetes, etc. Déjalo vacío si no aplica.',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  hintText: 'Ej. Alérgico a la penicilina'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(studentDataProvider.notifier).setMedicalNotes(result);
    }
  }
}

class _AvatarSection extends StatelessWidget {
  final AuthState authState;
  const _AvatarSection({required this.authState});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cs.outline),
              ),
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: authState.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: authState.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Icon(
                            Icons.person_rounded,
                            size: 64,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.person_rounded,
                          size: 64,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration:
                  BoxDecoration(color: cs.tertiary, shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded,
                  size: 18, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          authState.displayName.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: cs.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(IconData, String, String, Future<void> Function()?)> items;

  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
                color: cs.primary,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0),
          ),
          const SizedBox(height: 20),
          ...items.map((item) => InkWell(
                onTap: item.$4,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Icon(item.$1,
                          color: cs.onSurface.withValues(alpha: 0.3),
                          size: 20),
                      const SizedBox(width: 14),
                      Text(item.$2,
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.4),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Flexible(
                        child: Text(item.$3,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (item.$4 != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.edit_rounded,
                            size: 15, color: cs.primary.withValues(alpha: 0.6)),
                      ],
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
