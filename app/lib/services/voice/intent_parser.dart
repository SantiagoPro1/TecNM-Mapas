/// Tipos de intención reconocidos en comandos de voz.
enum IntentType {
  /// El usuario quiere navegar a un destino.
  /// Ej: "llévame a la biblioteca", "ir a cafetería"
  navigate,

  /// El usuario pregunta dónde está algo.
  /// Ej: "¿dónde está el laboratorio?", "¿dónde queda la cafetería?"
  whereIs,

  /// El usuario quiere saber su posición actual.
  /// Ej: "¿dónde estoy?", "mi ubicación"
  whereAmI,

  /// El usuario quiere repetir la última instrucción.
  /// Ej: "repite", "otra vez", "¿qué dijiste?"
  repeat,

  /// El usuario quiere detener la navegación.
  /// Ej: "detener", "parar", "cancelar navegación"
  stop,

  /// El usuario pide ayuda.
  /// Ej: "ayuda", "¿qué puedo decir?"
  help,

  /// El usuario quiere buscar destinos cercanos.
  /// Ej: "¿qué hay cerca?", "destinos cercanos"
  nearby,

  /// No se pudo determinar la intención.
  unknown,
}

/// Resultado del parsing de un comando de voz.
class ParsedIntent {
  /// Tipo de intención detectada.
  final IntentType type;

  /// Destino o query extraído del comando (null para intents sin destino).
  final String? destination;

  /// Texto original del comando.
  final String rawText;

  /// Nivel de confianza (0.0 a 1.0).
  final double confidence;

  const ParsedIntent({
    required this.type,
    this.destination,
    required this.rawText,
    this.confidence = 1.0,
  });

  @override
  String toString() =>
      'ParsedIntent($type, dest: $destination, raw: "$rawText")';
}

/// Parser de intenciones para comandos de voz en español mexicano.
///
/// Convierte texto libre del usuario en una [ParsedIntent] estructurada.
/// No requiere internet ni modelos ML — es un NLU basado en reglas
/// optimizado para el vocabulario del campus del TecNM.
class IntentParser {
  // ─── Patrones de navegación ─────────────────────────────────
  static final _navigatePatterns = [
    // "llévame a [destino]"
    RegExp(r'(?:ll[eé]vame|navega|nav[eé]game|gu[ií]ame|dir[ií]geme)\s+(?:a|al|a\s+la|al\s+la|hacia)\s+(.+)', caseSensitive: false),
    // "ir a [destino]"
    RegExp(r'(?:ir|ve|vamos|quiero\s+ir)\s+(?:a|al|a\s+la|hacia)\s+(.+)', caseSensitive: false),
    // "cómo llego a [destino]"
    RegExp(r'(?:c[oó]mo\s+(?:llego|voy))\s+(?:a|al|a\s+la)\s+(.+)', caseSensitive: false),
    // "ruta a [destino]"
    RegExp(r'(?:ruta|camino|direcci[oó]n)\s+(?:a|al|a\s+la|hacia|para)\s+(.+)', caseSensitive: false),
    // "a [destino]" (comando corto)
    RegExp(r'^(?:a|al|a\s+la)\s+(.+)$', caseSensitive: false),
  ];

  // ─── Patrones de "¿dónde está?" ────────────────────────────
  static final _whereIsPatterns = [
    RegExp(r'(?:d[oó]nde\s+(?:est[aá]|queda|se\s+encuentra))\s+(?:el|la|los|las)?\s*(.+)', caseSensitive: false),
    RegExp(r'(?:ubicaci[oó]n\s+(?:de|del|de\s+la))\s+(.+)', caseSensitive: false),
    RegExp(r'(?:buscar?|encontrar?)\s+(?:el|la|los|las)?\s*(.+)', caseSensitive: false),
  ];

  // ─── Patrones de "¿dónde estoy?" ───────────────────────────
  static final _whereAmIPatterns = [
    RegExp(r'd[oó]nde\s+estoy', caseSensitive: false),
    RegExp(r'mi\s+(?:ubicaci[oó]n|posici[oó]n)', caseSensitive: false),
    RegExp(r'(?:cu[aá]l|qu[eé])\s+es\s+mi\s+(?:ubicaci[oó]n|posici[oó]n)', caseSensitive: false),
    RegExp(r'posici[oó]n\s+actual', caseSensitive: false),
  ];

  // ─── Patrones de repetir ────────────────────────────────────
  static final _repeatPatterns = [
    RegExp(r'^(?:repite|repetir|otra\s+vez|de\s+nuevo|qu[eé]\s+dijiste)$', caseSensitive: false),
    RegExp(r'rep[ií]teme', caseSensitive: false),
    RegExp(r'no\s+(?:escuch[eé]|entend[ií]|o[ií])', caseSensitive: false),
  ];

  // ─── Patrones de detener ────────────────────────────────────
  static final _stopPatterns = [
    RegExp(r'^(?:detener|parar|para|stop|cancelar|alto|basta)$', caseSensitive: false),
    RegExp(r'cancelar?\s+(?:navegaci[oó]n|ruta)', caseSensitive: false),
    RegExp(r'detener?\s+(?:navegaci[oó]n|gu[ií]a)', caseSensitive: false),
  ];

  // ─── Patrones de ayuda ──────────────────────────────────────
  static final _helpPatterns = [
    RegExp(r'^(?:ayuda|help|socorro)$', caseSensitive: false),
    RegExp(r'qu[eé]\s+puedo\s+(?:decir|hacer|pedir)', caseSensitive: false),
    RegExp(r'comandos?\s+(?:disponibles|posibles)', caseSensitive: false),
    RegExp(r'c[oó]mo\s+(?:funciona|te\s+uso|se\s+usa)', caseSensitive: false),
  ];

  // ─── Patrones de cercanos ───────────────────────────────────
  static final _nearbyPatterns = [
    RegExp(r'qu[eé]\s+hay\s+(?:cerca|aqu[ií]|por\s+aqu[ií])', caseSensitive: false),
    RegExp(r'(?:destinos?|lugares?|edificios?)\s+cerca(?:nos?)?', caseSensitive: false),
    RegExp(r'(?:cerca|cercanos?|pr[oó]ximos?)$', caseSensitive: false),
    RegExp(r'alrededor', caseSensitive: false),
  ];

  /// Parsea un comando de voz en texto y retorna la intención estructurada.
  static ParsedIntent parse(String rawText) {
    final text = _cleanText(rawText);

    if (text.isEmpty) {
      return ParsedIntent(
        type: IntentType.unknown,
        rawText: rawText,
        confidence: 0.0,
      );
    }

    // 1. Detener (máxima prioridad para seguridad)
    for (final pattern in _stopPatterns) {
      if (pattern.hasMatch(text)) {
        return ParsedIntent(type: IntentType.stop, rawText: rawText);
      }
    }

    // 2. ¿Dónde estoy?
    for (final pattern in _whereAmIPatterns) {
      if (pattern.hasMatch(text)) {
        return ParsedIntent(type: IntentType.whereAmI, rawText: rawText);
      }
    }

    // 3. Repetir
    for (final pattern in _repeatPatterns) {
      if (pattern.hasMatch(text)) {
        return ParsedIntent(type: IntentType.repeat, rawText: rawText);
      }
    }

    // 4. Ayuda
    for (final pattern in _helpPatterns) {
      if (pattern.hasMatch(text)) {
        return ParsedIntent(type: IntentType.help, rawText: rawText);
      }
    }

    // 5. Cercanos
    for (final pattern in _nearbyPatterns) {
      if (pattern.hasMatch(text)) {
        return ParsedIntent(type: IntentType.nearby, rawText: rawText);
      }
    }

    // 6. Navegar (con extracción de destino)
    for (final pattern in _navigatePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final destination = _cleanDestination(match.group(1)!);
        if (destination.isNotEmpty) {
          return ParsedIntent(
            type: IntentType.navigate,
            destination: destination,
            rawText: rawText,
          );
        }
      }
    }

    // 7. ¿Dónde está? (con extracción de destino)
    for (final pattern in _whereIsPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final destination = _cleanDestination(match.group(1)!);
        if (destination.isNotEmpty) {
          return ParsedIntent(
            type: IntentType.whereIs,
            destination: destination,
            rawText: rawText,
          );
        }
      }
    }

    // 8. Fallback: si el texto es corto, intentar como navegación directa
    if (text.split(' ').length <= 4) {
      return ParsedIntent(
        type: IntentType.navigate,
        destination: text,
        rawText: rawText,
        confidence: 0.5, // Baja confianza — asumimos intención
      );
    }

    return ParsedIntent(
      type: IntentType.unknown,
      rawText: rawText,
      confidence: 0.0,
    );
  }

  /// Limpia el texto de entrada (normalización).
  static String _cleanText(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r'[¿?¡!.,;:]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  /// Limpia el nombre del destino extraído.
  static String _cleanDestination(String destination) {
    return destination
        .trim()
        .replaceAll(RegExp(r'^(el|la|los|las|un|una)\s+'), '')
        .replaceAll(RegExp(r'\s+por\s+favor$'), '')
        .replaceAll(RegExp(r'\s+please$'), '')
        .trim();
  }

  /// Genera el texto de ayuda con los comandos disponibles.
  static String get helpText => '''
Puedes decir cosas como:
• "Llévame a la biblioteca"
• "Ir a cafetería"
• "¿Dónde está el laboratorio de cómputo?"
• "¿Dónde estoy?"
• "¿Qué hay cerca?"
• "Repetir" para escuchar la última instrucción
• "Detener" para cancelar la navegación
• "Ayuda" para escuchar estos comandos''';
}
