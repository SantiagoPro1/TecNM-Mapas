import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/services/voice/voice_service.dart';
import 'package:navia/services/voice/intent_parser.dart';
import 'package:navia/data/providers/navigation_provider.dart';

// ─── Estado de voz ────────────────────────────────────────────

class VoiceControlState {
  final VoiceState voiceState;
  final String recognizedText;
  final ParsedIntent? lastIntent;
  final String? lastSpokenText;
  final bool isInitialized;

  const VoiceControlState({
    this.voiceState = VoiceState.idle,
    this.recognizedText = '',
    this.lastIntent,
    this.lastSpokenText,
    this.isInitialized = false,
  });

  VoiceControlState copyWith({
    VoiceState? voiceState,
    String? recognizedText,
    ParsedIntent? lastIntent,
    String? lastSpokenText,
    bool? isInitialized,
  }) {
    return VoiceControlState(
      voiceState: voiceState ?? this.voiceState,
      recognizedText: recognizedText ?? this.recognizedText,
      lastIntent: lastIntent ?? this.lastIntent,
      lastSpokenText: lastSpokenText ?? this.lastSpokenText,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// ─── StateNotifier ────────────────────────────────────────────

class VoiceNotifier extends StateNotifier<VoiceControlState> {
  final VoiceService _voiceService;
  final NavigationNotifier _navNotifier;

  VoiceNotifier(this._voiceService, this._navNotifier)
      : super(const VoiceControlState());

  /// Inicializa el servicio de voz.
  Future<void> initialize() async {
    await _voiceService.initialize();

    _voiceService.onStateChanged = (newState) {
      if (mounted) {
        state = state.copyWith(voiceState: newState);
      }
    };

    state = state.copyWith(isInitialized: true);
  }

  /// Flujo completo: escuchar → parsear → ejecutar.
  Future<void> listenAndExecute() async {
    state = state.copyWith(
      voiceState: VoiceState.listening,
      recognizedText: '',
    );

    await _voiceService.startListening(
      onResult: (text, isFinal) {
        state = state.copyWith(recognizedText: text);

        if (isFinal && text.isNotEmpty) {
          _processCommand(text);
        }
      },
    );
  }

  /// Procesa un comando de texto (de voz o teclado).
  Future<void> _processCommand(String text) async {
    final intent = IntentParser.parse(text);
    state = state.copyWith(
      voiceState: VoiceState.processing,
      lastIntent: intent,
    );

    switch (intent.type) {
      case IntentType.navigate:
        if (intent.destination != null) {
          _navNotifier.navigateTo(intent.destination!);
          final navState = _navNotifier.state;
          if (navState.activeRoute != null) {
            await _speak(navState.activeRoute!.voiceSummary);
            // Decir la primera instrucción
            final firstInstruction =
                navState.activeRoute!.steps.first.voiceInstruction;
            await Future.delayed(const Duration(milliseconds: 500));
            await _speak(firstInstruction);
          } else {
            await _speak(
              'No encontré una ruta hacia ${intent.destination}. '
              'Intenta con otro destino.',
            );
          }
        }
        break;

      case IntentType.whereIs:
        if (intent.destination != null) {
          final node = _navNotifier.findDestination(intent.destination!);
          if (node != null) {
            await _speak(
                '${node.name} se encuentra en el campus. ${node.description}.');
          } else {
            await _speak('No encontré ${intent.destination} en el campus.');
          }
        }
        break;

      case IntentType.whereAmI:
        final current = _navNotifier.state.currentNode;
        if (current != null) {
          await _speak(
              'Te encuentras en ${current.name}. ${current.description}.');
        } else {
          await _speak(
            'No tengo tu ubicación actual. '
            'Escanea un código QR del campus para posicionarte.',
          );
        }
        break;

      case IntentType.repeat:
        if (state.lastSpokenText != null) {
          await _speak(state.lastSpokenText!);
        } else {
          await _speak('No hay instrucciones previas para repetir.');
        }
        break;

      case IntentType.stop:
        _navNotifier.cancelNavigation();
        await _speak('Navegación cancelada.');
        break;

      case IntentType.help:
        await _speak(IntentParser.helpText);
        break;

      case IntentType.nearby:
        final nearby = _navNotifier.getNearbyDestinations(limit: 3);
        if (nearby.isNotEmpty) {
          final names = nearby
              .map((r) =>
                  '${r.destination.name}, a ${r.totalDistance.round()} metros')
              .join('. ');
          await _speak('Destinos cercanos: $names.');
        } else {
          await _speak('No tengo tu ubicación para buscar destinos cercanos.');
        }
        break;

      case IntentType.unknown:
        await _speak(
          'No entendí tu comando. '
          'Puedes decir "llévame a" seguido del destino, o "ayuda" para más opciones.',
        );
        break;
    }
  }

  /// Procesar comando de texto (para uso desde teclado/UI).
  Future<void> processTextCommand(String text) async {
    await _processCommand(text);
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

  /// Detiene todo (TTS + STT).
  Future<void> stopAll() async {
    await _voiceService.stopSpeaking();
    await _voiceService.stopListening();
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
  return VoiceNotifier(voiceService, navNotifier);
});
