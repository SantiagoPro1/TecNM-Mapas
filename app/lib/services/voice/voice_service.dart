import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Estados posibles del servicio de voz.
enum VoiceState {
  idle, // Sin actividad
  speaking, // Hablando al usuario (TTS activo)
  error, // Error
}

/// Servicio de voz optimizado (Text-to-Speech en español mexicano).
///
/// Implementado de forma no bloqueante, con inicialización perezosa (lazy)
/// y timeouts estrictos para evitar que Android/MIUI congele el hilo principal (ANR).
class VoiceService {
  final FlutterTts _tts = FlutterTts();

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  bool _ttsInitialized = false;
  bool _isInitializing = false;

  String? _lastError;
  String? get lastError => _lastError;

  /// Velocidad de voz (0.5 = lento, 1.0 = normal, 2.0 = rápido)
  double _speechRate = 0.8;
  double get speechRate => _speechRate;

  /// Callback cuando cambia el estado.
  void Function(VoiceState state)? onStateChanged;

  /// Timeout máximo para llamadas IPC al motor TTS de Android (evita ANR).
  static const Duration _ttsTimeout = Duration(milliseconds: 1500);

  /// Inicialización perezosa con timeout estricto.
  Future<bool> _initTts() async {
    if (_ttsInitialized) return true;
    if (_isInitializing) return false;
    _isInitializing = true;

    try {
      await Future.any([
        Future(() async {
          await _tts.setLanguage('es-MX');
          await _tts.setSpeechRate(_speechRate);
          await _tts.setVolume(1.0);
          await _tts.setPitch(1.0);

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
        }),
        Future.delayed(_ttsTimeout, () {
          throw TimeoutException('El motor TTS tardó más de ${_ttsTimeout.inMilliseconds}ms en responder');
        }),
      ]);
      return _ttsInitialized;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[NAVIA TTS] Servicio de voz nativo lento o no disponible: $e');
      _setState(VoiceState.error);
      return false;
    } finally {
      _isInitializing = false;
    }
  }

  /// Inicialización manual (no bloqueante).
  Future<void> initialize() async {
    unawaited(_initTts());
  }

  /// Habla el texto proporcionado usando TTS en español mexicano.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      final ready = await _initTts();
      if (!ready) return;

      // Detener si ya está hablando (con timeout)
      try {
        await _tts.stop().timeout(const Duration(milliseconds: 300));
      } catch (_) {}

      _setState(VoiceState.speaking);
      await _tts.speak(text).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('[NAVIA TTS] speak() superó el tiempo límite.');
          _setState(VoiceState.idle);
          return 0;
        },
      );
    } catch (e) {
      _lastError = 'TTS Speak Error: $e';
      _setState(VoiceState.error);
      debugPrint('[NAVIA TTS] Error en speak: $e');
    }
  }

  /// Detiene el TTS inmediatamente.
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop().timeout(const Duration(milliseconds: 300));
    } catch (_) {}
    _setState(VoiceState.idle);
  }

  /// Actualiza la velocidad de voz.
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.3, 2.0);
    if (_ttsInitialized) {
      try {
        await _tts.setSpeechRate(_speechRate).timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  }

  /// ¿Está el servicio hablando?
  bool get isSpeaking => _state == VoiceState.speaking;

  /// Libera recursos.
  Future<void> dispose() async {
    try {
      await _tts.stop().timeout(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  void _setState(VoiceState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(newState);
    }
  }
}
