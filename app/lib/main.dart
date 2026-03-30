import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Configuración y Tema
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/firebase_options.dart';

// Pantallas
import 'package:sinait/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:sinait/presentation/screens/navigation/home_screen.dart';
import 'package:sinait/presentation/screens/navigation/scanner_screen.dart';
import 'package:sinait/presentation/screens/navigation/history_screen.dart';
import 'package:sinait/presentation/screens/map/map_screen.dart';
import 'package:sinait/presentation/screens/credential/credential_screen.dart';
import 'package:sinait/presentation/screens/settings/settings_screen.dart';
import 'package:sinait/presentation/screens/settings/profile_screen.dart';

void main() async {
  // Asegura que los bindings de Flutter estén listos antes de inicializar Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicialización de Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Bloquear la orientación del teléfono en vertical (Portrait)
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  runApp(const SinaitApp());
}

class SinaitApp extends StatelessWidget {
  const SinaitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SINAIT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      
      // Define la pantalla inicial al abrir la app
      initialRoute: AppRoutes.onboarding,
      
      // Mapa de rutas tradicionales (reemplaza a go_router)
      routes: {
        AppRoutes.onboarding: (context) => const OnboardingScreen(),
        AppRoutes.home: (context) => const HomeScreen(),
        AppRoutes.scanner: (context) => const ScannerScreen(),
        AppRoutes.map: (context) => const MapScreen(),
        AppRoutes.credential: (context) => const CredentialScreen(),
        AppRoutes.history: (context) => const HistoryScreen(),
        AppRoutes.settings: (context) => const SettingsScreen(),
        AppRoutes.profile: (context) => const ProfileScreen(),
      },
    );
  }
}