import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Clave de persistencia ──────────────────────────────────────
const _kThemeIndex = 'settings_theme_index';

// ─── Metadatos de cada paleta ───────────────────────────────────

class AppThemeInfo {
  final String id;
  final String label;
  final String description;
  final Color previewColor;

  const AppThemeInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.previewColor,
  });
}

/// Catálogo de temas disponibles (orden = índice en el notifier).
const List<AppThemeInfo> availableThemes = [
  AppThemeInfo(
    id: 'tecnm_dark',
    label: 'TecNM Dark',
    description: 'Tema oscuro premium institucional',
    previewColor: Color(0xFF38BDF8),
  ),
  AppThemeInfo(
    id: 'industrial_hc',
    label: 'Industrial HC',
    description: 'Alto contraste · Gris oscuro / Naranja',
    previewColor: Color(0xFFFF8F00),
  ),
  AppThemeInfo(
    id: 'light_clean',
    label: 'Light Clean',
    description: 'Interfaz luminosa y minimalista',
    previewColor: Color(0xFF1976D2),
  ),
  AppThemeInfo(
    id: 'pastel_minimal',
    label: 'Pastel Minimal',
    description: 'Colores pasteles suaves y relajados',
    previewColor: Color(0xFF7C4DFF),
  ),
];

// ─── Constantes estáticas de compatibilidad (solo para contextos const) ──
//
// ⚠️  PREFERIR  Theme.of(context).colorScheme.primary  y similares.
//     Estas constantes existen SOLO para widgets que requieren `const`
//     (p.ej. `const Icon(color: AppTheme.accent)`).
//     Para reactividad al cambio de tema, usar Theme.of(context).
//
class AppTheme {
  AppTheme._();

  // ── Colores del tema TecNM Dark (fallback) ──
  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E293B);
  static const Color accent = Color(0xFF38BDF8);
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color error = Color(0xFFF43F5E);
  static const Color success = Color(0xFF34D399);
}

// ─── Generación de ThemeData por índice ──────────────────────────

ThemeData _buildTheme(int index) {
  switch (index) {
    case 0:
      return _tecnmDark();
    case 1:
      return _industrialHc();
    case 2:
      return _lightClean();
    case 3:
      return _pastelMinimal();
    default:
      return _tecnmDark();
  }
}

// ────────────────────────────────────────────────────────────────
//  0 · TecNM Dark  (tema original del proyecto)
// ────────────────────────────────────────────────────────────────

ThemeData _tecnmDark() {
  const background = Color(0xFF0F172A);
  const surface = Color(0xFF1E293B);
  const accent = Color(0xFF38BDF8);
  const textPrimary = Color(0xFFF1F5F9);
  const textSecondary = Color(0xFF94A3B8);
  const error = Color(0xFFF43F5E);
  const success = Color(0xFF34D399);

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: accent,
    fontFamily: 'Roboto',
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: surface,
      onPrimary: Color(0xFF0F172A),
      onSecondary: Color(0xFF0F172A),
      onSurface: textPrimary,
      error: error,
      tertiary: success,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: const Color(0xFF0F172A),
        minimumSize: const Size(double.infinity, 56),
        elevation: 2,
        shadowColor: accent.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.03), width: 1),
      ),
    ),
    iconTheme: const IconThemeData(color: accent, size: 24),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        color: textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: textPrimary,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(
        color: textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    useMaterial3: true,
  );
}

// ────────────────────────────────────────────────────────────────
//  1 · Industrial High Contrast  (Gris oscuro / Naranja)
// ────────────────────────────────────────────────────────────────

ThemeData _industrialHc() {
  const background = Color(0xFF1A1A1A);
  const surface = Color(0xFF2A2A2A);
  const accent = Color(0xFFFF8F00);
  const textPrimary = Color(0xFFFAFAFA);
  const textSecondary = Color(0xFFBDBDBD);
  const error = Color(0xFFFF1744);
  const success = Color(0xFF00E676);

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: accent,
    fontFamily: 'Roboto',
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: Color(0xFFFFCC80),
      surface: surface,
      onPrimary: Color(0xFF1A1A1A),
      onSecondary: Color(0xFF1A1A1A),
      onSurface: textPrimary,
      error: error,
      tertiary: success,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: const Color(0xFF1A1A1A),
        minimumSize: const Size(double.infinity, 56),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.15), width: 1),
      ),
    ),
    iconTheme: const IconThemeData(color: accent, size: 24),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        color: textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
      bodyLarge: TextStyle(
        color: textPrimary,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(
        color: textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ),
    useMaterial3: true,
  );
}

// ────────────────────────────────────────────────────────────────
//  2 · Light Clean  (luminoso y minimalista)
// ────────────────────────────────────────────────────────────────

ThemeData _lightClean() {
  const background = Color(0xFFF8FAFC);
  const surface = Color(0xFFFFFFFF);
  const accent = Color(0xFF1976D2);
  const textPrimary = Color(0xFF1E293B);
  const textSecondary = Color(0xFF64748B);
  const error = Color(0xFFDC2626);
  const success = Color(0xFF16A34A);

  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: background,
    primaryColor: accent,
    fontFamily: 'Roboto',
    colorScheme: const ColorScheme.light(
      primary: accent,
      secondary: Color(0xFF42A5F5),
      surface: surface,
      onPrimary: Colors.white,
      onSecondary: textPrimary,
      onSurface: textPrimary,
      error: error,
      tertiary: success,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        elevation: 1,
        shadowColor: accent.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 1,
      shadowColor: const Color(0xFF1E293B).withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
            color: const Color(0xFF1E293B).withValues(alpha: 0.06), width: 1),
      ),
    ),
    iconTheme: const IconThemeData(color: accent, size: 24),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        color: textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: textPrimary,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(
        color: textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    useMaterial3: true,
  );
}

// ────────────────────────────────────────────────────────────────
//  3 · Pastel Minimal  (suave, relajado, pastel)
// ────────────────────────────────────────────────────────────────

ThemeData _pastelMinimal() {
  const background = Color(0xFFF5F0FF);
  const surface = Color(0xFFFFFFFF);
  const accent = Color(0xFF7C4DFF);
  const textPrimary = Color(0xFF2D2D3F);
  const textSecondary = Color(0xFF8E8EA0);
  const error = Color(0xFFFF6B6B);
  const success = Color(0xFF51CF66);

  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: background,
    primaryColor: accent,
    fontFamily: 'Roboto',
    colorScheme: const ColorScheme.light(
      primary: accent,
      secondary: Color(0xFFB388FF),
      surface: surface,
      onPrimary: Colors.white,
      onSecondary: Color(0xFF2D2D3F),
      onSurface: textPrimary,
      error: error,
      tertiary: success,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: accent.withValues(alpha: 0.1), width: 1),
      ),
    ),
    iconTheme: const IconThemeData(color: accent, size: 24),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        color: textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: textPrimary,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(
        color: textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    useMaterial3: true,
  );
}

// ─── ThemeNotifier ──────────────────────────────────────────────

class ThemeNotifier extends StateNotifier<ThemeData> {
  int _currentIndex;

  ThemeNotifier()
      : _currentIndex = 0,
        super(_buildTheme(0)) {
    _loadFromDisk();
  }

  int get currentIndex => _currentIndex;

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_kThemeIndex) ?? 0;
    _currentIndex = index.clamp(0, availableThemes.length - 1);
    state = _buildTheme(_currentIndex);
  }

  Future<void> setTheme(int index) async {
    if (index < 0 || index >= availableThemes.length) return;
    _currentIndex = index;
    state = _buildTheme(index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeIndex, index);
  }

  /// Indica si el tema activo es de brillo oscuro.
  bool get isDark => state.brightness == Brightness.dark;
}

// ─── Provider Riverpod ──────────────────────────────────────────

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeData>((ref) {
  return ThemeNotifier();
});
