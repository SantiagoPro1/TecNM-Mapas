import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    hostedDomain: 'colima.tecnm.mx', 
  );

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      // --- VALIDACIÓN DE DOMINIO ---
      if (!googleUser.email.endsWith('@colima.tecnm.mx')) {
        await _googleSignIn.signOut(); // Lo sacamos de Google de inmediato
        throw 'Solo se permiten correos @colima.tecnm.mx';
      }
      // ----------------------------

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      rethrow; // Lanzamos el error para que la pantalla lo atrape y lo muestre
    }
  }

  // Cerrar sesión
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Obtener usuario actual
  User? get currentUser => _auth.currentUser;

  // Truco para extraer la matrícula del correo institucional
  String getMatricula(String? email) {
    if (email == null || !email.contains('@')) return 'Sin matrícula';
    // Si el correo es 22460290@colima.tecnm.mx, esto devuelve "22460290"
    return email.split('@')[0];
  }
}