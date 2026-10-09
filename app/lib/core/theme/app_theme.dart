// Sistema visual de NAVIA.
//
// Una sola identidad (no una lista de "temas"/moods para elegir): azul
// marino institucional real, tomado del logo de TecNM (`#002E6D`, ver
// assets/images/logo_tecnm.png), sobre una escala de grises neutros sin
// matiz — nada de "slate" azulado ni acentos saturados tipo neón. Claro y
// oscuro son la misma identidad, no paletas distintas.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Clave de persistencia ──────────────────────────────────────
const _kThemeMode = 'settings_theme_mode'; // 0=system, 1=light, 2=dark

/// Modo con el que arranca quien nunca eligió uno.
///
/// Claro, no "el del sistema". Es una app institucional: una credencial y un
/// mapa de campus se leen como un documento impreso —azul marino del TecNM
/// sobre papel—, no como un panel de control. En oscuro, el acento tiene que
/// aclararse para que contraste contra el negro, y ese azul claro encendido
/// sobre fondo casi negro es justo el aspecto genérico "de app de IA" que se
/// pidió evitar. Quien prefiera oscuro lo activa en Ajustes.
const ThemeMode _modoPorDefecto = ThemeMode.light;

// ─── Paleta base ──────────────────────────────────────────────────

/// Grises neutros verdaderos (sin matiz azul/morado) — la mayoría de la UI
/// vive aquí. El color de marca se reserva para acciones y estados activos.
class _Neutral {
  static const Color white = Color(0xFFFFFFFF);
  static const Color n50 = Color(0xFFF4F4F4);
  static const Color n400 = Color(0xFF8F8F8F);
  static const Color n700 = Color(0xFF333333);
  static const Color n800 = Color(0xFF212121);
  static const Color n850 = Color(0xFF171717);
  static const Color n900 = Color(0xFF101010);
}

/// Azul marino de marca, derivado del logo oficial de TecNM.
class _Navy {
  static const Color deep = Color(0xFF00204D); // texto/énfasis sobre claro
  static const Color base = Color(0xFF002E6D); // el color real del logo
  static const Color mid = Color(0xFF2B569B); // sobre claro, más suave
  static const Color light = Color(0xFF7DA0DD); // primario en modo oscuro
  static const Color pale = Color(0xFFE8EDF7); // fondo sutil en modo claro
}

/// Semántica de estado — deliberadamente apagada, no neón.
class _Semantic {
  static const Color successDark = Color(0xFF6FBE8F);
  static const Color errorDark = Color(0xFFE28680);
}

/// Ámbar institucional (del sello ITColima) para estados de advertencia —
/// no está en ColorScheme por defecto, se expone aparte a propósito.
class AppWarning {
  AppWarning._();
  static const Color light = Color(0xFF8A6100);
  static const Color dark = Color(0xFFD3A94A);
}

/// Colores del mapa. Van aparte del ColorScheme porque se pintan sobre
/// teselas de Google Maps (no sobre superficies del tema) y se dibujan en
/// canvas, donde no hay `Theme.of(context)`.
///
/// Sigue el patrón de Google Maps (punto con anillo blanco, pines de gota),
/// pero con el azul del TecNM en vez del azul de Google. El anillo blanco es
/// lo que permite que el punto se distinga aunque esté encima de la línea de
/// ruta, que es del mismo color — igual que en Google Maps.
class AppMapColors {
  AppMapColors._();

  /// Punto de ubicación del usuario.
  static const Color userLocation = _Navy.base;

  /// Halo de precisión alrededor del punto.
  static const Color userLocationHalo = _Navy.base;

  /// Pines de comida/cafetería: ocre plano, para diferenciarlos de un
  /// vistazo sin recurrir a colores encendidos.
  static const Color poiFood = Color(0xFFB26B00);

  /// Canchas, pistas, albercas — todo lo deportivo. Verde apagado, como el
  /// verde de parques de Google Maps, no el verde encendido de "éxito".
  static const Color poiSport = Color(0xFF2F6B44);

  /// Servicios generales (registro, información, baños, vestidores) y
  /// edificios: el azul de marca, que es el pin por defecto.
  static const Color poiService = _Navy.base;

  /// Primeros auxilios / servicios médicos.
  static const Color poiMedical = Color(0xFFA3271F);

  /// Transporte y estacionamiento: gris azulado sobrio.
  static const Color poiTransit = Color(0xFF4A5866);
}

/// Radios de borde: escala corta y consistente (nada de 24-28px "burbuja").
class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

/// Espaciados estándar, para no improvisar números sueltos por pantalla.
class AppSpace {
  AppSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Constantes const de compatibilidad, solo para contextos `const`
/// (p. ej. `const Icon(color: AppTheme.accent)`). Preferir siempre
/// `Theme.of(context).colorScheme` para que reaccione a claro/oscuro.
class AppTheme {
  AppTheme._();
  static const Color background = _Neutral.n900;
  static const Color surface = _Neutral.n850;
  static const Color accent = _Navy.light;
  static const Color textPrimary = _Neutral.n50;
  static const Color textSecondary = _Neutral.n400;
  static const Color error = _Semantic.errorDark;
  static const Color success = _Semantic.successDark;

  /// Azul marino real de marca (logo TecNM), fijo independientemente del
  /// modo claro/oscuro — para elementos con identidad visual propia que no
  /// deben cambiar con el tema, como la credencial digital (imita una
  /// credencial física impresa, siempre sobre fondo claro).
  static const Color brandNavy = _Navy.base;
  static const Color brandNavyDeep = _Navy.deep;
}

// ─── Construcción de ThemeData ───────────────────────────────────

TextTheme _textTheme(Color primary, Color secondary) {
  const family = 'Manrope';
  return TextTheme(
    displayLarge: TextStyle(
      fontFamily: family,
      color: primary,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      height: 1.15,
    ),
    displayMedium: TextStyle(
      fontFamily: family,
      color: primary,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.2,
    ),
    titleLarge: TextStyle(
      fontFamily: family,
      color: primary,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    bodyLarge: TextStyle(
      fontFamily: family,
      color: primary,
      fontSize: 15.5,
      fontWeight: FontWeight.w500,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      fontFamily: family,
      color: secondary,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      height: 1.45,
    ),
    labelLarge: TextStyle(
      fontFamily: family,
      color: primary,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
  );
}

ThemeData _buildLight() {
  // Tema principal inmersivo azul institucional (TecNM).
  // Se abandona el fondo blanco a petición del usuario.
  const background = _Navy.base;
  const surface = _Navy.deep; // Tarjetas levemente más oscuras para contrastar con el fondo
  const primary = _Neutral.white; // Acentos en blanco/celeste
  const textPrimary = _Neutral.white;
  const textSecondary = _Navy.light; // Textos secundarios en azul claro
  const outline = _Navy.mid; // Bordes en azul medio

  const colorScheme = ColorScheme.dark(
    primary: primary,
    onPrimary: _Navy.base,
    secondary: _Navy.pale,
    onSecondary: _Navy.deep,
    surface: surface,
    onSurface: textPrimary,
    surfaceContainerHighest: _Navy.mid,
    error: _Semantic.errorDark,
    onError: _Neutral.white,
    tertiary: _Semantic.successDark,
    outline: outline,
    outlineVariant: _Navy.deep,
  );

  return _theme(
    brightness: Brightness.dark, // Usamos dark para que la status bar y elementos respondan correctamente a fondos oscuros
    background: background,
    colorScheme: colorScheme,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    surface: surface,
    outline: outline,
  );
}

ThemeData _buildDark() {
  const background = _Neutral.n900;
  const surface = _Neutral.n850;
  const primary = _Navy.light;
  const textPrimary = _Neutral.n50;
  const textSecondary = _Neutral.n400;
  const outline = _Neutral.n700;

  const colorScheme = ColorScheme.dark(
    primary: primary,
    onPrimary: _Navy.deep,
    secondary: _Navy.pale,
    onSecondary: _Navy.deep,
    surface: surface,
    onSurface: textPrimary,
    surfaceContainerHighest: _Neutral.n800,
    error: _Semantic.errorDark,
    onError: _Navy.deep,
    tertiary: _Semantic.successDark,
    outline: outline,
    outlineVariant: _Neutral.n800,
  );

  return _theme(
    brightness: Brightness.dark,
    background: background,
    colorScheme: colorScheme,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    surface: surface,
    outline: outline,
  );
}

ThemeData _theme({
  required Brightness brightness,
  required Color background,
  required ColorScheme colorScheme,
  required Color textPrimary,
  required Color textSecondary,
  required Color surface,
  required Color outline,
}) {
  final textTheme = _textTheme(textPrimary, textSecondary);

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: background,
    primaryColor: colorScheme.primary,
    fontFamily: 'Manrope',
    colorScheme: colorScheme,
    // Onda sobria al tocar, no el destello "sparkle" de Material You: ese
    // brillo animado es parte del aspecto genérico que se pidió evitar.
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: outline,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(double.infinity, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: BorderSide(color: outline),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: textPrimary),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: outline, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.dark
          ? const Color(0xFF1B1B1B)
          : _Neutral.n50,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      labelStyle: TextStyle(color: textSecondary, fontFamily: 'Manrope'),
      hintStyle: TextStyle(
          color: textSecondary.withValues(alpha: 0.7), fontFamily: 'Manrope'),
    ),
    dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? colorScheme.primary
              : textSecondary),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? colorScheme.primary.withValues(alpha: 0.35)
              : outline),
      trackOutlineColor:
          const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm / 2)),
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? colorScheme.primary
              : Colors.transparent),
      side: BorderSide(color: outline),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: colorScheme.primary,
      labelStyle: TextStyle(color: textPrimary, fontFamily: 'Manrope'),
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: brightness == Brightness.dark
          ? _Neutral.n700
          : _Neutral.n800,
      contentTextStyle:
          const TextStyle(color: Colors.white, fontFamily: 'Manrope'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    progressIndicatorTheme:
        ProgressIndicatorThemeData(color: colorScheme.primary),
    iconTheme: IconThemeData(color: textPrimary, size: 22),
    textTheme: textTheme,
    useMaterial3: true,
  );
}

// ─── ThemeNotifier ──────────────────────────────────────────────

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(_modoPorDefecto) {
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kThemeMode);
    if (raw == null) {
      state = _modoPorDefecto; // nunca eligió: no heredar el modo del sistema
      return;
    }
    state = switch (raw) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kThemeMode,
      switch (mode) {
        ThemeMode.light => 1,
        ThemeMode.dark => 2,
        ThemeMode.system => 0,
      },
    );
  }
}

// ─── Providers Riverpod ───────────────────────────────────────────

/// Modo de tema elegido por el usuario (claro / oscuro / seguir sistema).
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

/// `ThemeData` de las dos identidades — MaterialApp elige entre ambos según
/// `themeProvider` (o el sistema, si está en modo automático).
final lightThemeProvider = Provider<ThemeData>((ref) => _buildLight());
final darkThemeProvider = Provider<ThemeData>((ref) => _buildDark());
