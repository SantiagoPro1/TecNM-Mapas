import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:navia/presentation/widgets/app_notice.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:navia/core/constants/app_version.dart';
import 'package:navia/core/theme/app_theme.dart';

/// Información de versión remota obtenida desde Firestore (`app_meta/app_update`).
class AppUpdateInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final String apkUrl;
  final String releaseNotes;
  final bool mandatory;
  final int installedBuildNumber;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    this.mandatory = false,
    this.installedBuildNumber = AppVersion.buildNumber,
  });

  /// `true` si el build en Firestore es mayor que el que corre localmente en el APK.
  bool get hasUpdate => latestBuildNumber > installedBuildNumber;
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

      final installedBuild = await const MethodChannel(
        'mx.edu.tecnm.colima.sinait/installer',
      ).invokeMethod<int>('getInstalledBuildNumber');

      return AppUpdateInfo(
        installedBuildNumber: installedBuild ?? AppVersion.buildNumber,
        latestVersion: (data['latestVersion'] as String?) ?? AppVersion.version,
        latestBuildNumber: (data['latestBuildNumber'] as num?)?.toInt() ??
            AppVersion.buildNumber,
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
        AppNotice(
          content: const Text(
            '¡Tu app está al día! Tienes la versión más reciente (v${AppVersion.version}).',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          tone: NoticeTone.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static void _mostrarDialogo(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (ctx) => _UpdateDialog(info: info),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  static const MethodChannel _installerChannel =
      MethodChannel('mx.edu.tecnm.colima.sinait/installer');

  bool _isDownloading = false;
  double _progress = 0.0;
  double _receivedMb = 0.0;
  double _totalMb = 0.0;
  bool _isReadyToInstall = false;
  String? _downloadedFilePath;
  String? _errorMessage;
  NoticeTone _messageTone = NoticeTone.error;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownloadAndInstall() async {
    if (_isDownloading || _isReadyToInstall) return;
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _messageTone = NoticeTone.error;
      _progress = 0.0;
      _receivedMb = 0.0;
      _totalMb = 0.0;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          '${tempDir.path}/TecNM_Mapas_v${widget.info.latestVersion}_b${widget.info.latestBuildNumber}.apk';

      _cancelToken = CancelToken();
      final dio = Dio();

      await dio.download(
        widget.info.apkUrl,
        targetPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            setState(() {
              _progress = (received / total).clamp(0.0, 1.0);
              _receivedMb = received / (1024 * 1024);
              _totalMb = total / (1024 * 1024);
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _isReadyToInstall = true;
        _downloadedFilePath = targetPath;
      });

      await _triggerInstall(targetPath);
    } catch (e) {
      if (!mounted) return;
      final cancelled = e is DioException && CancelToken.isCancel(e);
      setState(() {
        _isDownloading = false;
        _messageTone = cancelled ? NoticeTone.warning : NoticeTone.error;
        _errorMessage =
            cancelled ? 'Descarga cancelada' : 'Error durante la descarga: $e';
      });
    }
  }

  Future<void> _triggerInstall(String filePath) async {
    try {
      final result = await _installerChannel.invokeMethod<String>(
        'installApk',
        {'filePath': filePath, 'expectedBuild': widget.info.latestBuildNumber},
      );

      if (result == 'PERMISSION_REQUESTED' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppNotice(
            content: const Text(
              'Por favor activa "Permitir desde esta fuente" y regresa a la app para continuar la instalación.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            tone: NoticeTone.warning,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      debugPrint('AppUpdate: error invocando instalador nativo: $e');
      if (mounted) {
        setState(() {
          _isReadyToInstall = false;
          _messageTone = NoticeTone.error;
          _errorMessage = e is PlatformException
              ? e.message
              : 'No se pudo abrir el instalador: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = widget.info;

    return PopScope(
      canPop: !info.mandatory && !_isDownloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isReadyToInstall
                ? const Color(0xFF1E7A46).withValues(alpha: 0.12)
                : cs.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isReadyToInstall
                ? Icons.check_circle_rounded
                : (_isDownloading
                    ? Icons.downloading_rounded
                    : Icons.system_update_rounded),
            color: _isReadyToInstall ? const Color(0xFF1E7A46) : cs.primary,
            size: 36,
          ),
        ),
        title: Text(
          _isReadyToInstall
              ? '¡Descarga lista!'
              : (_isDownloading
                  ? 'Descargando actualización...'
                  : '¡Nueva versión disponible!'),
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
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: cs.primary,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${_receivedMb.toStringAsFixed(1)} MB / ${_totalMb > 0 ? _totalMb.toStringAsFixed(1) : '--'} MB',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Descargando directamente dentro de la aplicación. No cierres la ventana.',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 11.5,
                ),
              ),
            ] else if (_isReadyToInstall) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NoticeTone.success.background,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: NoticeTone.success.background,
                  ),
                ),
                child: const Text(
                  'El instalador del sistema abrirá la actualización. Si te pide permitir instalar apps desconocidas, activa el permiso para TecNM Mapas.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ] else ...[
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
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
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
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _messageTone.background,
                    borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_messageTone.icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_errorMessage!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600))),
                    ]),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          if (!info.mandatory && !_isDownloading)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'MÁS TARDE',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_isDownloading)
            TextButton(
              onPressed: () {
                _cancelToken?.cancel();
                setState(() {
                  _isDownloading = false;
                  _errorMessage = 'Descarga cancelada';
                  _messageTone = NoticeTone.warning;
                });
              },
              child: Text(
                'CANCELAR',
                style: TextStyle(
                  color: cs.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (_isReadyToInstall && _downloadedFilePath != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E7A46),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              onPressed: () => _triggerInstall(_downloadedFilePath!),
              icon: const Icon(Icons.install_mobile_rounded, size: 18),
              label: const Text(
                'INSTALAR',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              onPressed: _startDownloadAndInstall,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text(
                'ACTUALIZAR',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
