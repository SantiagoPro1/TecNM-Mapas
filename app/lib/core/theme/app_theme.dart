import 'package:flutter/material.dart';

class AppTheme {
  // Colores Premium SINAIT
  static const Color background = Color(0xFF0D1B2A);
  static const Color surface = Color(0xFF1A2E45);
  static const Color primary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF00E5FF); // Cian SINAIT
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF90CAF9); // Azul claro para sutileza
  static const Color success = Color(0xFF00E676);
  static const Color error = Color(0xFFFF5252);
  static const Color cardBackground = Color(0xFF1A2E45);
  static const Color navBackground = Color(0xFF0D1B2A);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: surface,
        onPrimary: Color(0xFF0D1B2A), // Contraste oscuro sobre cian
        onSecondary: Color(0xFF0D1B2A),
        onSurface: textPrimary,
        error: error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF0D1B2A),
          minimumSize: const Size(double.infinity, 56),
          elevation: 4,
          shadowColor: accent.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 8,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accent.withOpacity(0.1), width: 1),
        ),
      ),
      iconTheme: const IconThemeData(
        color: accent,
        size: 28,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          color: textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 15,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          color: Color(0xFF0D1B2A),
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      useMaterial3: true,
    );
  }
}