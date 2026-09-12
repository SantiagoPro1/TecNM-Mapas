import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navia/core/constants/venue_registry.dart';

/// Las 9 sedes del Evento Nacional Deportivo del TecNM 2026.
///
/// Las coordenadas las proporcionó el organizador y son reales: un dedazo
/// aquí manda a la gente a otro lado sin que nada falle visiblemente, así
/// que se protegen con pruebas.
void main() {
  _verificarEncuadreConDatosReales();

  test('están registradas las 9 sedes', () {
    expect(VenueRegistry.all.length, 9);
  });

  test('ningún id repetido', () {
    final ids = VenueRegistry.all.map((v) => v.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('ninguna sede se quedó sin nombre ni descripción', () {
    for (final v in VenueRegistry.all) {
      expect(v.label.trim(), isNotEmpty, reason: 'sede ${v.id} sin nombre');
      expect(v.shortDescription.trim(), isNotEmpty,
          reason: 'sede ${v.id} sin descripción');
    }
  });

  test('todas las sedes caen dentro de la región de Colima', () {
    // Caja generosa alrededor de Colima/Villa de Álvarez/Coquimatlán.
    // Atrapa signos invertidos o coordenadas pegadas de otro lugar.
    for (final v in VenueRegistry.all) {
      expect(v.centerLat, inInclusiveRange(19.10, 19.40),
          reason: 'latitud fuera de rango en ${v.id}');
      expect(v.centerLng, inInclusiveRange(-103.90, -103.60),
          reason: 'longitud fuera de rango en ${v.id}');
    }
  });

  test('la caja de cámara de cada sede contiene su propio centro', () {
    // Si esto falla, el mapa se abre "atorado" fuera de la vista de la sede.
    for (final v in VenueRegistry.all) {
      expect(v.centerLat, greaterThan(v.boundsSouthLat), reason: v.id);
      expect(v.centerLat, lessThan(v.boundsNorthLat), reason: v.id);
      expect(v.centerLng, greaterThan(v.boundsWestLng), reason: v.id);
      expect(v.centerLng, lessThan(v.boundsEastLng), reason: v.id);
    }
  });

  test('byId regresa la sede correcta y cae a TecNM Colima si no existe', () {
    expect(VenueRegistry.byId('coquimatlan').label, 'Coquimatlán');
    expect(VenueRegistry.byId('id_inventado').id, VenueRegistry.tecColima.id);
  });

  test('solo TecNM Colima trae mapa empaquetado en assets', () {
    // Las 8 sedes del evento se levantan desde Firestore con el editor de
    // administrador; si alguna aparece aquí es que se le puso mapAssetPath
    // por error y va a intentar leer un archivo que no existe.
    expect(VenueRegistry.bundledVenues.map((v) => v.id), ['tec_colima']);
  });
}

/// El centro de cada sede debe caer entre sus canchas, no en el punto donde
/// originalmente se buscó la sede en Google. Esa fue justo la falla de Unidad
/// Morelos: su centro apuntaba a la esquina noroeste, ~180 m fuera del
/// conjunto de canchas, así que el mapa abría encuadrando el terreno vecino.
///
/// La fuente de verdad son los datos verificados en `scripts/venue_places/`,
/// que es de donde salen los puntos que se siembran en Firestore.
void _verificarEncuadreConDatosReales() {
  final dir = Directory('scripts/venue_places');
  if (!dir.existsSync()) return; // el dataset no viaja en el paquete publicado

  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final venueId = data['venueId'] as String;
    final places = (data['places'] as List).cast<Map<String, dynamic>>();
    if (places.isEmpty) continue;

    final venue = VenueRegistry.byId(venueId);
    if (venue.id != venueId) continue; // sede sin registro propio

    final lats = places.map((p) => (p['lat'] as num).toDouble()).toList();
    final lngs = places.map((p) => (p['lon'] as num).toDouble()).toList();
    final minLat = lats.reduce(min), maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min), maxLng = lngs.reduce(max);

    test('$venueId: el centro cae entre sus canchas', () {
      expect(venue.centerLat, inInclusiveRange(minLat, maxLat));
      expect(venue.centerLng, inInclusiveRange(minLng, maxLng));

      // Y no solo dentro: a menos de 120 m del medio real del conjunto.
      final midLat = (minLat + maxLat) / 2, midLng = (minLng + maxLng) / 2;
      final dy = (venue.centerLat - midLat) * 111320;
      final dx = (venue.centerLng - midLng) * 111320 * cos(midLat * pi / 180);
      expect(sqrt(dx * dx + dy * dy), lessThan(120),
          reason: 'el centro de $venueId quedó descentrado respecto a sus '
              'puntos reales');
    });

    test('$venueId: la caja de cámara contiene todas sus canchas', () {
      expect(venue.boundsSouthLat, lessThanOrEqualTo(minLat));
      expect(venue.boundsNorthLat, greaterThanOrEqualTo(maxLat));
      expect(venue.boundsWestLng, lessThanOrEqualTo(minLng));
      expect(venue.boundsEastLng, greaterThanOrEqualTo(maxLng));
    });
  }
}
