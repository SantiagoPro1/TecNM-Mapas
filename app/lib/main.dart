import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // 1. Asegura que los bindings de Flutter estén listos
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Inicialización de Firebase (Esencial para Google Sign-In)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 3. Bloquear la orientación del teléfono en vertical (Portrait)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 4. Revisar si debemos mostrar el Onboarding (Términos y Condiciones)
  final prefs = await SharedPreferences.getInstance();
  final bool showOnboarding = prefs.getBool('showOnboarding') ?? true;
  
  // Lanzamos la App pasando el estado del Onboarding
  runApp(SinaitApp(showOnboarding: showOnboarding));
}

class SinaitApp extends StatelessWidget {
  final bool showOnboarding;

  const SinaitApp({
    super.key, 
    required this.showOnboarding
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SINAIT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      
      // Lógica de inicio: Si es nuevo va a onboarding, si no, al home
      initialRoute: showOnboarding ? AppRoutes.onboarding : AppRoutes.home,
      
      // Mapa de rutas nativo (Navigator 1.0)
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