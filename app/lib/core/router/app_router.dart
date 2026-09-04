import 'package:go_router/go_router.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:navia/presentation/screens/auth/login_screen.dart';
import 'package:navia/presentation/screens/navigation/home_screen.dart';
import 'package:navia/presentation/screens/map/map_screen.dart';
import 'package:navia/presentation/screens/credential/credential_screen.dart';
import 'package:navia/presentation/screens/navigation/history_screen.dart';
import 'package:navia/presentation/screens/settings/settings_screen.dart';
import 'package:navia/presentation/screens/settings/profile_screen.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.onboarding,
  routes: [
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
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
