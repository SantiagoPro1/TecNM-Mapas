import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Servicio de credencial digital con QR dinámico.
///
/// Genera un token JWT-like con TTL de 60 segundos para el QR
/// de la credencial del alumno. El token se regenera automáticamente.
///
/// La firma es HMAC-SHA256 real (RFC 2104) sobre
/// `base64url(header).base64url(payload)`, con la misma clave compartida que
/// usa el backend para verificar. Antes era un hash propio de 32 bits
/// (`hash << 5`), que se puede invertir/forzar en segundos: cualquiera podía
/// fabricar una credencial válida sin conocer la clave.
///
/// LÍMITE CONOCIDO: la clave viaja dentro del APK, así que quien lo
/// descompile puede firmar credenciales. Eso acota el ataque a alguien con
/// conocimientos y acceso al binario, en vez de a cualquiera con diez líneas
/// de script — pero la solución definitiva es que el QR lleve el ID token de
/// Firebase y el backend lo valide contra Google (no hay secreto que
/// extraer). Ver `verifyFirebaseToken` en el backend, que ya hace eso.
class CredentialService {
  /// Duración del token en segundos.
  static const int tokenTtlSeconds = 60;

  /// Clave compartida con el backend. Sale de `.env` (`CREDENTIAL_SECRET`)
  /// para que se pueda rotar sin recompilar la app a mano y, sobre todo, para
  /// que sea LA MISMA de los dos lados.
  ///
  /// Bug histórico que esto corrige: la app firmaba con
  /// `NAVIA_TecNM_2026_SecretKey` y el backend verificaba con
  /// `SINAIT_TecNM_2026_SecretKey`. Ninguna credencial escaneada podía pasar
  /// la verificación — todas devolvían 401 "Firma de credencial inválida".
  static String get _secretKey {
    try {
      final k = dotenv.env['CREDENTIAL_SECRET'];
      if (k != null && k.isNotEmpty) return k;
    } catch (_) {
      // `dotenv.env` lanza si nunca se llamó a `dotenv.load` — pasa en las
      // pruebas unitarias, que no arrancan la app completa.
    }
    // Mismo valor por defecto que el backend, para que ambos lados sigan
    // coincidiendo aunque falte el .env.
    return 'NAVIA_TecNM_2026_SecretKey';
  }

  /// Genera un token JWT-like para el QR de la credencial.
  ///
  /// Payload:
  /// - sub: matrícula del alumno
  /// - name: nombre completo
  /// - campus: campus de origen
  /// - iat: timestamp de emisión (epoch seconds)
  /// - exp: timestamp de expiración (iat + 60s)
  /// - jti: ID único del token
  static String generateCredentialToken({
    required String matricula,
    required String fullName,
    String campus = 'TecNM Colima',
  }) {
    final now = DateTime.now();
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    final exp = iat + tokenTtlSeconds;

    // Header
    final header = {
      'alg': 'HS256',
      'typ': 'JWT',
    };

    // Payload
    final payload = {
      'sub': matricula,
      'name': fullName,
      'campus': campus,
      'iat': iat,
      'exp': exp,
      'jti': _generateJti(),
      'type': 'student_credential',
    };

    // Encode
    final headerB64 = _base64UrlEncode(json.encode(header));
    final payloadB64 = _base64UrlEncode(json.encode(payload));

    // Signature (HMAC-SHA256 simplificado)
    final signature = _sign('$headerB64.$payloadB64');

    return '$headerB64.$payloadB64.$signature';
  }

  /// Decodifica un token y retorna el payload (sin verificar firma).
  static Map<String, dynamic>? decodeToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payloadStr = _base64UrlDecode(parts[1]);
      return json.decode(payloadStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Verifica si un token es válido (firma + expiración).
  static bool verifyToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;

      // Verificar firma
      final expectedSig = _sign('${parts[0]}.${parts[1]}');
      if (parts[2] != expectedSig) return false;

      // Verificar expiración
      final payload = decodeToken(token);
      if (payload == null) return false;

      final exp = payload['exp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now < exp;
    } catch (e) {
      return false;
    }
  }

  /// Tiempo restante del token en segundos.
  static int remainingSeconds(String token) {
    final payload = decodeToken(token);
    if (payload == null) return 0;

    final exp = payload['exp'] as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = exp - now;
    return remaining > 0 ? remaining : 0;
  }

  /// ¿Ha expirado el token?
  static bool isExpired(String token) => remainingSeconds(token) <= 0;

  // ─── Utilidades internas ─────────────────────────────────────

  static String _base64UrlEncode(String input) {
    return base64Url.encode(utf8.encode(input)).replaceAll('=', '');
  }

  static String _base64UrlDecode(String input) {
    // Restore padding
    String padded = input;
    switch (input.length % 4) {
      case 2:
        padded += '==';
        break;
      case 3:
        padded += '=';
        break;
    }
    return utf8.decode(base64Url.decode(padded));
  }

  /// Firma HMAC-SHA256 en base64url sin relleno, igual que un JWT HS256 real.
  static String _sign(String data) {
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    return base64Url
        .encode(hmac.convert(utf8.encode(data)).bytes)
        .replaceAll('=', '');
  }

  /// Genera un ID único para el token (jti claim).
  static String _generateJti() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rand = random.nextInt(999999);
    return '${timestamp.toRadixString(36)}-${rand.toRadixString(36)}';
  }
}
