import 'package:flutter_test/flutter_test.dart';
import 'package:navia/core/constants/venue_registry.dart';

/// Las 9 sedes del Evento Nacional Deportivo del TecNM 2026.
///
/// Las coordenadas las proporcionó el organizador y son reales: un dedazo
/// aquí manda a la gente a otro lado sin que nada falle visiblemente, así
/// que se protegen con pruebas.
void main() {
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
