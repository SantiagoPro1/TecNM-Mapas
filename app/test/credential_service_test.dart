import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/services/auth/credential_service.dart';

/// La credencial QR es lo único que acredita a un atleta en un acceso. Estas
/// pruebas cubren las dos fallas reales que tenía:
///
///  1. La app firmaba con `NAVIA_...` y el backend verificaba con
///     `SINAIT_...`: ninguna credencial pasaba la verificación.
///  2. La "firma HMAC-SHA256" era en realidad un hash propio de 32 bits
///     (`hash << 5`), falsificable sin conocer la clave.
void main() {
  const secreto = 'NAVIA_TecNM_2026_SecretKey';

  String token() => CredentialService.generateCredentialToken(
        matricula: 'L21450123',
        fullName: 'Atleta de Prueba',
        campus: 'TecNM Colima',
      );

  group('Formato del token', () {
    test('son tres partes separadas por punto', () {
      expect(token().split('.').length, 3);
    });

    test('el payload lleva los campos que el backend exige', () {
      final p = CredentialService.decodeToken(token())!;
      expect(p['type'], 'student_credential');
      expect(p['sub'], 'L21450123');
      expect(p['name'], 'Atleta de Prueba');
      expect(p['exp'], greaterThan(p['iat'] as int));
    });

    test('cada token trae un jti distinto', () {
      expect(CredentialService.decodeToken(token())!['jti'],
          isNot(CredentialService.decodeToken(token())!['jti']));
    });
  });

  group('Firma HMAC-SHA256 (la que verifica el backend)', () {
    test('coincide con un HMAC-SHA256 calculado por fuera', () {
      final t = token();
      final partes = t.split('.');
      final esperada = base64Url
          .encode(Hmac(sha256, utf8.encode(secreto))
              .convert(utf8.encode('${partes[0]}.${partes[1]}'))
              .bytes)
          .replaceAll('=', '');
      expect(partes[2], esperada);
    });

    test('no es el hash de 32 bits viejo', () {
      // El formato anterior era hexadecimal corto (<= 16 caracteres). Un
      // HMAC-SHA256 en base64url son 43 caracteres.
      expect(token().split('.')[2].length, 43);
    });

    test('un token con el payload alterado deja de validar', () {
      final partes = token().split('.');
      final alterado = base64Url
          .encode(utf8.encode(json.encode({
            'sub': 'L99999999', // otra matrícula
            'name': 'Impostor',
            'campus': 'TecNM Colima',
            'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
            'jti': 'x',
            'type': 'student_credential',
          })))
          .replaceAll('=', '');
      expect(
          CredentialService.verifyToken('${partes[0]}.$alterado.${partes[2]}'),
          isFalse);
    });

    test('un token íntegro y vigente sí valida', () {
      expect(CredentialService.verifyToken(token()), isTrue);
    });
  });
}
