import 'package:flutter_tts/flutter_tts.dart';

/// Estados posibles del servicio de voz.
enum VoiceState {
  idle, // Sin actividad
  speaking, // Hablando al usuario (TTS activo)
  error, // Error
}

/// Servicio de voz (Text-to-Speech en español mexicano).
///
/// Solo salida de voz: la parte de reconocimiento (STT) se retiró junto con
/// los comandos hablados, que ya no tenían ninguna entrada en la interfaz
/// para el Evento Nacional Deportivo. Lo que queda se usa para leer en voz
/// alta la indicación del paso actual cuando el usuario toca "Repetir".
class VoiceService {
  final FlutterTts _tts = FlutterTts();

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  bool _ttsInitialized = false;

  String? _lastError;
  String? get lastError => _lastError;

  /// Velocidad de voz (0.5 = lento, 1.0 = normal, 2.0 = rápido)
  double _speechRate = 0.8;
  double get speechRate => _speechRate;

  /// Callback cuando cambia el estado.
  void Function(VoiceState state)? onStateChanged;

  /// Inicializa el TTS. Llamar una vez al inicio de la app.
  Future<void> initialize() async {
    await _initTts();
  }

  Future<void> _initTts() async {
    // Configurar para español mexicano
    await _tts.setLanguage('es-MX');
    await _tts.setSpeechRate(_speechRate);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Callbacks de estado
    _tts.setStartHandler(() {
      _setState(VoiceState.speaking);
    });

    _tts.setCompletionHandler(() {
      _setState(VoiceState.idle);
    });

    _tts.setErrorHandler((msg) {
      _lastError = 'TTS Error: $msg';
      _setState(VoiceState.error);
    });

    _ttsInitialized = true;
  }

  /// Habla el texto proporcionado usando TTS en español mexicano.
  ///
  /// Si ya está hablando, detiene el mensaje anterior.
  Future<void> speak(String text) async {
    if (!_ttsInitialized) await _initTts();

    // Detener si ya está hablando
    await _tts.stop();

    _setState(VoiceState.speaking);
    await _tts.speak(text);
  }

  /// Detiene el TTS inmediatamente.
  Future<void> stopSpeaking() async {
    await _tts.stop();
    _setState(VoiceState.idle);
  }

  /// Actualiza la velocidad de voz.
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.3, 2.0);
    await _tts.setSpeechRate(_speechRate);
  }

  /// ¿Está el servicio hablando?
  bool get isSpeaking => _state == VoiceState.speaking;

  /// Libera recursos.
  Future<void> dispose() async {
    await _tts.stop();
  }

  void _setState(VoiceState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }
}
