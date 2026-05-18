import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado de conectividad de la aplicación.
enum ConnectivityStatus {
  /// Conectado a internet (verificado con DNS lookup).
  online,

  /// Sin conexión a internet.
  offline,

  /// Estado inicial antes de la primera verificación.
  unknown,
}

/// Servicio que monitorea la conectividad a internet en tiempo real.
///
/// Estrategia de verificación:
///  1. Al iniciar, realiza un DNS lookup para verificar conectividad real
///     (no solo WiFi/datos activos, sino acceso real a internet).
///  2. Cada [_checkIntervalOnline] segundos si está online, o
///     [_checkIntervalOffline] segundos si está offline, revalida.
///  3. Expone un [StreamController] para que los providers de Riverpod
///     reaccionen al cambio de estado.
///
/// No usa el paquete `connectivity_plus` para evitar dependencias extra;
/// un simple DNS lookup a `dns.google` es suficiente y más confiable.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService _instance = ConnectivityService._();
  static ConnectivityService get instance => _instance;

  /// Intervalo de verificación cuando está online (más largo: 30s).
  static const Duration _checkIntervalOnline = Duration(seconds: 30);

  /// Intervalo de verificación cuando está offline (más corto: 8s).
  static const Duration _checkIntervalOffline = Duration(seconds: 8);

  final _controller = StreamController<ConnectivityStatus>.broadcast();
  Timer? _timer;
  ConnectivityStatus _lastStatus = ConnectivityStatus.unknown;

  /// Stream de cambios de conectividad.
  Stream<ConnectivityStatus> get statusStream => _controller.stream;

  /// Estado actual de conectividad.
  ConnectivityStatus get currentStatus => _lastStatus;

  /// `true` si el dispositivo tiene conexión a internet.
  bool get isOnline => _lastStatus == ConnectivityStatus.online;

  /// `true` si el dispositivo NO tiene conexión a internet.
  bool get isOffline => _lastStatus == ConnectivityStatus.offline;

  /// Inicia el monitoreo periódico de conectividad.
  /// Debe llamarse una vez en main() después de WidgetsFlutterBinding.
  Future<void> initialize() async {
    // Verificación inicial
    await _checkConnectivity();
    // Timer periódico adaptativo
    _scheduleNextCheck();
  }

  /// Fuerza una verificación inmediata de conectividad.
  Future<ConnectivityStatus> checkNow() async {
    await _checkConnectivity();
    return _lastStatus;
  }

  /// Verifica conectividad real mediante DNS lookup.
  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 3));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _updateStatus(ConnectivityStatus.online);
      } else {
        _updateStatus(ConnectivityStatus.offline);
      }
    } on SocketException {
      _updateStatus(ConnectivityStatus.offline);
    } on TimeoutException {
      _updateStatus(ConnectivityStatus.offline);
    } catch (e) {
      debugPrint('[Connectivity] Error inesperado: $e');
      _updateStatus(ConnectivityStatus.offline);
    }
  }

  void _updateStatus(ConnectivityStatus newStatus) {
    if (_lastStatus != newStatus) {
      debugPrint('[Connectivity] ${_lastStatus.name} → ${newStatus.name}');
      _lastStatus = newStatus;
      _controller.add(newStatus);
      // Re-programar el timer con el intervalo apropiado
      _scheduleNextCheck();
    }
  }

  void _scheduleNextCheck() {
    _timer?.cancel();
    final interval = _lastStatus == ConnectivityStatus.online
        ? _checkIntervalOnline
        : _checkIntervalOffline;
    _timer = Timer.periodic(interval, (_) => _checkConnectivity());
  }

  /// Libera recursos. Llamar al cerrar la app (normalmente no necesario).
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

// ─── Riverpod Providers ───────────────────────────────────────────

/// Provider del servicio de conectividad (singleton).
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService.instance;
});

/// StreamProvider que emite cambios de conectividad.
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  // Emitir el estado actual inmediatamente, luego escuchar cambios
  return Stream.value(service.currentStatus).followedBy(service.statusStream);
});

/// Provider de conveniencia: ¿está online?
final isOnlineProvider = Provider<bool>((ref) {
  final status = ref.watch(connectivityStatusProvider);
  return status.when(
    data: (s) => s == ConnectivityStatus.online,
    loading: () => true, // Asumir online hasta verificar
    error: (_, __) => false,
  );
});

/// Extensión para concatenar streams fácilmente.
extension _StreamConcat<T> on Stream<T> {
  /// Emite todos los eventos de este stream, seguidos por los de [other].
  Stream<T> followedBy(Stream<T> other) async* {
    await for (final event in this) {
      yield event;
    }
    await for (final event in other) {
      yield event;
    }
  }
}
