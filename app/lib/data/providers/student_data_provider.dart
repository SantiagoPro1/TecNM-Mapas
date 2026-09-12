import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navia/data/providers/auth_provider.dart';

/// Datos del estudiante que la app NO puede obtener por su cuenta y que,
/// por lo tanto, cada quien captura una sola vez desde su perfil:
///
///  - **Carrera** (programa educativo)
///  - **NSS** (Número de Seguridad Social del IMSS)
///
/// Ninguno de los dos se puede derivar del correo institucional ni de la
/// matrícula:
///
///  - Google Sign-In solo entrega nombre, correo y foto. No hay carrera.
///  - El formato de matrícula varía por campus del TecNM y no codifica la
///    carrera de forma documentada en ningún lado de este proyecto.
///  - El NSS son 11 dígitos que asigna el IMSS (subdelegación, año de
///    alta, año de nacimiento, consecutivo y dígito verificador). No tiene
///    ninguna relación con el correo ni con la matrícula.
///
/// Antes `credential_screen.dart` mostraba "ING. SISTEMAS COMPUTACIONALES"
/// escrito a mano para TODOS los estudiantes — bug real reportado por el
/// usuario. Inventar un mapeo habría sido cambiar un dato incorrecto por
/// otro igual de incorrecto.
///
/// Ambos se guardan SOLO en el dispositivo (SharedPreferences, como el
/// resto de los ajustes personales), con una llave por matrícula, para que
/// si el mismo teléfono llega a usarse con más de una cuenta institucional
/// los datos de una persona no se le queden pegados a otra. El NSS es dato
/// personal sensible: no se sube a Firestore ni viaja en el QR de la
/// credencial.
class StudentData {
  final String? carrera;
  final String? nss;

  /// Datos de emergencia. Sustituyen a los recuadros que antes decían
  /// "VIGENCIA 2024-2027", "ALUMNO REGULAR" y "SEGURO VIGENTE IMSS" fijos
  /// para todos: la app no puede verificar nada de eso, y una credencial
  /// que afirma cobertura médica sin respaldo es peor que una que no dice
  /// nada (alguien podría actuar confiando en ella). En un evento con
  /// miles de atletas, lo que de verdad sirve si alguien se lesiona en
  /// una cancha es esto.
  final String? bloodType;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? medicalNotes;

  const StudentData({
    this.carrera,
    this.nss,
    this.bloodType,
    this.emergencyName,
    this.emergencyPhone,
    this.medicalNotes,
  });

  static const bloodTypes = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

  StudentData copyWith({
    String? carrera,
    String? nss,
    String? bloodType,
    String? emergencyName,
    String? emergencyPhone,
    String? medicalNotes,
    bool clearCarrera = false,
    bool clearNss = false,
    bool clearBloodType = false,
    bool clearEmergency = false,
    bool clearMedicalNotes = false,
  }) {
    return StudentData(
      carrera: clearCarrera ? null : (carrera ?? this.carrera),
      nss: clearNss ? null : (nss ?? this.nss),
      bloodType: clearBloodType ? null : (bloodType ?? this.bloodType),
      emergencyName: clearEmergency ? null : (emergencyName ?? this.emergencyName),
      emergencyPhone:
          clearEmergency ? null : (emergencyPhone ?? this.emergencyPhone),
      medicalNotes:
          clearMedicalNotes ? null : (medicalNotes ?? this.medicalNotes),
    );
  }

  /// "Juan Pérez · 312 123 4567", o solo lo que haya.
  String? get emergencyLabel {
    final n = emergencyName?.trim();
    final p = emergencyPhone?.trim();
    if ((n == null || n.isEmpty) && (p == null || p.isEmpty)) return null;
    if (n == null || n.isEmpty) return p;
    if (p == null || p.isEmpty) return n;
    return '$n · $p';
  }

  /// Formatea el NSS en bloques para que sea legible en la credencial:
  /// 11 dígitos → "12 34 56 7890 1".
  static String formatNss(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return raw;
    return '${d.substring(0, 2)} ${d.substring(2, 4)} ${d.substring(4, 6)} '
        '${d.substring(6, 10)} ${d.substring(10)}';
  }

  /// Un NSS válido son exactamente 11 dígitos.
  static bool isValidNss(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '').length == 11;
}

class StudentDataNotifier extends StateNotifier<StudentData> {
  final Ref _ref;
  String? _loadedForMatricula;

  StudentDataNotifier(this._ref) : super(const StudentData()) {
    _ref.listen<String>(matriculaProvider, (previous, next) {
      if (next != _loadedForMatricula) _loadFromDisk(next);
    }, fireImmediately: true);
  }

  String _key(String field, String m) => '${field}_$m';

  Future<void> _loadFromDisk(String matricula) async {
    _loadedForMatricula = matricula;
    if (matricula.isEmpty) {
      state = const StudentData();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    // Si mientras tanto ya cambió de cuenta otra vez, no pisar el estado
    // con una lectura que ya quedó vieja.
    if (_loadedForMatricula != matricula) return;
    state = StudentData(
      carrera: prefs.getString(_key('carrera', matricula)),
      nss: prefs.getString(_key('nss', matricula)),
      bloodType: prefs.getString(_key('blood', matricula)),
      emergencyName: prefs.getString(_key('emg_name', matricula)),
      emergencyPhone: prefs.getString(_key('emg_phone', matricula)),
      medicalNotes: prefs.getString(_key('medical', matricula)),
    );
  }

  Future<void> _save(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> setCarrera(String value) async {
    final m = _loadedForMatricula;
    if (m == null || m.isEmpty) return;
    final trimmed = value.trim();
    state = trimmed.isEmpty
        ? state.copyWith(clearCarrera: true)
        : state.copyWith(carrera: trimmed);
    await _save(_key('carrera', m), trimmed);
  }

  /// Guarda el NSS quedándose solo con los dígitos (la gente lo escribe con
  /// espacios o guiones según cómo venga en su documento).
  Future<void> setNss(String value) async {
    final m = _loadedForMatricula;
    if (m == null || m.isEmpty) return;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    state = digits.isEmpty
        ? state.copyWith(clearNss: true)
        : state.copyWith(nss: digits);
    await _save(_key('nss', m), digits);
  }

  Future<void> setBloodType(String? value) async {
    final m = _loadedForMatricula;
    if (m == null || m.isEmpty) return;
    final v = (value ?? '').trim();
    state = v.isEmpty
        ? state.copyWith(clearBloodType: true)
        : state.copyWith(bloodType: v);
    await _save(_key('blood', m), v);
  }

  Future<void> setEmergencyContact(String name, String phone) async {
    final m = _loadedForMatricula;
    if (m == null || m.isEmpty) return;
    final n = name.trim();
    final p = phone.trim();
    state = (n.isEmpty && p.isEmpty)
        ? state.copyWith(clearEmergency: true)
        : state.copyWith(emergencyName: n, emergencyPhone: p);
    await _save(_key('emg_name', m), n);
    await _save(_key('emg_phone', m), p);
  }

  Future<void> setMedicalNotes(String value) async {
    final m = _loadedForMatricula;
    if (m == null || m.isEmpty) return;
    final v = value.trim();
    state = v.isEmpty
        ? state.copyWith(clearMedicalNotes: true)
        : state.copyWith(medicalNotes: v);
    await _save(_key('medical', m), v);
  }
}

final studentDataProvider =
    StateNotifierProvider<StudentDataNotifier, StudentData>((ref) {
  return StudentDataNotifier(ref);
});
