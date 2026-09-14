// Datos de las 9 sedes empaquetados dentro de la app.
//
// POR QUÉ EXISTE ESTO
//
// Antes, cada arranque leía de Firestore los ~134 documentos de las 9 sedes,
// y además `watchPlaces` abría un listener que vuelve a leer la colección
// completa al conectarse. Con 40,000 asistentes eso son millones de lecturas
// facturadas al día — por datos que no cambian: las canchas de una unidad
// deportiva no se mueven durante el evento.
//
// Ahora esos documentos viajan dentro del APK (`assets/maps/venues_bundle.json`,
// ~25 KB) y Firestore solo se consulta para UNA cosa: un documento diminuto
// con el número de versión de los datos. Si el número no subió, no se lee
// nada más. Eso deja el consumo debajo del tramo gratuito de Firestore
// (50,000 lecturas al día) y, de paso, hace que el mapa abra al instante y
// funcione sin señal aunque sea la primera vez que alguien abre esa sede.
//
// CÓMO SE ACTUALIZA
//
// Cuando el administrador edita puntos, sube `dataVersion` en el documento
// `app_meta/venue_data` de Firestore. Los teléfonos lo detectan en su
// siguiente revisión (máximo 12 h después) y a partir de ahí leen de
// Firestore en vez del paquete, hasta que se publique un APK nuevo.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/place_node.dart';

class VenueBundle {
  VenueBundle._();

  static const String assetPath = 'assets/maps/venues_bundle.json';

  static Map<String, dynamic>? _data;
  static Future<Map<String, dynamic>>? _cargando;

  /// Carga el paquete una sola vez por proceso.
  static Future<Map<String, dynamic>> _load() {
    if (_data != null) return Future.value(_data!);
    return _cargando ??= () async {
      try {
        final raw = await rootBundle.loadString(assetPath);
        _data = json.decode(raw) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('VenueBundle: no se pudo leer $assetPath → $e');
        _data = const {'dataVersion': 0, 'venues': <String, dynamic>{}};
      }
      return _data!;
    }();
  }

  /// Versión de los datos que viajan en este APK.
  static Future<int> version() async =>
      (await _load())['dataVersion'] as int? ?? 0;

  static Future<List<Map<String, dynamic>>> _coleccion(
      String zoneId, String nombre) async {
    final data = await _load();
    final venues = data['venues'] as Map<String, dynamic>?;
    final venue = venues?[zoneId] as Map<String, dynamic>?;
    final lista = venue?[nombre] as List<dynamic>?;
    if (lista == null) return const [];
    return lista.cast<Map<String, dynamic>>();
  }

  static Future<List<PlaceNode>> places(String zoneId) async {
    final docs = await _coleccion(zoneId, 'places');
    return docs.map((d) => _placeDesdeMapa(zoneId, d)).toList();
  }

  static Future<List<CampusNode>> nodes(String zoneId) async {
    final docs = await _coleccion(zoneId, 'nodes');
    return docs.map((d) => _nodoDesdeMapa(zoneId, d)).toList();
  }

  static Future<List<CampusEdge>> edges(String zoneId) async {
    final docs = await _coleccion(zoneId, 'edges');
    return docs.map((d) => _aristaDesdeMapa(zoneId, d)).toList();
  }

  // Los mapas del paquete traen exactamente los campos del documento de
  // Firestore más un `id`, así que se reutilizan los mismos constructores
  // `fromFirestoreMap` de los modelos: una sola definición de cómo se lee un
  // documento, venga de la red o del APK.

  static PlaceNode _placeDesdeMapa(String zoneId, Map<String, dynamic> d) =>
      PlaceNode(
        id: d['id'] as String,
        zoneId: zoneId,
        name: (d['name'] as String?) ?? 'Sin nombre',
        latitude: _num(d['latitude']),
        longitude: _num(d['longitude']),
        type: (d['type'] as String?) ?? 'Punto',
        accessibilityLevel: (d['accessibilityLevel'] as String?) ?? 'medio',
        letter: d['letter'] as String?,
        imageUrl: d['imageUrl'] as String?,
      );

  static CampusNode _nodoDesdeMapa(String zoneId, Map<String, dynamic> d) =>
      CampusNode.fromFirestoreMap(zoneId, d['id'] as String, d);

  static CampusEdge _aristaDesdeMapa(String zoneId, Map<String, dynamic> d) =>
      CampusEdge.fromFirestoreMap(zoneId, d);

  static double _num(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
}

/// Decide si el paquete que trae el APK sigue sirviendo, o si el admin ya
/// publicó datos más nuevos y hay que ir a Firestore.
///
/// Se hace ESCUCHANDO el documento en vivo, no preguntando cada cierto rato.
/// La primera versión revisaba cada 12 h, y eso significaba que una
/// corrección del admin —mover una cancha mal ubicada en pleno evento—
/// tardaba hasta medio día en llegarle a la gente.
///
/// Escuchar sale igual de barato: Firestore cobra una lectura al conectarse y
/// después solo cuando el documento cambia. Con 40,000 asistentes son ~40,000
/// lecturas al día (el tramo gratuito son 50,000), y el cambio llega en
/// segundos en vez de en 12 horas.
class VenueDataVersion {
  VenueDataVersion._();

  static const String coleccion = 'app_meta';
  static const String documento = 'venue_data';

  static const String _kUltimaVersionVista = 'venue_data_version_remota';

  /// Versión publicada por el admin, en vivo.
  ///
  /// Ante cualquier problema (sin red, documento ausente, permisos) emite la
  /// última versión conocida —o la del propio APK— en vez de propagar el
  /// error: es preferible mostrar los datos empaquetados, que son correctos,
  /// a dejar el mapa vacío. Un corte de red no debe vaciar la pantalla.
  static Stream<int> versionEnVivo() async* {
    final local = await VenueBundle.version();
    int respaldo = local;
    try {
      final prefs = await SharedPreferences.getInstance();
      respaldo = prefs.getInt(_kUltimaVersionVista) ?? local;
    } catch (_) {
      // Sin SharedPreferences (pruebas): basta con la versión del APK.
    }

    yield respaldo; // algo que mostrar de inmediato, sin esperar a la red

    yield* FirebaseFirestore.instance
        .collection(coleccion)
        .doc(documento)
        .snapshots()
        .map((doc) {
          final v = (doc.data()?['dataVersion'] as num?)?.toInt();
          if (v == null) return respaldo;
          _recordar(v);
          if (v > local) {
            debugPrint('VenueDataVersion: el admin publicó la versión $v '
                '(el APK trae la $local); se leerá de Firestore.');
          }
          return v;
        })
        .handleError((Object e) {
          debugPrint('VenueDataVersion: no se pudo escuchar la versión ($e); '
              'se siguen usando los datos del APK.');
        });
  }

  /// Sube `dataVersion` para que los teléfonos (incluido el del propio admin)
  /// dejen el paquete del APK y lean de Firestore. Se llama tras cada
  /// escritura del editor: sin esto, `watchPlaces` seguía sirviendo el
  /// paquete y el punto recién creado desaparecía al salir del modo edición.
  ///
  /// Nunca queda por debajo de la versión del APK (si el documento no existe,
  /// un simple incremento daría 1 y seguiría "vigente" el paquete).
  static Future<void> publicarCambio(FirebaseFirestore firestore) async {
    final local = await VenueBundle.version();
    final ref = firestore.collection(coleccion).doc(documento);
    try {
      await firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final remota = (snap.data()?['dataVersion'] as num?)?.toInt() ?? 0;
        final base = remota > local ? remota : local;
        tx.set(ref, {'dataVersion': base + 1}, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('VenueDataVersion: no se pudo publicar el cambio ($e)');
    }
  }

  static Future<void> _recordar(int version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kUltimaVersionVista, version);
    } catch (_) {
      // No poder recordarla solo cuesta una lectura extra al siguiente
      // arranque; no es motivo para fallar.
    }
  }

  /// Respuesta puntual (no en vivo) para decisiones de una sola vez, como
  /// saltarse la precarga offline al arrancar.
  static Future<bool> paqueteVigente() async {
    try {
      final local = await VenueBundle.version();
      final remota = await versionEnVivo().first;
      return remota <= local;
    } catch (e) {
      debugPrint('VenueDataVersion: no se pudo resolver la versión ($e); '
          'se usan los datos del APK.');
      return true;
    }
  }
}
