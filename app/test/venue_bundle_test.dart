import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navia/core/constants/venue_registry.dart';

/// El paquete `assets/maps/venues_bundle.json` es ahora la fuente de los
/// puntos del mapa: si viene mal, la app abre sin nada y nadie encuentra su
/// cancha. Se valida contra el archivo real, no contra un doble.
///
/// (Se lee con `File` en vez de `rootBundle` porque estas pruebas corren sin
/// motor de Flutter; el contenido es el mismo archivo que se empaqueta.)
void main() {
  final archivo = File('assets/maps/venues_bundle.json');

  late Map<String, dynamic> bundle;

  setUpAll(() {
    bundle = json.decode(archivo.readAsStringSync()) as Map<String, dynamic>;
  });

  test('el archivo existe y es JSON válido', () {
    expect(archivo.existsSync(), isTrue);
    expect(bundle['venues'], isA<Map<String, dynamic>>());
  });

  test('trae una versión de datos usable', () {
    expect(bundle['dataVersion'], isA<int>());
    expect(bundle['dataVersion'], greaterThan(0));
  });

  test('están las 9 sedes del registro', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    for (final v in VenueRegistry.all) {
      expect(venues.containsKey(v.id), isTrue,
          reason: 'falta la sede ${v.id} en el paquete');
    }
  });

  test('ninguna sede quedó sin puntos', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    for (final entry in venues.entries) {
      final places = (entry.value as Map<String, dynamic>)['places'] as List;
      expect(places, isNotEmpty,
          reason: '${entry.key} se quedó sin puntos: su mapa saldría vacío');
    }
  });

  test('cada punto trae id, nombre y coordenadas reales', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    for (final entry in venues.entries) {
      final places = (entry.value as Map<String, dynamic>)['places'] as List;
      for (final p in places.cast<Map<String, dynamic>>()) {
        final donde = '${entry.key}/${p['id']}';
        expect(p['id'], isA<String>(), reason: donde);
        expect((p['id'] as String).isNotEmpty, isTrue, reason: donde);
        expect(p['name'], isA<String>(), reason: donde);

        final lat = (p['latitude'] as num?)?.toDouble();
        final lng = (p['longitude'] as num?)?.toDouble();
        expect(lat, isNotNull, reason: donde);
        expect(lng, isNotNull, reason: donde);
        // Colima: ningún punto puede caer fuera del estado.
        expect(lat!, inInclusiveRange(18.6, 19.6), reason: donde);
        expect(lng!, inInclusiveRange(-104.8, -103.4), reason: donde);
      }
    }
  });

  test('no hay ids repetidos dentro de una misma sede', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    for (final entry in venues.entries) {
      final places = (entry.value as Map<String, dynamic>)['places'] as List;
      final ids = places.map((p) => (p as Map)['id']).toList();
      expect(ids.toSet().length, ids.length,
          reason: '${entry.key} tiene ids de punto repetidos');
    }
  });

  test('cada punto del paquete cae dentro de la caja de su sede', () {
    final venues = bundle['venues'] as Map<String, dynamic>;
    for (final entry in venues.entries) {
      final venue = VenueRegistry.byId(entry.key);
      if (venue.id != entry.key) continue;
      final places = (entry.value as Map<String, dynamic>)['places'] as List;
      for (final p in places.cast<Map<String, dynamic>>()) {
        final lat = (p['latitude'] as num).toDouble();
        final lng = (p['longitude'] as num).toDouble();
        expect(lat, inInclusiveRange(venue.boundsSouthLat, venue.boundsNorthLat),
            reason: '${entry.key}/${p['id']} queda fuera de la caja de cámara');
        expect(lng, inInclusiveRange(venue.boundsWestLng, venue.boundsEastLng),
            reason: '${entry.key}/${p['id']} queda fuera de la caja de cámara');
      }
    }
  });
}
