import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Pantalla de bienvenida de NAVIA.
/// Se muestra durante el arranque mientras los servicios se inicializan.
/// Es reemplazada automáticamente por [NaviaApp] una vez que [main] termina.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1D2E5E),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo principal NAVIA
              Image.asset(
                'assets/images/logo_navia.png',
                width: 160,
                height: 160,
                fit: BoxFit.contain,
              )
                  .animate()
                  .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                  .scaleXY(
                    begin: 0.80,
                    end: 1.0,
                    duration: 600.ms,
                    curve: Curves.easeOutBack,
                  ),

              const SizedBox(height: 28),

              // Nombre de la app
              const Text(
                'NAVIA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                ),
              )
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 500.ms)
                  .slideY(begin: 0.2, end: 0.0, duration: 500.ms),

              const SizedBox(height: 6),

              // Subtítulo descriptivo
              const Text(
                'Sistema de Navegación Inteligente Accesible',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFB0BEC5),
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ).animate().fadeIn(delay: 500.ms, duration: 400.ms),

              const SizedBox(height: 60),

              // Indicador de carga
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ).animate().fadeIn(delay: 700.ms, duration: 400.ms),

              const SizedBox(height: 16),

              Text(
                'Iniciando...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ).animate().fadeIn(delay: 800.ms, duration: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
