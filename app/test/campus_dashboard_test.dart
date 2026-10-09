import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/presentation/screens/navigation/campus_dashboard.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final dark in [false, true]) {
    for (final width in [320.0, 393.0, 820.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('Campus dashboard: dark=$dark width=$width scale=$scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final container = ProviderContainer();
          addTearDown(container.dispose);
          final theme =
              container.read(dark ? darkThemeProvider : lightThemeProvider);
          final boundary = GlobalKey();
          String? opened;
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  bottomNavigationBar: const BottomNav(currentIndex: 0),
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CampusDashboard(
                                venues: VenueRegistry.all,
                                onOpen: (venue) => opened = venue.id),
                          ])),
                )),
          ));
          await tester.pumpAndSettle();
          // Overflow errors are reported by the test binding.
          if (Platform.isWindows && width == 393 && scale == 1) {
            final render = boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await render.toImage(pixelRatio: 2);
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final directory = Directory('C:/SINAIT-APP/dist/design-preview')
                ..createSync(recursive: true);
              File('${directory.path}/${dark ? 'oscuro' : 'claro'}.png')
                  .writeAsBytesSync(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.ensureVisible(find.text('TecNM Colima'));
          await tester.tap(find.text('TecNM Colima'));
          expect(opened, 'tec_colima');
          await tester.ensureVisible(find.text(VenueRegistry.all[1].label));
          await tester.tap(find.text(VenueRegistry.all[1].label));
          expect(opened, VenueRegistry.all[1].id);
          await tester.drag(
              find.byType(SingleChildScrollView).first, const Offset(0, -1800));
          await tester.pumpAndSettle();
          // Overflow errors are reported by the test binding.
        });
      }
    }
  }
}
