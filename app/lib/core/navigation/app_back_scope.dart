import 'package:flutter/material.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/navigation/app_navigation.dart';

/// System Back walks through app history and stays inside the root screen.
class AppBackScope extends StatelessWidget {
  final Widget child;
  final bool fallbackToHome;

  const AppBackScope(
      {super.key, required this.child, this.fallbackToHome = true});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    return PopScope<Object?>(
      canPop: route != null && !route.isFirst,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop ||
            !fallbackToHome ||
            route?.settings.name == AppRoutes.home) {
          return;
        }
        AppNavigation.open(context, AppRoutes.home);
      },
      child: child,
    );
  }
}
