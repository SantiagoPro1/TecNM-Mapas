// assistive_camera_screen.dart
//
// DEPRECADO: Esta pantalla fue consolidada en ScannerScreen
// (presentation/screens/navigation/scanner_screen.dart).
//
// La pantalla principal de NAVIA AR es ScannerScreen, que integra
// el pipeline completo: Camera -> TFLite -> VisionProvider -> Voz.
//
// Se conserva como archivo de marcador para facilitar el historial de git.

import 'package:flutter/material.dart';
import 'package:navia/presentation/screens/navigation/scanner_screen.dart';

/// Pantalla legada de camara asistiva.
///
/// Redirige a [ScannerScreen] para evitar duplicacion de codigo.
class AssistiveCameraScreen extends StatelessWidget {
  const AssistiveCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScannerScreen();
  }
}
