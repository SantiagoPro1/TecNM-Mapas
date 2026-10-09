import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/presentation/screens/map/map_notice_scope.dart';

void main() {
  final container = ProviderContainer();
  tearDownAll(container.dispose);
  for (final theme in [
    container.read(lightThemeProvider),
    container.read(darkThemeProvider)
  ]) {
    for (final background in [
      theme.colorScheme.primary,
      theme.colorScheme.tertiary,
      theme.colorScheme.error
    ]) {
      testWidgets(
          'Notice text contrasts with $background in ${theme.colorScheme.primary}',
          (tester) async {
        final key = GlobalKey<ScaffoldMessengerState>();
        await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: MapNoticeScope(
              messengerKey: key,
              child: const Scaffold(body: SizedBox.expand()),
            )));
        key.currentState!.showSnackBar(MapNotice(
          content: const Text('Modo editor activado'),
          backgroundColor: background,
        ));
        await tester.pumpAndSettle();
        final element = tester.element(find.text('Modo editor activado'));
        final color = DefaultTextStyle.of(element).style.color!;
        final a = color.computeLuminance();
        final b = background.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
        expect(tester.widget<SnackBar>(find.byType(SnackBar)).closeIconColor,
            color);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final delayed in [false, true]) {
    testWidgets(
        delayed
            ? 'A point saved after leaving the map does not notify Home'
            : 'A visible map notice does not follow navigation to Home',
        (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      final navigatorKey = GlobalKey<NavigatorState>();
      final saved = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        initialRoute: '/map',
        routes: {
          '/': (_) => const Scaffold(body: Text('Home')),
          '/map': (_) => MapNoticeScope(
                messengerKey: messengerKey,
                child: Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      if (delayed) await saved.future;
                      messengerKey.currentState?.showSnackBar(
                        const SnackBar(content: Text('Punto agregado')),
                      );
                    },
                    child: const Text('Crear punto'),
                  ),
                ),
              ),
        },
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear punto'));
      await tester.pumpAndSettle();
      if (!delayed) expect(find.text('Punto agregado'), findsOneWidget);
      navigatorKey.currentState!.pushReplacementNamed('/');
      await tester.pumpAndSettle();
      if (delayed) {
        saved.complete();
        await tester.pumpAndSettle();
      }
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Punto agregado'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
