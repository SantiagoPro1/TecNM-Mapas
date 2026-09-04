import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/campus_node.dart';

/// CRUD en tiempo real contra el grafo caminable de una sede
/// (`venues/{zoneId}/nodes`, `venues/{zoneId}/edges`).
///
/// Usado por las sedes que NO vienen empaquetadas en assets (las sedes del
/// Evento Nacional Deportivo): su grafo se construye en línea con el editor
/// de administrador en vez de un JSON hecho a mano.
class VenueGraphRepository {
  final FirebaseFirestore _firestore;

  VenueGraphRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _nodesCol(String zoneId) =>
      _firestore.collection('venues').doc(zoneId).collection('nodes');

  CollectionReference<Map<String, dynamic>> _edgesCol(String zoneId) =>
      _firestore.collection('venues').doc(zoneId).collection('edges');

  Stream<List<CampusNode>> watchNodes(String zoneId) {
    return _nodesCol(zoneId).snapshots().map((snap) => snap.docs
        .map((d) => CampusNode.fromFirestoreMap(zoneId, d.id, d.data()))
        .toList());
  }

  Stream<List<CampusEdge>> watchEdges(String zoneId) {
    return _edgesCol(zoneId).snapshots().map((snap) =>
        snap.docs.map((d) => CampusEdge.fromFirestoreMap(zoneId, d.data())).toList());
  }

  Future<List<CampusNode>> fetchNodesOnce(String zoneId) async {
    final snap = await _nodesCol(zoneId).get();
    return snap.docs
        .map((d) => CampusNode.fromFirestoreMap(zoneId, d.id, d.data()))
        .toList();
  }

  Future<List<CampusEdge>> fetchEdgesOnce(String zoneId) async {
    final snap = await _edgesCol(zoneId).get();
    return snap.docs.map((d) => CampusEdge.fromFirestoreMap(zoneId, d.data())).toList();
  }

  Future<void> createNode(CampusNode node) =>
      _nodesCol(node.zoneId).doc(node.id).set(node.toFirestoreMap());

  Future<void> updateNode(CampusNode node) =>
      _nodesCol(node.zoneId).doc(node.id).update(node.toFirestoreMap());

  /// Actualización parcial de solo lat/lng — para el arrastre en el editor,
  /// sin pisar el resto de los campos del nodo.
  Future<void> moveNode(
    String zoneId,
    String nodeId, {
    required double lat,
    required double lng,
  }) =>
      _nodesCol(zoneId).doc(nodeId).update({'lat': lat, 'lng': lng});

  /// Actualización parcial de solo el nombre — igual que [moveNode], sin
  /// pisar el resto de los campos.
  Future<void> renameNode(String zoneId, String nodeId, String name) =>
      _nodesCol(zoneId).doc(nodeId).update({'name': name});

  /// Borra un nodo y, en batch, cualquier arista que lo referencie (para que
  /// el grafo nunca quede apuntando a un vértice fantasma).
  Future<void> deleteNode(String zoneId, String nodeId) async {
    final outgoing = await _edgesCol(zoneId).where('from', isEqualTo: nodeId).get();
    final incoming = await _edgesCol(zoneId).where('to', isEqualTo: nodeId).get();

    final batch = _firestore.batch();
    batch.delete(_nodesCol(zoneId).doc(nodeId));
    for (final doc in [...outgoing.docs, ...incoming.docs]) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> createEdge(CampusEdge edge) =>
      _edgesCol(edge.zoneId).doc(edge.docId).set(edge.toFirestoreMap());

  Future<void> updateEdge(CampusEdge edge) =>
      _edgesCol(edge.zoneId).doc(edge.docId).update(edge.toFirestoreMap());

  Future<void> deleteEdge(String zoneId, String from, String to) =>
      _edgesCol(zoneId).doc(CampusEdge.buildDocId(from, to)).delete();

  /// Descarga una vez el grafo (nodos + aristas) de TODAS las sedes para
  /// dejarlo en la caché local de Firestore, de modo que las rutas se puedan
  /// calcular sin señal. Ver [PlaceRepository.prefetchAllVenuesForOffline].
  Future<void> prefetchAllVenuesForOffline() async {
    for (final venue in VenueRegistry.all) {
      try {
        await _nodesCol(venue.id).get();
        await _edgesCol(venue.id).get();
      } catch (e) {
        debugPrint('VenueGraphRepository: precarga falló para ${venue.id} → $e');
      }
    }
  }
}
