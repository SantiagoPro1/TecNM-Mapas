import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:navia/core/theme/app_theme.dart';

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
      backgroundColor: AppTheme.brandNavy,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Escudo del TecNM Campus Colima, sobre un disco blanco: el
              // escudo es amarillo con trazo azul marino, y sobre el fondo
              // azul de marca los contornos se pierden. El disco lo separa.
              Container(
                width: 160,
                height: 160,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(14),
                child: Image.asset(
                  'assets/images/logo_itcolima.png',
                  fit: BoxFit.contain,
                ),
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
                'TEC COLIMA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              )
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 500.ms)
                  .slideY(begin: 0.2, end: 0.0, duration: 500.ms),

              const SizedBox(height: 6),

              // Subtítulo descriptivo
              const Text(
                'Mapas y navegación del campus',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
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
