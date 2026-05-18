import 'package:equatable/equatable.dart';

/// Tipos de aviso contextual.
enum AnnouncementType {
  info, // Información general
  warning, // Advertencia (piso mojado, obra, etc.)
  event, // Evento o actividad
  closure, // Cierre de área
  service, // Servicio disponible
}

/// Modelo de aviso contextual geoposicionado.
///
/// Los avisos se muestran según la zona del campus donde
/// se encuentre el usuario (determinada por escaneo QR).
class Announcement extends Equatable {
  final String id;
  final String title;
  final String body;
  final AnnouncementType type;

  /// IDs de los nodos del campus donde aplica este aviso.
  final List<String> zoneNodeIds;

  /// ¿Está activo? (para activar/desactivar sin borrar).
  final bool active;

  /// Fecha de creación.
  final DateTime createdAt;

  /// Fecha de expiración (null = sin expiración).
  final DateTime? expiresAt;

  /// Prioridad (mayor = más importante, rango 0-10).
  final int priority;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.zoneNodeIds,
    this.active = true,
    required this.createdAt,
    this.expiresAt,
    this.priority = 5,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: AnnouncementType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AnnouncementType.info,
      ),
      zoneNodeIds: (json['zoneNodeIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      priority: json['priority'] as int? ?? 5,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'type': type.name,
        'zoneNodeIds': zoneNodeIds,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'priority': priority,
      };

  /// ¿Es relevante para un nodo específico?
  bool isRelevantFor(String nodeId) => zoneNodeIds.contains(nodeId);

  /// ¿Ha expirado?
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// ¿Debe mostrarse?
  bool get shouldShow => active && !isExpired;

  /// Ícono según el tipo.
  String get typeLabel {
    switch (type) {
      case AnnouncementType.info:
        return 'Información';
      case AnnouncementType.warning:
        return 'Advertencia';
      case AnnouncementType.event:
        return 'Evento';
      case AnnouncementType.closure:
        return 'Cierre';
      case AnnouncementType.service:
        return 'Servicio';
    }
  }

  @override
  List<Object?> get props => [id];
}
