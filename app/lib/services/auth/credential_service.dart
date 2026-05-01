import 'dart:convert';
import 'dart:math';

/// Servicio de credencial digital con QR dinámico.
///
/// Genera un token JWT-like con TTL de 60 segundos para el QR
/// de la credencial del alumno. El token se regenera automáticamente.
///
/// NOTA: Esto es un JWT simplificado on-device. La validación real
/// se hace en el backend con la clave secreta compartida.
class CredentialService {
  /// Duración del token en segundos.
  static const int tokenTtlSeconds = 60;

  /// Clave secreta para firma HMAC (en producción, usar dotenv/secure storage).
  static const String _secretKey = 'SINAIT_TecNM_2026_SecretKey';

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

  /// Firma HMAC simplificada (hash determinístico).
  /// En producción real, usar package:crypto con HMAC-SHA256.
  static String _sign(String data) {
    // Simple hash basado en la data + secret key
    final input = '$data.$_secretKey';
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash + input.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    // Second pass for better distribution
    final input2 = '${hash.toRadixString(16)}.$_secretKey';
    int hash2 = 0;
    for (int i = 0; i < input2.length; i++) {
      hash2 = ((hash2 << 5) - hash2 + input2.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return '${hash.toRadixString(16)}${hash2.toRadixString(16)}';
  }

  /// Genera un ID único para el token (jti claim).
  static String _generateJti() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rand = random.nextInt(999999);
    return '${timestamp.toRadixString(36)}-${rand.toRadixString(36)}';
  }
}
