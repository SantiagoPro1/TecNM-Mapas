import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Estados posibles del servicio de voz.
enum VoiceState {
  idle, // Sin actividad
  listening, // Escuchando al usuario (STT activo)
  processing, // Procesando el comando
  speaking, // Hablando al usuario (TTS activo)
  error, // Error
}

/// Servicio de voz que envuelve flutter_tts (Text-to-Speech)
/// y speech_to_text (Speech-to-Text) para la interfaz de voz
/// en español mexicano.
class VoiceService {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  bool _ttsInitialized = false;
  bool _sttAvailable = false;

  String _lastRecognized = '';
  String get lastRecognized => _lastRecognized;

  String? _lastError;
  String? get lastError => _lastError;

  /// Velocidad de voz (0.5 = lento, 1.0 = normal, 2.0 = rápido)
  double _speechRate = 0.85;
  double get speechRate => _speechRate;

  /// Callback cuando cambia el estado.
  void Function(VoiceState state)? onStateChanged;

  /// Callback cuando se reconoce texto parcial o final.
  void Function(String text, bool isFinal)? onRecognized;

  /// Inicializa TTS y STT. Llamar una vez al inicio de la app.
  Future<void> initialize() async {
    await _initTts();
    await _initStt();
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

  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize(
      onError: (error) {
        _lastError = 'STT Error: ${error.errorMsg}';
        _setState(VoiceState.error);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (_state == VoiceState.listening) {
            _setState(VoiceState.idle);
          }
        }
      },
    );
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

  /// Habla una lista de instrucciones en secuencia.
  Future<void> speakSequence(
    List<String> instructions, {
    Duration pauseBetween = const Duration(milliseconds: 800),
  }) async {
    for (final instruction in instructions) {
      await speak(instruction);
      // Esperar a que termine de hablar + pausa
      await Future.delayed(pauseBetween);
    }
  }

  /// Detiene el TTS inmediatamente.
  Future<void> stopSpeaking() async {
    await _tts.stop();
    _setState(VoiceState.idle);
  }

  /// Comienza a escuchar comandos de voz del usuario.
  ///
  /// [onResult] se llama cuando se reconoce texto (parcial o final).
  /// [timeout] es la duración máxima de escucha.
  Future<void> startListening({
    void Function(String text, bool isFinal)? onResult,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!_sttAvailable) {
      _lastError = 'Reconocimiento de voz no disponible';
      _setState(VoiceState.error);
      return;
    }

    // Detener TTS si está hablando
    await _tts.stop();

    _lastRecognized = '';
    _setState(VoiceState.listening);

    await _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        _lastRecognized = result.recognizedWords;

        onResult?.call(result.recognizedWords, result.finalResult);
        onRecognized?.call(result.recognizedWords, result.finalResult);

        if (result.finalResult) {
          _setState(VoiceState.processing);
        }
      },
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      localeId: 'es_MX',
      listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation),
    );
  }

  /// Detiene la escucha de voz.
  Future<void> stopListening() async {
    await _stt.stop();
    _setState(VoiceState.idle);
  }

  /// Actualiza la velocidad de voz.
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.3, 2.0);
    await _tts.setSpeechRate(_speechRate);
  }

  /// ¿Está el servicio escuchando?
  bool get isListening => _state == VoiceState.listening;

  /// ¿Está el servicio hablando?
  bool get isSpeaking => _state == VoiceState.speaking;

  /// ¿Está disponible el STT?
  bool get isSttAvailable => _sttAvailable;

  /// Libera recursos.
  Future<void> dispose() async {
    await _tts.stop();
    await _stt.stop();
  }

  void _setState(VoiceState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }
}
