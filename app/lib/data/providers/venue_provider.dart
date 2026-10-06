import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/venue.dart';

/// Notificador que mantiene la lista de sedes actualizada.
/// Empieza de inmediato con [VenueRegistry.all] (offline-first, 0 ms)
/// y escucha la colección 'venues' en Firestore para reflejar cambios remotos en vivo.
class VenueListNotifier extends StateNotifier<List<Venue>> {
  VenueListNotifier() : super(VenueRegistry.all) {
    _escucharFirestore();
  }

  void _escucharFirestore() {
    try {
      FirebaseFirestore.instance
          .collection('venues')
          .snapshots()
          .listen((snap) {
            if (snap.docs.isEmpty) return;
            final mapa = {for (final v in VenueRegistry.all) v.id: v};
            bool huboCambios = false;

            for (final doc in snap.docs) {
              final data = doc.data();
              final id = doc.id;
              final label = (data['label'] as String?) ?? (data['name'] as String?);
              final lat = (data['centerLat'] as num?)?.toDouble() ??
                  (data['latitude'] as num?)?.toDouble();
              final lng = (data['centerLng'] as num?)?.toDouble() ??
                  (data['longitude'] as num?)?.toDouble();

              if (label != null && lat != null && lng != null) {
                final previa = mapa[id] ?? VenueRegistry.byId(id);
                mapa[id] = Venue(
                  id: id,
                  label: label,
                  shortDescription: (data['shortDescription'] as String?) ??
                      previa.shortDescription,
                  centerLat: lat,
                  centerLng: lng,
                  boundsSouthLat:
                      (data['boundsSouthLat'] as num?)?.toDouble() ??
                          previa.boundsSouthLat,
                  boundsWestLng:
                      (data['boundsWestLng'] as num?)?.toDouble() ??
                          previa.boundsWestLng,
                  boundsNorthLat:
                      (data['boundsNorthLat'] as num?)?.toDouble() ??
                          previa.boundsNorthLat,
                  boundsEastLng:
                      (data['boundsEastLng'] as num?)?.toDouble() ??
                          previa.boundsEastLng,
                  defaultZoom:
                      (data['defaultZoom'] as num?)?.toDouble() ??
                          previa.defaultZoom,
                  icon: previa.icon,
                );
                huboCambios = true;
              }
            }

            if (huboCambios) {
              state = mapa.values.toList();
            }
          }, onError: (_) {});
    } catch (_) {}
  }
}

/// Todas las sedes registradas (TecNM Colima + sedes del Evento Nacional Deportivo),
/// con sincronización en vivo desde Firestore.
final venueRegistryProvider =
    StateNotifierProvider<VenueListNotifier, List<Venue>>(
  (ref) => VenueListNotifier(),
);

/// Busca una sede por id. Cae de vuelta a TecNM Colima si el id no existe.
final venueByIdProvider = Provider.family<Venue, String>(
  (ref, id) {
    final venues = ref.watch(venueRegistryProvider);
    return venues.firstWhere(
      (v) => v.id == id,
      orElse: () => VenueRegistry.byId(id),
    );
  },
);
