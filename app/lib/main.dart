import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Configuración y Tema
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/firebase_options.dart';

// Cache offline y modo sin conexión
import 'package:navia/data/cache/map_cache_service.dart';
import 'package:navia/services/offline/offline_manager.dart';

// Precarga de SVGs del mapa
import 'package:navia/utils/svg_marker_helper.dart';

// Providers
import 'package:navia/data/providers/navigation_provider.dart';

// Pantallas
import 'package:navia/presentation/screens/splash/splash_screen.dart';
import 'package:navia/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:navia/presentation/screens/navigation/home_screen.dart';
import 'package:navia/presentation/screens/navigation/scanner_screen.dart';
import 'package:navia/presentation/screens/navigation/history_screen.dart';
import 'package:navia/presentation/screens/map/map_screen.dart';
import 'package:navia/presentation/screens/credential/credential_screen.dart';
import 'package:navia/presentation/screens/settings/settings_screen.dart';
import 'package:navia/presentation/screens/settings/profile_screen.dart';

void main() async {
  // 1. Asegura que los bindings de Flutter estén listos
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Mostrar el splash screen Flutter inmediatamente para una transición
  //    suave desde el splash nativo Android
  runApp(const _SplashWrapper());

  // 3. Inicializar todos los servicios en background
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint(
      '[NAVIA] Advertencia: No se encontró el archivo .env. '
      'Las variables de entorno no estarán disponibles. Error: $e',
    );
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3.1. Inicializar Hive y sembrar la caché offline de mapas
  await MapCacheService.initialize();

  // 3.2. Inicializar sistema offline (conectividad + posición guardada)
  await OfflineManager.initialize();

  // 3.3. Precarga de iconos SVG del mapa para evitar parpadeos
  await PrecacheSvg.precacheAll();

  // 3.4. Bloquear la orientación del teléfono en vertical (Portrait)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 4. Revisar si debemos mostrar el Onboarding (Términos y Condiciones)
  final prefs = await SharedPreferences.getInstance();
  final bool showOnboarding = prefs.getBool('showOnboarding') ?? true;

  // 5. Una vez listos todos los servicios, reemplazar el splash con la app real
  runApp(
    ProviderScope(
      child: NaviaApp(showOnboarding: showOnboarding),
    ),
  );
}

/// Widget temporal que muestra el [SplashScreen] mientras [main] inicializa
/// los servicios. Se reemplaza con [NaviaApp] una vez que todo está listo.
class _SplashWrapper extends StatelessWidget {
  const _SplashWrapper();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}

class NaviaApp extends ConsumerStatefulWidget {
  final bool showOnboarding;

  const NaviaApp({
    super.key,
    required this.showOnboarding,
  });

  @override
  ConsumerState<NaviaApp> createState() => _NaviaAppState();
}

class _NaviaAppState extends ConsumerState<NaviaApp> {
  @override
  void initState() {
    super.initState();
    // Inicializar el grafo de navegación en background
    Future.microtask(() {
      ref.read(navigationProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return MaterialApp(
      title: 'NAVIA',
      debugShowCheckedModeBanner: false,
      theme: theme,

      // Lógica de inicio: Si es nuevo va a onboarding, si no, al home
      initialRoute:
          widget.showOnboarding ? AppRoutes.onboarding : AppRoutes.home,

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
