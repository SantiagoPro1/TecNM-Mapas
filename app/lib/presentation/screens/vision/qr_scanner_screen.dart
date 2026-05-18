// qr_scanner_screen.dart
//
// DEPRECADO: esta pantalla fue reemplazada por AssistiveCameraScreen
// (scanner_screen.dart) que usa el paquete `camera` + TFLite.
//
// Se conserva como archivo de marcador para facilitar el historial de git.
// No está registrada en AppRouter y no importa mobile_scanner.

import 'package:flutter/material.dart';

/// Pantalla legada de escáner QR (sin uso en producción).
///
/// Fue sustituida por [ScannerScreen] ubicada en
/// `presentation/screens/navigation/scanner_screen.dart`.
class QRScannerScreen extends StatelessWidget {
  const QRScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR Scanner (Deprecated)')),
      body: const Center(
        child: Text('Esta pantalla ha sido reemplazada por NAVIA AR.'),
      ),
    );
  }
}
