import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/data/models/venue.dart';

/// Todas las sedes registradas (TecNM Colima + sedes del Evento Nacional
/// Deportivo).
final venueRegistryProvider = Provider<List<Venue>>((ref) => VenueRegistry.all);

/// Busca una sede por id. Cae de vuelta a TecNM Colima si el id no existe.
final venueByIdProvider = Provider.family<Venue, String>(
  (ref, id) => VenueRegistry.byId(id),
);
