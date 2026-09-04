import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Acepta cualquier subdominio de tecnm.mx (ej. colima.tecnm.mx,
  /// leon.tecnm.mx, o tecnm.mx a secas) para el Evento Nacional Deportivo,
  /// donde asisten estudiantes de otros campus del país.
  ///
  /// `hostedDomain` de Google Sign-In solo acepta UN dominio literal exacto
  /// y no puede expresar un comodín — por eso no se usa aquí y la validación
  /// recae por completo en este regex.
  static final RegExp _tecnmDomainPattern =
      RegExp(r'^[^@\s]+@([a-z0-9-]+\.)*tecnm\.mx$', caseSensitive: false);

  /// `true` si [email] es un correo institucional TecNM válido.
  ///
  /// Público a propósito: es el candado de acceso de toda la app y tiene
  /// pruebas en `test/auth_domain_test.dart` — no debe romperse en silencio.
  static bool isInstitutionalEmail(String email) =>
      _tecnmDomainPattern.hasMatch(email);

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
      'https://www.googleapis.com/auth/userinfo.profile',
    ],
  );

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      // --- VALIDACIÓN DE DOMINIO ---
      if (!isInstitutionalEmail(googleUser.email)) {
        await _googleSignIn.signOut();
        throw 'Solo se permiten correos institucionales @*.tecnm.mx';
      }
      // ----------------------------

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null && (user.photoURL == null || user.photoURL!.isEmpty)) {
        // Intento 1: Foto directa de GoogleSignIn
        String? photoUrl = googleUser.photoUrl;

        // Intento 2: People API con el access token
        if ((photoUrl == null || photoUrl.isEmpty) &&
            googleAuth.accessToken != null) {
          photoUrl = await _fetchPhotoFromPeopleApi(googleAuth.accessToken!);
        }

        // Intento 3: UserInfo endpoint
        if ((photoUrl == null || photoUrl.isEmpty) &&
            googleAuth.accessToken != null) {
          photoUrl = await _fetchPhotoFromUserInfo(googleAuth.accessToken!);
        }

        if (photoUrl != null && photoUrl.isNotEmpty) {
          // Pedir la imagen en alta resolución (400px)
          photoUrl = photoUrl.replaceFirst('s96-c', 's400-c');
          await user.updatePhotoURL(photoUrl);
          await user.reload();
          return _auth.currentUser;
        }
      }

      return user;
    } catch (e) {
      rethrow;
    }
  }

  /// Obtiene la foto desde Google People API
  Future<String?> _fetchPhotoFromPeopleApi(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://people.googleapis.com/v1/people/me?personFields=photos'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final photos = data['photos'] as List<dynamic>?;
        if (photos != null && photos.isNotEmpty) {
          return photos.first['url'] as String?;
        }
      } else {
        debugPrint('People API status: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('People API error: $e');
    }
    return null;
  }

  /// Obtiene la foto desde el endpoint de UserInfo de Google
  Future<String?> _fetchPhotoFromUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['picture'] as String?;
      } else {
        debugPrint('UserInfo status: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('UserInfo error: $e');
    }
    return null;
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
    return email.split('@')[0];
  }
}
