import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/presentation/screens/map/map_action_buttons.dart';
import 'package:navia/presentation/screens/map/map_notice_scope.dart';
import 'package:navia/presentation/screens/map/map_overlay_panel.dart';

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(360, 800),
    const Size(800, 360),
    const Size(1024, 768)
  ]) {
    for (final config in [
      (1.0, false),
      (2.0, false),
      (1.0, true),
      (2.0, true)
    ]) {
      final scale = config.$1;
      final keyboard = config.$2;
      final keyboardHeight =
          keyboard ? (size.height < 480 ? 120.0 : 280.0) : 0.0;
      testWidgets(
          'Ordered panels and visible notice: $size, scale $scale, keyboard $keyboard',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        addTearDown(tester.view.reset);
        final messenger = GlobalKey<ScaffoldMessengerState>();
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: MapNoticeScope(
            messengerKey: messenger,
            child: Scaffold(
              bottomNavigationBar: keyboard
                  ? null
                  : MapBottomPanel(
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Destino de la ruta y tiempo estimado'),
                        for (var i = 0; i < 3; i++) const SizedBox(height: 40),
                        ElevatedButton(
                            onPressed: () {},
                            child: const Text('Detener ruta')),
                      ],
                    )),
              floatingActionButtonLocation: size.height < 480
                  ? FloatingActionButtonLocation.startTop
                  : FloatingActionButtonLocation.endFloat,
              floatingActionButton: keyboard
                  ? null
                  : MapActionButtons(children: [
                      FloatingActionButton(
                          onPressed: () {},
                          child: const Icon(Icons.my_location)),
                    ]),
              body: Stack(children: [
                const SizedBox.expand(),
                Positioned.fill(
                    child: MapOverlayPanel(
                        child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final title in [
                      'Controles',
                      'Modo editor',
                      'Ubicacion manual',
                      'Estado de ruta'
                    ])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(title)))),
                  ],
                ))),
              ]),
            ),
          ),
        ));
        messenger.currentState!
            .showSnackBar(const SnackBar(content: Text('Punto guardado')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final notice = tester.getRect(find
            .descendant(
                of: find.byType(SnackBar), matching: find.byType(Material))
            .first);
        final bottom = keyboard
            ? Rect.fromLTWH(0, size.height - keyboardHeight, size.width, 0)
            : tester.getRect(find.byType(MapBottomPanel));
        final topViewport = tester.getRect(find.descendant(
            of: find.byType(MapOverlayPanel),
            matching: find.byType(SingleChildScrollView)));
        expect(notice.top, greaterThanOrEqualTo(0));
        expect(notice.bottom, lessThanOrEqualTo(bottom.top));
        expect(topViewport.bottom, lessThanOrEqualTo(notice.top + 1));
        expect(topViewport.width, lessThanOrEqualTo(560));
        expect(topViewport.center.dx, closeTo(size.width / 2, 1));
        expect(notice.width, lessThanOrEqualTo(560));
        expect(notice.center.dx, closeTo(size.width / 2, 1));
      });
    }
  }
}
