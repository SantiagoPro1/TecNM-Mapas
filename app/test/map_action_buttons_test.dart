import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/presentation/screens/map/map_action_buttons.dart';
import 'package:navia/presentation/screens/map/map_notice_scope.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';

void main() {
  for (final height in [640.0, 800.0]) {
    for (final admin in [false, true]) {
      testWidgets('Map notice is visible at height $height (admin=$admin)',
          (tester) async {
        tester.view.physicalSize = Size(360, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final messenger = GlobalKey<ScaffoldMessengerState>();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              snackBarTheme:
                  const SnackBarThemeData(behavior: SnackBarBehavior.floating)),
          home: MapNoticeScope(
            messengerKey: messenger,
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: const BottomNav(currentIndex: 3),
              floatingActionButton: MapActionButtons(children: [
                if (admin) ...[
                  FloatingActionButton(
                      heroTag: 'edit',
                      onPressed: () {},
                      child: const Icon(Icons.edit)),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton(
                    heroTag: 'center',
                    onPressed: () {},
                    child: const Icon(Icons.my_location)),
              ]),
            ),
          ),
        ));
        messenger.currentState!
            .showSnackBar(const SnackBar(content: Text('Punto agregado')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final notice = tester.getRect(find.byType(SnackBar));
        expect(notice.top, greaterThanOrEqualTo(0));
        expect(notice.bottom,
            lessThanOrEqualTo(tester.getTopLeft(find.byType(BottomNav)).dy));
        expect(tester.getSize(find.byType(MapActionButtons)).height,
            lessThan(160));
      });
    }
  }
}
