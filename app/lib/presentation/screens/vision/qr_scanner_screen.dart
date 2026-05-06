import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:sinait/data/models/place_node.dart';
import 'package:sinait/presentation/screens/map/providers/map_providers.dart';
import 'package:sinait/presentation/screens/map/map_screen.dart'; 

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("es-MX");
    await _flutterTts.setSpeechRate(0.5);
    // Instrucción de voz para accesibilidad visual
    await _flutterTts.speak('Escáner activado. Por favor, apunta la cámara al código Q R de la pared para confirmar tu ubicación inicial.');
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final String code = barcodes.first.rawValue!;
      setState(() => _isProcessing = true);
      
      try {
        // Se espera un QR en formato JSON: {"node_id": "ID_DEL_LUGAR"}
        final Map<String, dynamic> data = jsonDecode(code);
        final String nodeId = data['node_id'] ?? '';

        if (nodeId.isNotEmpty) {
          _flutterTts.stop();
          
          final placesAsync = ref.read(placesStreamProvider);
          
          placesAsync.whenData((places) {
            PlaceNode? scannedNode;
            try {
              scannedNode = places.firstWhere((p) => p.id == nodeId);
            } catch (e) {
              scannedNode = null;
            }

            if (scannedNode != null) {
              // Confirmamos la posición en el Riverpod global
              ref.read(currentUserPositionProvider.notifier).state = scannedNode;
              
              _flutterTts.speak('Ubicación confirmada: ${scannedNode.name}. ¿A dónde deseas ir?');
              
              // Navegar al mapa después de dar tiempo al TTS para que hable
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MapScreen()),
                  );
                }
              });
            } else {
              _flutterTts.speak('Código detectado, pero el lugar no existe en nuestra base de datos.');
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) setState(() => _isProcessing = false);
              });
            }
          });
        }
      } catch (e) {
        debugPrint('Formato de QR no válido: $e');
        _flutterTts.speak('Formato de código inválido o no soportado por NAVIA.');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isProcessing = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear Ubicación (QR)'),
        backgroundColor: Colors.black87,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          
          // Overlay Accesible de alto contraste
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.qr_code_scanner, size: 64, color: Color(0xFF64FFDA)),
                    const SizedBox(height: 16),
                    Text(
                      _isProcessing ? 'Procesando código...' : 'Busca el código QR táctil en la pared',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Esto establecerá tu punto de partida con precisión milimétrica.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
