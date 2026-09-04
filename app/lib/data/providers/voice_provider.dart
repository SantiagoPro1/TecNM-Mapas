import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/services/voice/voice_service.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';

// ─── Estado de voz ────────────────────────────────────────────

class VoiceControlState {
  final VoiceState voiceState;
  final String? lastSpokenText;
  final bool isInitialized;

  const VoiceControlState({
    this.voiceState = VoiceState.idle,
    this.lastSpokenText,
    this.isInitialized = false,
  });

  VoiceControlState copyWith({
    VoiceState? voiceState,
    String? lastSpokenText,
    bool? isInitialized,
  }) {
    return VoiceControlState(
      voiceState: voiceState ?? this.voiceState,
      lastSpokenText: lastSpokenText ?? this.lastSpokenText,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// ─── StateNotifier ────────────────────────────────────────────

/// Salida de voz de la app (TTS). El motor de comandos hablados se retiró:
/// no quedaba ninguna entrada en la interfaz que lo disparara, y para el
/// Evento Nacional Deportivo la navegación es visual.
class VoiceNotifier extends StateNotifier<VoiceControlState> {
  final VoiceService _voiceService;
  final NavigationNotifier _navNotifier;
  final Ref _ref;

  VoiceNotifier(this._voiceService, this._navNotifier, this._ref)
      : super(const VoiceControlState());

  /// Inicializa el servicio de voz.
  Future<void> initialize() async {
    await _voiceService.initialize();

    // Sincronizar velocidad de voz desde los ajustes configurados
    final rate = _ref.read(settingsProvider).speechRate;
    await _voiceService.setSpeechRate(rate);

    _voiceService.onStateChanged = (newState) {
      if (mounted) {
        state = state.copyWith(voiceState: newState);
      }
    };

    state = state.copyWith(isInitialized: true);
  }

  /// Habla el texto y lo guarda como última instrucción.
  Future<void> _speak(String text) async {
    state = state.copyWith(lastSpokenText: text);
    await _voiceService.speak(text);
  }

  /// Habla texto sin guardarlo como última instrucción.
  Future<void> speakAnnouncement(String text) async {
    await _voiceService.speak(text);
  }

  /// Dice la instrucción actual del paso de navegación.
  Future<void> speakCurrentStep() async {
    final instruction = _navNotifier.state.currentInstruction;
    if (instruction != null) {
      await _speak(instruction);
    }
  }

  /// Avanza y anuncia el siguiente paso.
  Future<void> nextStepAndSpeak() async {
    _navNotifier.nextStep();
    await speakCurrentStep();
  }

  /// Detiene la voz.
  Future<void> stopAll() async {
    await _voiceService.stopSpeaking();
    state = state.copyWith(voiceState: VoiceState.idle);
  }

  /// Actualiza velocidad de voz.
  Future<void> setSpeechRate(double rate) async {
    await _voiceService.setSpeechRate(rate);
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}

// ─── Providers ────────────────────────────────────────────────

/// Provider del servicio de voz (singleton).
final voiceServiceProvider = Provider<VoiceService>((ref) {
  return VoiceService();
});

/// Provider principal de voz.
final voiceProvider =
    StateNotifierProvider<VoiceNotifier, VoiceControlState>((ref) {
  final voiceService = ref.watch(voiceServiceProvider);
  final navNotifier = ref.watch(navigationProvider.notifier);
  return VoiceNotifier(voiceService, navNotifier, ref);
});
