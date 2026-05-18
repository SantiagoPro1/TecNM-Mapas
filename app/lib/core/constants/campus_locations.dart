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
  static const String estacionamientoPrincipal = 'estacionamiento_principal';
  static const String explanadaPrincipal = 'patio_civico';
  static const String canchas = 'campo_futbol';

  // ─── Edificios y Laboratorios ─────────────────────────────────────────────
  static const String edificioA = 'edificio_a'; // Administrativo / Dirección
  static const String edificioB =
      'edificio_b'; // Centro de Información / Biblioteca
  static const String edificioP = 'edificio_p'; // Académico
  static const String sistemas = 'edificio_r'; // Sistemas y Computación
  static const String mecatronica = 'edificio_y'; // Laboratorio de Mecatrónica
  static const String arquitectura =
      'edificio_u'; // Laboratorio de Arquitectura
  static const String industrial = 'edificio_w'; // Ingeniería Industrial
  static const String posgrado = 'edificio_v'; // División de Posgrado
  static const String cecum = 'cecum'; // Centro Cultural y de Usos Múltiples
  static const String cafeteria = 'edificio_c'; // Cafetería Norte

  // ─── Plaza Sendera ───────────────────────────────────────────────────────
  static const String senderaEntrada = 'sendera_entrada_sur';
  static const String senderaCinemex = 'cinemex_sendera';
  static const String senderaWoolworth = 'woolworth_sendera';
  static const String senderaBanos = 'banos_sendera';

  // ─── Plaza Zentralia ─────────────────────────────────────────────────────
  static const String zentraliaEntrada = 'zentralia_entrada_sur';
  static const String zentraliaLiverpool = 'liverpool_zentralia';
  static const String zentraliaCinepolis = 'cinepolis_zentralia';
  static const String zentraliaBanos = 'banos_zentralia';

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
  static String qrCodeForNode(String nodeId) => 'NAVIA:$nodeId';

  /// Extrae el nodeId de un string QR escaneado.
  /// Retorna null si el formato no es válido.
  static String? parseQrCode(String qrData) {
    if (qrData.startsWith('NAVIA:')) {
      return qrData.substring(7);
    }
    return null;
  }

  // ─── Perímetros de Geofencing ───────────────────────────────────────────────
  // Cada zona se define con coordenadas centrales (lat, lng) y un radio
  // de alcance en metros. Estos valores alimentan al ZoneNotifier para
  // determinar en qué zona se encuentra el usuario.

  /// TecNM Colima — centro del campus.
  static const double escolarLat = 19.2628;
  static const double escolarLng = -103.7233;
  static const double escolarRadius = 350.0; // metros

  /// Plaza Sendera — centro aproximado de la plaza.
  static const double senderaLat = 19.2457;
  static const double senderaLng = -103.7250;
  static const double senderaRadius = 250.0; // metros

  /// Plaza Zentralia — centro aproximado de la plaza.
  static const double zentraliaLat = 19.2530;
  static const double zentraliaLng = -103.7140;
  static const double zentraliaRadius = 300.0; // metros

  /// Lista tipada con todas las zonas para iteración en el ZoneNotifier.
  /// Cada entrada: (AppZone, lat, lng, radio).
  /// NOTA: Requiere import de [AppZone] desde app_zone.dart.
  static const List<(double lat, double lng, double radius)> zonePerimeters = [
    (escolarLat, escolarLng, escolarRadius), // index 0 → escolar
    (senderaLat, senderaLng, senderaRadius), // index 1 → sendera
    (zentraliaLat, zentraliaLng, zentraliaRadius), // index 2 → zentralia
  ];
}
