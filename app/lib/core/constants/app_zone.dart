/// Zonas geográficas reconocidas por el sistema de geofencing.
///
/// Cada valor representa una zona física con un perímetro definido
/// en [CampusLocations]. El sistema de [ZoneNotifier] actualiza la
/// zona activa según la posición GPS del usuario.
enum AppZone {
  /// Campus del TecNM Colima.
  escolar,

  /// Plaza Sendera.
  sendera,

  /// Plaza Zentralia.
  zentralia,

  /// Fuera de cualquier zona registrada.
  desconocido;

  /// Etiqueta legible para UI / logs.
  String get label {
    switch (this) {
      case AppZone.escolar:
        return 'TecNM Colima';
      case AppZone.sendera:
        return 'Plaza Sendera';
      case AppZone.zentralia:
        return 'Plaza Zentralia';
      case AppZone.desconocido:
        return 'Fuera de zona';
    }
  }
}
