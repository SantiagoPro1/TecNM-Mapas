import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:navia/data/providers/voice_provider.dart';

// Pantallas
import 'package:navia/presentation/screens/splash/splash_screen.dart';
import 'package:navia/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:navia/presentation/screens/auth/login_screen.dart';
import 'package:navia/presentation/screens/navigation/home_screen.dart';
import 'package:navia/presentation/screens/navigation/history_screen.dart';
import 'package:navia/presentation/screens/map/map_screen.dart';
import 'package:navia/presentation/screens/credential/credential_screen.dart';
import 'package:navia/presentation/screens/settings/settings_screen.dart';
import 'package:navia/presentation/screens/settings/profile_screen.dart';

/// Tiempo mínimo que se deja ver la pantalla de bienvenida.
///
/// La app arranca en menos de un segundo, así que el splash desaparecía antes
/// de que diera tiempo de leer "TEC COLIMA". No es una espera artificial
/// gratuita: es la única pantalla donde el usuario ve de quién es la app.
const Duration _minimoSplash = Duration(milliseconds: 2600);

void main() async {
  // 1. Asegura que los bindings de Flutter estén listos
  WidgetsFlutterBinding.ensureInitialized();
  final arranque = DateTime.now();

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

  // 3.0. Persistencia offline de Firestore, explícita (en móvil viene activa
  //      por defecto, pero de esto depende que las 8 sedes del evento —que
  //      no vienen empaquetadas en assets— sigan viéndose sin señal, así que
  //      no conviene dejarlo a un valor por defecto).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
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

  // 4.1. Revisar si el usuario ya eligió Invitado/Iniciar sesión en LoginScreen
  // (se pregunta una sola vez, justo después del onboarding — ver login_screen.dart).
  final bool hasChosenEntryMode = prefs.getBool('hasChosenEntryMode') ?? false;

  // 4.2. Completa el tiempo mínimo de splash. Si la inicialización ya tardó
  //      más que eso (teléfono lento, primer arranque), no espera nada extra.
  final transcurrido = DateTime.now().difference(arranque);
  if (transcurrido < _minimoSplash) {
    await Future.delayed(_minimoSplash - transcurrido);
  }

  // 5. Una vez listos todos los servicios, reemplazar el splash con la app real
  runApp(
    ProviderScope(
      child: NaviaApp(
        showOnboarding: showOnboarding,
        hasChosenEntryMode: hasChosenEntryMode,
      ),
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

/// Mensajero global de SnackBars — independiente de qué pantalla esté
/// activa. Necesario para el aviso de "llegaste a tu destino": la llegada
/// se detecta por GPS mientras la persona camina, y para entonces puede
/// estar en cualquier pantalla (Inicio, Perfil, Configuración...), no
/// necesariamente en el mapa. Un SnackBar atado al Scaffold de una pantalla
/// específica solo se ve si esa pantalla sigue siendo la visible cuando por
/// fin se muestra.
final naviaScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class NaviaApp extends ConsumerStatefulWidget {
  final bool showOnboarding;
  final bool hasChosenEntryMode;

  const NaviaApp({
    super.key,
    required this.showOnboarding,
    required this.hasChosenEntryMode,
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
    final themeMode = ref.watch(themeProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);

    // Aviso de llegada — a propósito vive aquí (raíz de la app, arriba del
    // Navigator) y no dentro de MapScreen: así se dispara sin importar en
    // qué pantalla esté la persona cuando el GPS confirma que llegó.
    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.status == NavStatus.arrived &&
          previous?.status != NavStatus.arrived) {
        ref.read(voiceProvider.notifier).speakAnnouncement(
            'Has llegado a tu destino. NAVIA te desea un excelente día.');
        naviaScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 22),
                SizedBox(width: 10),
                Expanded(child: Text('¡Has llegado a tu destino!')),
              ],
            ),
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        );
      }
    });

    return MaterialApp(
      title: 'NAVIA',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: naviaScaffoldMessengerKey,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,

      // Lógica de inicio: onboarding (si es nuevo) → elegir Invitado/Iniciar
      // sesión (una sola vez) → home.
      initialRoute: widget.showOnboarding
          ? AppRoutes.onboarding
          : (widget.hasChosenEntryMode ? AppRoutes.home : AppRoutes.login),

      // Mapa de rutas nativo (Navigator 1.0)
      routes: {
        AppRoutes.onboarding: (context) => const OnboardingScreen(),
        AppRoutes.login: (context) => const LoginScreen(),
        AppRoutes.home: (context) => const HomeScreen(),
        AppRoutes.map: (context) => const MapScreen(),
        AppRoutes.openMap: (context) => const MapScreen(openMap: true),
        AppRoutes.credential: (context) => const CredentialScreen(),
        AppRoutes.history: (context) => const HistoryScreen(),
        AppRoutes.settings: (context) => const SettingsScreen(),
        AppRoutes.profile: (context) => const ProfileScreen(),
      },
    );
  }
}
