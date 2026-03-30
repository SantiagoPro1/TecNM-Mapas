import 'package:go_router/go_router.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:sinait/presentation/screens/navigation/home_screen.dart';
import 'package:sinait/presentation/screens/map/map_screen.dart';
import 'package:sinait/presentation/screens/navigation/scanner_screen.dart';
import 'package:sinait/presentation/screens/credential/credential_screen.dart';
import 'package:sinait/presentation/screens/navigation/history_screen.dart';
import 'package:sinait/presentation/screens/settings/settings_screen.dart';
import 'package:sinait/presentation/screens/settings/profile_screen.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.onboarding,
  routes: [
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.map,
      builder: (context, state) => const MapScreen(),
    ),
    GoRoute(
      path: AppRoutes.scanner,
      builder: (context, state) => const ScannerScreen(),
    ),
    GoRoute(
      path: AppRoutes.credential,
      builder: (context, state) => const CredentialScreen(),
    ),
    GoRoute(
      path: AppRoutes.history,
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.profile,
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
);