/// Constantes de ubicaciones del campus TecNM Colima.
///
/// Centraliza los IDs de nodos del campus para evitar strings mágicos
/// dispersos por el código. Coinciden 1:1 con los IDs en tec_colima_map.json.
class CampusLocations {
  CampusLocations._();

  // ─── Coordenadas del centro del campus ────────────────────────────────────
  static const double centerLat = 19.2619;
  static const double centerLng = -103.7237;

  // ─── Entrada y áreas especiales ───────────────────────────────────────────
  static const String entradaPrincipal = 'entrada_principal';
  static const String estacionamientoPrincipal = 'estacionamiento_principal';
  static const String estacionamientoNorte = 'estacionamiento_norte';
  static const String patioCivico = 'patio_civico';
  static const String plazaCultural = 'plaza_cultural';

  // ─── Edificios A–Z ────────────────────────────────────────────────────────
  static const String edificioA = 'edificio_a'; // Administrativo / Dirección
  static const String edificioB = 'edificio_b'; // Centro de Información
  static const String edificioC = 'edificio_c'; // Cafetería Norte
  static const String edificioC1 = 'edificio_c1'; // Cafetería Sur
  static const String edificioD = 'edificio_d'; // Aulas
  static const String edificioE = 'edificio_e'; // Aulas y Lab de Microbiología
  static const String edificioF = 'edificio_f'; // Ciencias Básicas
  static const String edificioG = 'edificio_g'; // Aulas y Lab de Química
  static const String edificioH = 'edificio_h'; // Centro de Cómputo
  static const String edificioI = 'edificio_i'; // Aulas de Arquitectura
  static const String edificioJ = 'edificio_j'; // Lab de Bioquímica
  static const String edificioK = 'edificio_k'; // Aulas
  static const String edificioL = 'edificio_l'; // Lab de Química Orgánica
  static const String edificioM = 'edificio_m'; // Lab de Operaciones Unitarias
  static const String edificioN = 'edificio_n'; // Ciencias de la Tierra
  static const String edificioNTilde = 'edificio_n_tilde'; // Actividades Extraescolares
  static const String edificioO = 'edificio_o'; // Cubículos Docentes
  static const String edificioP = 'edificio_p'; // Taller de Manufactura
  static const String edificioQ = 'edificio_q'; // Recursos Materiales y Mantenimiento
  static const String edificioR = 'edificio_r'; // Sistemas y Computación
  static const String edificioS = 'edificio_s'; // Salón de la Paz
  static const String edificioT = 'edificio_t'; // Ciencias Económico Administrativas
  static const String edificioU = 'edificio_u'; // Laboratorio de Arquitectura
  static const String edificioV = 'edificio_v'; // División de Posgrado e Investigación
  static const String edificioW = 'edificio_w'; // Ingeniería Industrial
  static const String edificioX = 'edificio_x'; // Laboratorio de Ambiental
  static const String edificioY = 'edificio_y'; // Laboratorio de Mecatrónica
  static const String edificioZ = 'edificio_z'; // Banco de Reactivos
  static const String cecum = 'cecum';          // Centro Cultural y de Usos Múltiples

  // ─── Destinos principales (voz + QR) ──────────────────────────────────────
  static const List<String> mainDestinations = [
    entradaPrincipal,
    edificioA,
    edificioB,
    edificioC,
    edificioC1,
    edificioD,
    edificioE,
    edificioF,
    edificioG,
    edificioH,
    edificioI,
    edificioJ,
    edificioK,
    edificioL,
    edificioM,
    edificioN,
    edificioNTilde,
    edificioO,
    edificioP,
    edificioQ,
    edificioR,
    edificioS,
    edificioT,
    edificioU,
    edificioV,
    edificioW,
    edificioX,
    edificioY,
    edificioZ,
    cecum,
    patioCivico,
    plazaCultural,
    estacionamientoPrincipal,
    estacionamientoNorte,
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
