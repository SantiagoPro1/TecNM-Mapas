import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navia/utils/gps_filter.dart';

Position _pos(double lat, double lng, {double accuracy = 5.0}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('GpsFilter', () {
    test('acepta la primera lectura tal cual (inicializa el estimado)', () {
      final filter = GpsFilter();
      final result = filter.filter(_pos(19.26, -103.72));

      expect(result, isNotNull);
      expect(result!.latitude, closeTo(19.26, 1e-9));
      expect(result.longitude, closeTo(-103.72, 1e-9));
    });

    test('rechaza lecturas con accuracy peor que maxAccuracyM', () {
      final filter = GpsFilter(maxAccuracyM: 25.0);
      filter.filter(_pos(19.26, -103.72, accuracy: 5.0));

      // Precisión de 40m (GPS degradado, típico bajo techo/entre edificios).
      final rejected = filter.filter(_pos(19.2601, -103.7201, accuracy: 40.0));

      expect(rejected, isNull);
    });

    test('rechaza un salto imposible (outlier) respecto a la última posición',
        () {
      final filter = GpsFilter(baseMaxJumpM: 15.0);
      filter.filter(_pos(19.2600, -103.7200));

      // ~1.1km de salto instantáneo — imposible caminando entre dos lecturas.
      final rejected = filter.filter(_pos(19.2700, -103.7200));

      expect(rejected, isNull);
    });

    test(
        'tras varios rechazos consecutivos, se resetea y acepta la '
        'reubicación como legítima', () {
      final filter = GpsFilter(baseMaxJumpM: 15.0);
      filter.filter(_pos(19.2600, -103.7200));

      LatLng? lastResult;
      // 5 lecturas seguidas "lejos" — simula que el usuario de verdad se
      // movió (p. ej. subió a un vehículo) en vez de que sea ruido GPS.
      for (var i = 0; i < 5; i++) {
        final r = filter.filter(_pos(19.2700, -103.7200));
        if (r != null) lastResult = r;
      }

      expect(lastResult, isNotNull,
          reason:
              'después de _maxConsecutiveRejects rechazos, el filtro debe '
              'resetearse y aceptar la nueva posición como referencia');
    });

    test('suaviza el ruido: el estimado no salta directo al valor crudo',
        () {
      final filter = GpsFilter();
      filter.filter(_pos(19.2600, -103.7200));

      // Salto pequeño (~5m), dentro del umbral — se acepta pero el Kalman
      // lo suaviza en vez de saltar directo al valor crudo.
      final smoothed = filter.filter(_pos(19.26005, -103.7200));

      expect(smoothed, isNotNull);
      expect(smoothed!.latitude, greaterThan(19.2600));
      expect(smoothed.latitude, lessThan(19.26005));
    });

    test('reset() limpia el estado interno (no arrastra la posición previa)',
        () {
      final filter = GpsFilter(baseMaxJumpM: 15.0);
      filter.filter(_pos(19.2600, -103.7200));
      filter.reset();

      // Si el filtro no se hubiera reseteado, este salto de ~1.1km se
      // rechazaría por ser un outlier respecto a la lectura anterior.
      final result = filter.filter(_pos(19.2700, -103.7200));

      expect(result, isNotNull);
    });

    test('isStationary / isWalking reflejan la velocidad calculada', () async {
      // El cálculo de velocidad usa el reloj de pared (DateTime.now()) en
      // el momento de cada llamada a filter(), no el timestamp del propio
      // Position — por eso la prueba necesita una espera real entre ambas
      // lecturas.
      final filter = GpsFilter();
      expect(filter.isStationary, isTrue);

      filter.filter(_pos(19.2600, -103.7200));
      await Future.delayed(const Duration(milliseconds: 200));
      // Salto pequeño (~5.5m, bajo el umbral de outlier en reposo de
      // 10.5m) para que se acepte y sí actualice la velocidad.
      final second = filter.filter(_pos(19.26005, -103.7200));

      expect(second, isNotNull);
      expect(filter.speedMs, greaterThan(0));
    });
  });
}
