import 'package:flutter_test/flutter_test.dart';
import 'package:navia/data/providers/student_data_provider.dart';

void main() {
  group('NSS del IMSS', () {
    test('válido solo con exactamente 11 dígitos', () {
      expect(StudentData.isValidNss('12345678901'), isTrue);
      expect(StudentData.isValidNss('1234567890'), isFalse); // 10
      expect(StudentData.isValidNss('123456789012'), isFalse); // 12
      expect(StudentData.isValidNss(''), isFalse);
    });

    test('acepta separadores: la gente lo copia como viene en su documento',
        () {
      expect(StudentData.isValidNss('12 34 56 7890 1'), isTrue);
      expect(StudentData.isValidNss('12-34-56-7890-1'), isTrue);
    });

    test('lo formatea en bloques legibles', () {
      expect(StudentData.formatNss('12345678901'), '12 34 56 7890 1');
    });

    test('si no son 11 dígitos lo deja tal cual (no inventa formato)', () {
      expect(StudentData.formatNss('123'), '123');
    });
  });

  group('StudentData', () {
    test('las banderas clear sí borran (no el problema de `??`)', () {
      const d = StudentData(
        carrera: 'Ing. en Sistemas',
        nss: '12345678901',
        bloodType: 'O+',
        emergencyName: 'María',
        emergencyPhone: '3121234567',
        medicalNotes: 'Asma',
      );
      final limpio = d.copyWith(
        clearCarrera: true,
        clearNss: true,
        clearBloodType: true,
        clearEmergency: true,
        clearMedicalNotes: true,
      );
      expect(limpio.carrera, isNull);
      expect(limpio.nss, isNull);
      expect(limpio.bloodType, isNull);
      expect(limpio.emergencyName, isNull);
      expect(limpio.emergencyPhone, isNull);
      expect(limpio.medicalNotes, isNull);
    });

    test('el contacto de emergencia se arma con lo que haya', () {
      expect(
          const StudentData(emergencyName: 'María', emergencyPhone: '312')
              .emergencyLabel,
          'María · 312');
      expect(const StudentData(emergencyName: 'María').emergencyLabel, 'María');
      expect(const StudentData(emergencyPhone: '312').emergencyLabel, '312');
      expect(const StudentData().emergencyLabel, isNull);
    });
  });
}
