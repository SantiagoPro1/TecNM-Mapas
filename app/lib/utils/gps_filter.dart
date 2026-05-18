import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// Filtro de señal GPS para NAVIA.
///
/// Implementa cuatro capas de refinamiento sobre las coordenadas crudas:
///
///  1. **Rechazo por accuracy**: Descarta lecturas con precisión reportada
///     superior a [maxAccuracyM] metros (señal GPS degradada).
///
///  2. **Rechazo de outliers adaptativo**: Descarta lecturas que se desvíen
///     más de un umbral dinámico (modulado por velocidad) respecto a la
///     última posición válida. Si se acumulan [_maxConsecutiveRejects]
///     rechazos, se resetea el filtro asumiendo reubicación legítima.
///
///  3. **Filtro Kalman 1D con measurement noise adaptativo**: Usa la accuracy
///     reportada por el GPS para ajustar la confianza en cada lectura.
///     Lecturas de alta precisión (< 5m) tienen más peso; lecturas de baja
///     precisión (> 15m) se suavizan agresivamente.
///
///  4. **Cálculo de velocidad instantánea**: Media exponencial de la distancia
///     entre lecturas válidas. Usado para adaptar animación, frecuencia de
///     polling y umbral de recálculo de ruta.
class GpsFilter {
  GpsFilter({
    this.maxAccuracyM = 25.0,
    this.baseMaxJumpM = 15.0,
    this.q = 1e-5,
    this.baseR = 0.5e-4,
  });

  /// Accuracy máxima aceptable (metros). Lecturas con accuracy superior
  /// se descartan directamente — señal GPS degradada (interior, multipath).
  final double maxAccuracyM;

  /// Distancia máxima base (metros) entre lecturas consecutivas.
  /// Se modula dinámicamente por la velocidad del usuario:
  ///   quieto (< 0.3 m/s) → baseMaxJumpM * 0.7
  ///   caminando            → baseMaxJumpM
  ///   rápido (> 2 m/s)     → baseMaxJumpM * 2.5
  final double baseMaxJumpM;

  /// Process noise del filtro Kalman (varianza del modelo de movimiento).
  /// Más pequeño → respuesta más lenta pero más suave.
  final double q;

  /// Measurement noise base del filtro Kalman.
  /// Se escala dinámicamente por la accuracy reportada del GPS.
  final double baseR;

  // ── Estado interno del filtro Kalman ─────────────────────────────────────
  double? _latEstimate;
  double? _lngEstimate;
  double _latP = 1.0; // Covarianza de error lat
  double _lngP = 1.0; // Covarianza de error lng

  // ── Última posición válida y timestamp para velocidad ───────────────────
  LatLng? _lastValidPosition;
  DateTime? _lastValidTimestamp;

  /// Velocidad instantánea en m/s calculada entre las últimas 2 lecturas.
  double _speedMs = 0.0;

  /// Contador de rechazos consecutivos. Si alcanza [_maxConsecutiveRejects],
  /// el filtro se resetea asumiendo que el usuario se movió legítimamente.
  int _consecutiveRejects = 0;
  static const int _maxConsecutiveRejects = 5;

  /// Intervalo real entre las dos últimas lecturas válidas (para animación).
  Duration _lastGpsInterval = const Duration(milliseconds: 800);

  /// Velocidad instantánea actual (m/s).
  double get speedMs => _speedMs;

  /// Velocidad instantánea actual (km/h).
  double get speedKmh => _speedMs * 3.6;

  /// `true` si el usuario está caminando (> 0.5 m/s ≈ 1.8 km/h).
  bool get isWalking => _speedMs > 0.5;

  /// `true` si el usuario está efectivamente quieto (< 0.3 m/s).
  bool get isStationary => _speedMs < 0.3;

  /// Última posición filtrada válida.
  LatLng? get lastPosition => _lastValidPosition;

  /// Intervalo real entre las dos últimas lecturas GPS válidas.
  Duration get lastGpsInterval => _lastGpsInterval;

  /// Umbral de salto adaptativo basado en la velocidad actual.
  double get _adaptiveMaxJump {
    if (_speedMs < 0.3) return baseMaxJumpM * 0.7; // Quieto: 10.5m
    if (_speedMs < 2.0) return baseMaxJumpM; // Caminando: 15m
    return baseMaxJumpM * 2.5; // Rápido: 37.5m
  }

  /// Procesa una nueva lectura GPS cruda.
  ///
  /// Retorna la posición filtrada si es válida, o `null` si fue rechazada
  /// por accuracy degradada, salto excesivo, o ruido.
  LatLng? filter(Position rawPosition) {
    final rawLat = rawPosition.latitude;
    final rawLng = rawPosition.longitude;
    final accuracy = rawPosition.accuracy;
    final now = DateTime.now();

    // ── 1. Rechazo por accuracy ─────────────────────────────────────────
    if (accuracy > maxAccuracyM) {
      // Señal GPS demasiado imprecisa — descartar
      _consecutiveRejects++;
      if (_consecutiveRejects >= _maxConsecutiveRejects) {
        // Demasiados rechazos consecutivos: resetear filtro y aceptar
        // esta lectura como nueva referencia (reubicación forzada).
        reset();
      } else {
        return null;
      }
    }

    // ── 2. Rechazo de outliers adaptativo ───────────────────────────────
    if (_lastValidPosition != null) {
      final jump = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        rawLat,
        rawLng,
      );

      if (jump > _adaptiveMaxJump) {
        _consecutiveRejects++;
        if (_consecutiveRejects >= _maxConsecutiveRejects) {
          // Muchos rechazos → probablemente se movió legítimamente
          reset();
        } else {
          return null;
        }
      }
    }

    // Lectura aceptada: resetear contador de rechazos
    _consecutiveRejects = 0;

    // ── 3. Filtro Kalman 1D con measurement noise adaptativo ────────────
    //
    // Escalar R por la accuracy reportada:
    //   accuracy <  5m → factor ≈ 0.25 (confiar mucho en la lectura)
    //   accuracy = 10m → factor ≈ 1.0  (noise base)
    //   accuracy > 20m → factor ≈ 4.0  (suavizar agresivamente)
    final accuracyFactor = math.max(0.1, (accuracy / 10.0) * (accuracy / 10.0));
    final dynamicR = baseR * accuracyFactor;

    if (_latEstimate == null) {
      // Primera lectura: inicializar
      _latEstimate = rawLat;
      _lngEstimate = rawLng;
      _latP = 1.0;
      _lngP = 1.0;
    } else {
      // Predicción (modelo de velocidad constante simplificado)
      _latP += q;
      _lngP += q;

      // Actualización (corrección con la nueva lectura)
      final latK = _latP / (_latP + dynamicR); // Ganancia de Kalman lat
      final lngK = _lngP / (_lngP + dynamicR); // Ganancia de Kalman lng

      _latEstimate = _latEstimate! + latK * (rawLat - _latEstimate!);
      _lngEstimate = _lngEstimate! + lngK * (rawLng - _lngEstimate!);

      _latP = (1 - latK) * _latP;
      _lngP = (1 - lngK) * _lngP;
    }

    final filtered = LatLng(_latEstimate!, _lngEstimate!);

    // ── 4. Cálculo de velocidad instantánea ─────────────────────────────
    if (_lastValidPosition != null && _lastValidTimestamp != null) {
      final dt = now.difference(_lastValidTimestamp!).inMilliseconds / 1000.0;
      if (dt > 0.05) {
        // Evitar división por intervalos minúsculos
        final dist = Geolocator.distanceBetween(
          _lastValidPosition!.latitude,
          _lastValidPosition!.longitude,
          filtered.latitude,
          filtered.longitude,
        );
        // Media exponencial para suavizar la velocidad
        final instantSpeed = dist / dt;
        _speedMs = _speedMs * 0.6 + instantSpeed * 0.4;

        // Registrar intervalo real entre lecturas para calibrar animación
        _lastGpsInterval = Duration(
            milliseconds: now.difference(_lastValidTimestamp!).inMilliseconds);
      }
    }

    _lastValidPosition = filtered;
    _lastValidTimestamp = now;

    return filtered;
  }

  /// Reinicia el estado del filtro (por ejemplo, al cambiar de zona).
  void reset() {
    _latEstimate = null;
    _lngEstimate = null;
    _latP = 1.0;
    _lngP = 1.0;
    _lastValidPosition = null;
    _lastValidTimestamp = null;
    _speedMs = 0.0;
    _consecutiveRejects = 0;
    _lastGpsInterval = const Duration(milliseconds: 800);
  }

  /// Calcula la duración óptima de animación de interpolación del marcador
  /// según la velocidad actual del usuario y el intervalo real entre lecturas.
  ///
  /// La duración es el MÍNIMO entre:
  ///   - Duración basada en velocidad (lento=1200ms, normal=600ms, rápido=300ms)
  ///   - 1.3× el intervalo real entre lecturas GPS (para evitar que la animación
  ///     dure más que el gap entre actualizaciones)
  ///
  /// Esto garantiza que el marcador siempre alcanza su destino antes de que
  /// llegue la siguiente lectura, evitando "lag acumulado".
  Duration get adaptiveAnimationDuration {
    final speedBased = _speedMs < 0.3
        ? const Duration(milliseconds: 1200)
        : _speedMs < 2.0
            ? const Duration(milliseconds: 600)
            : const Duration(milliseconds: 300);

    // 1.3× el intervalo GPS real, clamped entre 250ms y 1500ms
    final intervalBased = Duration(
      milliseconds:
          (_lastGpsInterval.inMilliseconds * 1.3).round().clamp(250, 1500),
    );

    // Usar el menor de ambos para no acumular lag
    return speedBased < intervalBased ? speedBased : intervalBased;
  }

  /// Calcula el umbral de desviación (metros) para recalcular la ruta.
  ///
  /// - Quieto: 15m — evitar recálculos por ruido GPS.
  /// - Caminando: 10m — standard.
  /// - Rápido: 8m — recalcular antes para no perder el camino.
  double get routeRecalcThresholdM {
    if (_speedMs < 0.3) return 15.0;
    if (_speedMs < 2.0) return 10.0;
    return 8.0;
  }

  /// Distancia en metros entre dos puntos LatLng.
  static double distanceBetween(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }
}
