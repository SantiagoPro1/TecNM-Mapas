import 'package:flutter/material.dart';
import 'package:navia/core/constants/app_routes.dart';

/// Ignores taps on the current destination or on a route that is leaving.
class AppNavigation {
  AppNavigation._();

  static bool _canNavigate(BuildContext context, String destination) {
    if (!context.mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null) return true;
    if (!route.isCurrent || route.settings.name == destination) return false;
    final animation = route.animation;
    return animation == null || animation.status == AnimationStatus.completed;
  }

  static void open(BuildContext context, String destination,
      {Object? arguments}) {
    if (!_canNavigate(context, destination)) return;
    final navigator = Navigator.of(context);
    if (destination == AppRoutes.home) {
      var foundHome = false;
      navigator.popUntil((route) {
        foundHome = route.settings.name == AppRoutes.home;
        return foundHome || route.isFirst;
      });
      if (!foundHome) {
        navigator.pushReplacementNamed(destination, arguments: arguments);
      }
      return;
    }
    navigator.pushNamed(destination, arguments: arguments);
  }

  static void push(BuildContext context, String destination,
          {Object? arguments}) =>
      open(context, destination, arguments: arguments);
}
