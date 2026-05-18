import 'package:equatable/equatable.dart';

/// Tipos de nodo en el grafo del campus.
enum NodeType { building, corridor, entrance, service, area }

/// Representa un punto (edificio, intersección, entrada o servicio)
/// dentro del grafo de navegación del TecNM Colima.
class CampusNode extends Equatable {
  final String id;
  final String name;
  final List<String> aliases;
  final NodeType type;
  final double lat;
  final double lng;
  final int floor;
  final bool accessible;
  final String description;

  const CampusNode({
    required this.id,
    required this.name,
    required this.aliases,
    required this.type,
    required this.lat,
    required this.lng,
    required this.floor,
    required this.accessible,
    required this.description,
  });

  /// Deserializa un nodo desde el JSON del mapa.
  factory CampusNode.fromJson(Map<String, dynamic> json) {
    return CampusNode(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      aliases: (json['aliases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      type: _parseNodeType((json['type'] as String?) ?? 'corridor'),
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      floor: (json['floor'] as int?) ?? 0,
      accessible: (json['accessible'] as bool?) ?? true,
      description: (json['description'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aliases': aliases,
        'type': type.name,
        'lat': lat,
        'lng': lng,
        'floor': floor,
        'accessible': accessible,
        'description': description,
      };

  /// Verifica si el texto del usuario coincide con este nodo
  /// (por nombre exacto, id, o cualquiera de sus aliases).
  bool matchesQuery(String query) {
    final q = query.toLowerCase().trim();
    if (id.toLowerCase() == q) return true;
    if (name.toLowerCase().contains(q)) return true;
    for (final alias in aliases) {
      if (alias.toLowerCase().contains(q) || q.contains(alias.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// Es un destino que el usuario puede pedir por voz
  /// (excluye corredores/intersecciones internas).
  bool get isDestination =>
      type == NodeType.building ||
      type == NodeType.service ||
      type == NodeType.entrance;

  static NodeType _parseNodeType(String raw) {
    switch (raw) {
      case 'building':
        return NodeType.building;
      case 'corridor':
        return NodeType.corridor;
      case 'entrance':
        return NodeType.entrance;
      case 'service':
        return NodeType.service;
      case 'area':
        return NodeType.area;
      default:
        return NodeType.corridor;
    }
  }

  @override
  List<Object?> get props => [id];

  @override
  String toString() => 'CampusNode($id: $name)';
}
