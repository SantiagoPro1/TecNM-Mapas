import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinait/data/models/announcement.dart';
import 'package:sinait/services/feed/feed_service.dart';
import 'package:sinait/data/providers/navigation_provider.dart';

// ─── Estado del Feed ──────────────────────────────────────────

class FeedState {
  final List<Announcement> announcements;
  final bool isLoading;
  final String? errorMessage;

  const FeedState({
    this.announcements = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  FeedState copyWith({
    List<Announcement>? announcements,
    bool? isLoading,
    String? errorMessage,
  }) {
    return FeedState(
      announcements: announcements ?? this.announcements,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

// ─── StateNotifier ────────────────────────────────────────────

class FeedNotifier extends StateNotifier<FeedState> {
  final FeedService _feedService;

  FeedNotifier(this._feedService) : super(const FeedState());

  /// Carga avisos para la zona actual del usuario.
  Future<void> loadForZone(String zoneNodeId) async {
    state = state.copyWith(isLoading: true);

    try {
      final announcements =
          await _feedService.getAnnouncementsForZone(zoneNodeId);
      state = FeedState(announcements: announcements);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error cargando avisos: $e',
      );
    }
  }

  /// Carga todos los avisos activos (sin filtrar por zona).
  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true);

    try {
      final announcements = await _feedService.getAllActive();
      state = FeedState(announcements: announcements);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error cargando avisos: $e',
      );
    }
  }

  /// Descarta un aviso del feed local.
  void dismiss(String announcementId) {
    state = state.copyWith(
      announcements: state.announcements
          .where((a) => a.id != announcementId)
          .toList(),
    );
  }
}

// ─── Providers ────────────────────────────────────────────────

/// Provider del servicio de feed.
final feedServiceProvider = Provider<FeedService>((ref) {
  return FeedService();
});

/// Provider principal del feed.
final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  final feedService = ref.watch(feedServiceProvider);
  return FeedNotifier(feedService);
});

/// Provider que auto-actualiza el feed cuando cambia la zona.
/// Escucha los cambios en navigationProvider y recarga los avisos.
final autoFeedProvider = Provider<void>((ref) {
  final navState = ref.watch(navigationProvider);
  final feedNotifier = ref.watch(feedProvider.notifier);

  if (navState.currentNode != null) {
    feedNotifier.loadForZone(navState.currentNode!.id);
  }
});
