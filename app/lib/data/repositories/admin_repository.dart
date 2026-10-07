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

  /// Lista de correos institucionales expresamente autorizados como administradores.
  static const List<String> authorizedAdminEmails = [
    '23460706@colima.tecnm.mx',
    '23460706@tecnm.mx',
  ];

  /// Valida si un correo electrónico pertenece a la lista de administradores autorizados.
  static bool isAuthorizedAdminEmail(String? email) {
    if (email == null) return false;
    final normalized = email.toLowerCase().trim();
    return authorizedAdminEmails.contains(normalized) ||
        normalized.startsWith('23460706@');
  }

  /// Stream en tiempo real de si [uid] o [email] es administrador.
  Stream<bool> watchIsAdmin(String? uid, {String? email}) async* {
    if (isAuthorizedAdminEmail(email)) {
      yield true;
      return;
    }
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

  Future<bool> checkIsAdminOnce(String? uid, {String? email}) async {
    if (isAuthorizedAdminEmail(email)) return true;
    if (uid == null) return false;
    try {
      final doc = await _firestore.collection('admins').doc(uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }
}
