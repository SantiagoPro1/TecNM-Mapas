import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ─────────────────────────────────────────────────────
const _kVoiceEnabled = 'settings_voice_enabled';
const _kHighContrast = 'settings_high_contrast';
const _kVibrationEnabled = 'settings_vibration_enabled';
const _kSpeechRate = 'settings_speech_rate';

// ─── State ────────────────────────────────────────────────────

class AppSettings {
  final bool voiceEnabled;
  final bool highContrast;
  final bool vibrationEnabled;
  final double speechRate;

  const AppSettings({
    this.voiceEnabled = true,
    this.highContrast = false,
    this.vibrationEnabled = true,
    this.speechRate = 0.8,
  });

  AppSettings copyWith({
    bool? voiceEnabled,
    bool? highContrast,
    bool? vibrationEnabled,
    double? speechRate,
  }) {
    return AppSettings(
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      highContrast: highContrast ?? this.highContrast,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      speechRate: speechRate ?? this.speechRate,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      voiceEnabled: prefs.getBool(_kVoiceEnabled) ?? true,
      highContrast: prefs.getBool(_kHighContrast) ?? false,
      vibrationEnabled: prefs.getBool(_kVibrationEnabled) ?? true,
      speechRate: prefs.getDouble(_kSpeechRate) ?? 0.8,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVoiceEnabled, state.voiceEnabled);
    await prefs.setBool(_kHighContrast, state.highContrast);
    await prefs.setBool(_kVibrationEnabled, state.vibrationEnabled);
    await prefs.setDouble(_kSpeechRate, state.speechRate);
  }

  void toggleVoice(bool v) {
    state = state.copyWith(voiceEnabled: v);
    _save();
  }

  void toggleHighContrast(bool v) {
    state = state.copyWith(highContrast: v);
    _save();
  }

  void toggleVibration(bool v) {
    state = state.copyWith(vibrationEnabled: v);
    _save();
  }

  void setSpeechRate(double v) {
    state = state.copyWith(speechRate: v);
    _save();
  }
}

// ─── Provider ─────────────────────────────────────────────────

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
