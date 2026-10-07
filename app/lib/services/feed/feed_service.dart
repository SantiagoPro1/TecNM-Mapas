import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:navia/data/models/announcement.dart';

/// Servicio de Feed Contextual.
///
/// Obtiene avisos desde Firestore filtrados por la zona
/// del campus donde se encuentra el usuario.
/// En modo offline, retorna avisos demo precargados.
class FeedService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Colección de avisos en Firestore.
  static const _collection = 'announcements';

  /// Obtiene avisos relevantes para una zona del campus.
  ///
  /// [zoneNodeId] es el ID del nodo actual del usuario.
  /// Busca avisos cuyo campo `zoneNodeIds` contenga ese nodo.
  Future<List<Announcement>> getAnnouncementsForZone(String zoneNodeId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('zoneNodeIds', arrayContains: zoneNodeId)
          .where('active', isEqualTo: true)
          .orderBy('priority', descending: true)
          .limit(10)
          .get();

      return snapshot.docs
          .map((doc) => Announcement.fromJson({...doc.data(), 'id': doc.id}))
          .where((a) => a.shouldShow)
          .toList();
    } catch (e) {
      // Fallback a datos locales si Firestore no está disponible (modo offline)
      return _getOfflineDemoAnnouncements(zoneNodeId);
    }
  }

  /// Obtiene todos los avisos activos (para admin o vista general).
  Future<List<Announcement>> getAllActive() async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('active', isEqualTo: true)
          .orderBy('priority', descending: true)
          .limit(20)
          .get();

      return snapshot.docs
          .map((doc) => Announcement.fromJson({...doc.data(), 'id': doc.id}))
          .where((a) => a.shouldShow)
          .toList();
    } catch (e) {
      return _getOfflineDemoAnnouncements(null);
    }
  }

  /// Stream en tiempo real de avisos para una zona.
  Stream<List<Announcement>> watchZone(String zoneNodeId) {
    return _firestore
        .collection(_collection)
        .where('zoneNodeIds', arrayContains: zoneNodeId)
        .where('active', isEqualTo: true)
        .orderBy('priority', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Announcement.fromJson({...doc.data(), 'id': doc.id}))
            .where((a) => a.shouldShow)
            .toList());
  }

  /// Obtiene avisos para una sede específica.
  Future<List<Announcement>> getAnnouncementsForVenue(String venueId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('venueId', isEqualTo: venueId)
          .where('active', isEqualTo: true)
          .orderBy('priority', descending: true)
          .limit(10)
          .get();

      return snapshot.docs
          .map((doc) => Announcement.fromJson({...doc.data(), 'id': doc.id}))
          .where((a) => a.shouldShow)
          .toList();
    } catch (e) {
      return const [];
    }
  }

  /// Datos demo para modo offline o primer uso (vacío para no inyectar datos ficticios).
  List<Announcement> _getOfflineDemoAnnouncements(String? zoneNodeId) {
    return const [];
  }
}
