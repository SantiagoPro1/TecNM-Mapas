import 'package:cloud_firestore/cloud_firestore.dart';

/// Consulta el rol de administrador contra la colección `admins/{uid}`.
///
/// No hay UI para auto-otorgarse el rol a propósito: el primer (y cada)
/// administrador se da de alta a mano desde la consola de Firebase
/// (Firestore → crear documento `admins/{uid del usuario}`). Las reglas de
/// seguridad (`firestore.rules`) prohíben escribir esta colección desde el
/// cliente, así nadie puede auto-promoverse.
class AdminRepository {
  final FirebaseFirestore _firestore;

  AdminRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Stream en tiempo real de si [uid] es administrador. `false` si no hay
  /// sesión iniciada o si Firestore no está disponible.
  Stream<bool> watchIsAdmin(String? uid) async* {
    if (uid == null) {
      yield false;
      return;
    }
    try {
      await for (final doc in _firestore.collection('admins').doc(uid).snapshots()) {
        yield doc.exists;
      }
    } catch (_) {
      yield false;
    }
  }

  Future<bool> checkIsAdminOnce(String? uid) async {
    if (uid == null) return false;
    try {
      final doc = await _firestore.collection('admins').doc(uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }
}
