import 'package:flutter_test/flutter_test.dart';
import 'package:navia/services/auth/auth_service.dart';

/// El candado de acceso de la app: solo correos @*.tecnm.mx.
///
/// Se amplió de "solo @colima.tecnm.mx" a cualquier campus para el Evento
/// Nacional Deportivo. El backend replica esta misma regla en
/// `backend/src/middleware/auth.middleware.js` — si una cambia, la otra
/// también debe cambiar.
void main() {
  group('Correos institucionales aceptados', () {
    const validos = [
      '23460706@colima.tecnm.mx', // campus original
      'l21450123@leon.tecnm.mx', // otro campus
      'alguien@tecnm.mx', // dominio raíz, sin campus
      'nombre.apellido@cd-victoria.tecnm.mx', // subdominio con guion
      'MAYUSCULAS@COLIMA.TECNM.MX', // no debe importar el case
    ];

    for (final email in validos) {
      test('acepta $email', () {
        expect(AuthService.isInstitutionalEmail(email), isTrue);
      });
    }
  });

  group('Correos rechazados', () {
    const invalidos = [
      'alguien@gmail.com', // correo personal
      'alguien@hotmail.com',
      '', // vacío
      'sinarroba.tecnm.mx', // sin @
      'alguien@tecnm.mx.attacker.com', // sufijo suplantado
      'alguien@evil-tecnm.mx.attacker.com',
      'alguien@atacantetecnm.mx', // pegado, sin punto separador
      'alguien@tecnm.com', // TLD equivocado
      'alguien@notecnm.mx',
      'con espacio@tecnm.mx', // espacio en la parte local
    ];

    for (final email in invalidos) {
      test('rechaza "$email"', () {
        expect(AuthService.isInstitutionalEmail(email), isFalse);
      });
    }
  });
}
