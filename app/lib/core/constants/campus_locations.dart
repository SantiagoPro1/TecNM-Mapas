/// Constantes de ubicaciones del campus TecNM Colima.
///
/// Centraliza los IDs de nodos del campus para evitar strings mágicos
/// dispersos por el código. Coinciden 1:1 con los IDs en tec_colima_map.json.
class CampusLocations {
  CampusLocations._();

  // ─── Coordenadas del centro del campus ────────────────────────────────────
  static const double centerLat = 19.2628;
  static const double centerLng = -103.7233;

  // ─── Entrada y áreas especiales ───────────────────────────────────────────
  static const String entradaPrincipal = 'tec_entrada';
  static const String estacionamientoPrincipal = 'tec_estacionamiento';
  static const String explanadaPrincipal = 'tec_explanada';
  static const String canchas = 'tec_canchas';

  // ─── Edificios y Laboratorios ─────────────────────────────────────────────
  static const String edificioA = 'tec_edificio_a'; // Administrativo / Dirección
  static const String edificioB = 'tec_edificio_b'; // Centro de Información / Biblioteca
  static const String edificioP = 'tec_edificio_p'; // Académico
  static const String sistemas = 'tec_sistemas'; // Sistemas y Computación
  static const String mecatronica = 'tec_mecatronica'; // Laboratorio de Mecatrónica
  static const String arquitectura = 'tec_arquitectura'; // Laboratorio de Arquitectura
  static const String industrial = 'tec_industrial'; // Ingeniería Industrial
  static const String posgrado = 'tec_posgrado'; // División de Posgrado
  static const String cecum = 'tec_cecum'; // Centro Cultural y de Usos Múltiples
  static const String cafeteria = 'tec_cafeteria'; // Cafetería Norte

  // ─── Destinos principales (voz + QR) ──────────────────────────────────────
  static const List<String> mainDestinations = [
    entradaPrincipal,
    estacionamientoPrincipal,
    explanadaPrincipal,
    canchas,
    edificioA,
    edificioB,
    edificioP,
    sistemas,
    mecatronica,
    arquitectura,
    industrial,
    posgrado,
    cecum,
    cafeteria,
  ];

  /// Genera el contenido QR para un nodo del campus.
  static String qrCodeForNode(String nodeId) => 'SINAIT:$nodeId';

  /// Extrae el nodeId de un string QR escaneado.
  /// Retorna null si el formato no es válido.
  static String? parseQrCode(String qrData) {
    if (qrData.startsWith('SINAIT:')) {
      return qrData.substring(7);
    }
    return null;
  }
}
