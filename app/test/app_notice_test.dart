import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/presentation/screens/map/map_notice_scope.dart';
import 'package:navia/presentation/widgets/announcement_notice.dart';
import 'package:navia/data/models/announcement.dart';

void main() {
  for (final type in AnnouncementType.values) {
    testWidgets('Venue announcement $type uses its semantic color',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final expected = switch (type) {
        AnnouncementType.closure => const Color(0xFFB42318),
        AnnouncementType.warning => const Color(0xFF945900),
        AnnouncementType.service => const Color(0xFF187447),
        AnnouncementType.event ||
        AnnouncementType.info =>
          const Color(0xFF002E6D),
      };
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AnnouncementNotice(
            announcement: Announcement(
          id: 'test',
          title: 'Aviso de la sede',
          body: 'Consulta la entrada principal.',
          type: type,
          zoneNodeIds: const [],
          createdAt: DateTime(2026),
        )),
      ))));
      expect(
          tester
              .widget<Container>(find.descendant(
                  of: find.byType(AnnouncementNotice),
                  matching: find.byType(Container)))
              .decoration,
          isA<BoxDecoration>().having((d) => d.color, 'background', expected));
      expect(find.text('Aviso de la sede'), findsOneWidget);
      expect(find.text('Consulta la entrada principal.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    for (final tone in NoticeTone.values) {
      testWidgets('Readable ${tone.name} notice in dark=$dark with large text',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final key = GlobalKey<ScaffoldMessengerState>();
        await tester.pumpWidget(MaterialApp(
          theme: container.read(dark ? darkThemeProvider : lightThemeProvider),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: MapNoticeScope(
              messengerKey: key,
              child: const Scaffold(body: SizedBox.expand())),
        ));
        key.currentState!.showSnackBar(MapNotice(
            tone: tone, content: const Text('Cambio confirmado en el mapa')));
        await tester.pumpAndSettle();
        final notice = tester.widget<SnackBar>(find.byType(SnackBar));
        final expected = switch (tone) {
          NoticeTone.success => const Color(0xFF187447),
          NoticeTone.deletion || NoticeTone.error => const Color(0xFFB42318),
          NoticeTone.warning => const Color(0xFF945900),
          NoticeTone.info => const Color(0xFF002E6D),
        };
        expect(notice.backgroundColor, expected);
        expect(find.byIcon(tone.icon), findsOneWidget);
        final color = DefaultTextStyle.of(
                tester.element(find.text('Cambio confirmado en el mapa')))
            .style
            .color!;
        final luminance = expected.computeLuminance();
        expect(color, Colors.white);
        expect(1.05 / (luminance + .05), greaterThanOrEqualTo(4.5));
        final textRect =
            tester.getRect(find.text('Cambio confirmado en el mapa'));
        expect(textRect.top, greaterThanOrEqualTo(0));
        expect(textRect.bottom, lessThan(800));
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Cambio confirmado en el mapa'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
