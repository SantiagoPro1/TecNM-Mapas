import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:navia/core/constants/app_version.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Información de versión remota obtenida desde Firestore (`app_meta/app_update`).
class AppUpdateInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final String apkUrl;
  final String releaseNotes;
  final bool mandatory;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    this.mandatory = false,
  });

  /// `true` si el build en Firestore es mayor que el que corre localmente en el APK.
  bool get hasUpdate => latestBuildNumber > AppVersion.buildNumber;
}

/// Servicio que comprueba si existe una versión más reciente del APK en la nube
/// y muestra el diálogo institucional para descargarla e instalarla con un toque.
class AppUpdateService {
  AppUpdateService._();

  static const String _coleccion = 'app_meta';
  static const String _documento = 'app_update';

  static bool _dialogoMostradoEnSesion = false;

  /// Consulta si existe una versión más nueva en Firestore.
  static Future<AppUpdateInfo?> obtenerInfoActualizacion() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_coleccion)
          .doc(_documento)
          .get();

      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;

      return AppUpdateInfo(
        latestVersion: (data['latestVersion'] as String?) ?? AppVersion.version,
        latestBuildNumber:
            (data['latestBuildNumber'] as num?)?.toInt() ?? AppVersion.buildNumber,
        apkUrl: (data['apkUrl'] as String?) ?? '',
        releaseNotes: (data['releaseNotes'] as String?) ??
            'Mejoras de rendimiento y actualización de sedes deportivas.',
        mandatory: (data['mandatory'] as bool?) ?? false,
      );
    } catch (e) {
      debugPrint('AppUpdateService: no se pudo verificar actualización ($e)');
      return null;
    }
  }

  /// Verifica y muestra el diálogo de actualización si hay una nueva versión.
  /// Si [manualCheck] es true (ej. desde Ajustes), muestra un aviso si ya está al día.
  static Future<void> verificarActualizacion(
    BuildContext context, {
    bool manualCheck = false,
  }) async {
    if (!manualCheck && _dialogoMostradoEnSesion) return;

    final info = await obtenerInfoActualizacion();
    if (!context.mounted) return;

    if (info != null && info.hasUpdate && info.apkUrl.isNotEmpty) {
      _dialogoMostradoEnSesion = true;
      _mostrarDialogo(context, info);
    } else if (manualCheck) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '¡Tu app está al día! Tienes la versión más reciente (v${AppVersion.version}).',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Color(0xFF1E7A46),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static void _mostrarDialogo(BuildContext context, AppUpdateInfo info) {
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (ctx) => PopScope(
        canPop: !info.mandatory,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          icon: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.system_update_rounded,
              color: cs.primary,
              size: 36,
            ),
          ),
          title: Text(
            '¡Nueva versión disponible!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    'Versión ${info.latestVersion} (Instalada: ${AppVersion.version})',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Novedades:',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Text(
                  info.releaseNotes,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            if (!info.mandatory)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'MÁS TARDE',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              onPressed: () async {
                final uri = Uri.parse(info.apkUrl);
                try {
                  final launched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched && await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                } catch (e) {
                  debugPrint('Error lanzando url de actualizacion: $e');
                }
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text(
                'ACTUALIZAR',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
