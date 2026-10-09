import 'package:flutter_test/flutter_test.dart';
import 'package:navia/data/repositories/admin_repository.dart';

void main() {
  test('Authorizes the requested institutional administrators precisely', () {
    for (final email in [
      'alira@colima.tecnm.mx',
      'hcastrejon@colima.tecnm.mx',
      'jorge.chavez@colima.tecnm.mx',
      '23460706@colima.tecnm.mx',
    ]) {
      expect(AdminRepository.isAuthorizedAdminEmail(email), isTrue);
      expect(AdminRepository.isAuthorizedAdminEmail(' ${email.toUpperCase()} '),
          isTrue);
    }
    expect(AdminRepository.isAuthorizedAdminEmail(null), isFalse);
    expect(AdminRepository.isAuthorizedAdminEmail('otro@colima.tecnm.mx'),
        isFalse);
    expect(AdminRepository.isAuthorizedAdminEmail('alira@otro.mx'), isFalse);
    expect(
        AdminRepository.isAuthorizedAdminEmail('extra_alira@colima.tecnm.mx'),
        isFalse);
  });
}
