import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sinait/data/models/announcement.dart';

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

  /// Datos demo para modo offline o primer uso.
  List<Announcement> _getOfflineDemoAnnouncements(String? zoneNodeId) {
    final now = DateTime.now();
    final allDemo = [
      Announcement(
        id: 'demo_1',
        title: 'Biblioteca: Horario extendido',
        body: 'La biblioteca estará abierta hasta las 21:00 hrs esta semana por periodo de exámenes.',
        type: AnnouncementType.info,
        zoneNodeIds: const ['biblioteca', 'cruce_noreste', 'pasillo_central_norte'],
        createdAt: now,
        priority: 7,
      ),
      Announcement(
        id: 'demo_2',
        title: '⚠️ Piso mojado en Edificio B',
        body: 'Precaución: Se está realizando limpieza en el pasillo del Edificio B, planta baja.',
        type: AnnouncementType.warning,
        zoneNodeIds: const ['edificio_b', 'cruce_oeste'],
        createdAt: now,
        priority: 9,
      ),
      Announcement(
        id: 'demo_3',
        title: 'Conferencia de IA en Auditorio',
        body: 'Hoy a las 16:00 hrs: "Inteligencia Artificial aplicada a la accesibilidad". Entrada libre.',
        type: AnnouncementType.event,
        zoneNodeIds: const ['auditorio', 'cruce_oeste', 'pasillo_central_medio'],
        createdAt: now,
        priority: 6,
      ),
      Announcement(
        id: 'demo_4',
        title: 'Cafetería: Menú especial',
        body: 'Hoy tenemos menú especial por día del estudiante. ¡No te lo pierdas!',
        type: AnnouncementType.service,
        zoneNodeIds: const ['cafeteria', 'cruce_sureste', 'pasillo_central_sur'],
        createdAt: now,
        priority: 4,
      ),
      Announcement(
        id: 'demo_5',
        title: 'Mantenimiento en Lab. Electrónica',
        body: 'El laboratorio de electrónica estará cerrado el viernes por mantenimiento de equipos.',
        type: AnnouncementType.closure,
        zoneNodeIds: const ['lab_electronica', 'cruce_este'],
        createdAt: now,
        expiresAt: now.add(const Duration(days: 5)),
        priority: 8,
      ),
      Announcement(
        id: 'demo_6',
        title: 'Bienvenido al TecNM Colima',
        body: 'SINAIT te guía por el campus. Escanea un QR para empezar o usa el comando de voz "Llévame a...".',
        type: AnnouncementType.info,
        zoneNodeIds: const ['entrada_principal', 'entrada_sur', 'estacionamiento'],
        createdAt: now,
        priority: 5,
      ),
    ];

    if (zoneNodeId == null) return allDemo;

    return allDemo
        .where((a) => a.isRelevantFor(zoneNodeId))
        .toList();
  }
}
