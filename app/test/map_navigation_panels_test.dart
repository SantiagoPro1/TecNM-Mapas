import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/nav_route.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/presentation/screens/map/map_navigation_panels.dart';
import 'package:navia/presentation/screens/map/map_overlay_panel.dart';

void main() {
  const destination = CampusNode(
      id: 'test',
      zoneId: 'campus',
      name:
          'Edificio de Investigacion y Estudios de Posgrado, acceso principal',
      aliases: [],
      type: NodeType.building,
      lat: 19,
      lng: -103,
      floor: 0,
      accessible: true,
      description: '');
  const step = RouteStep(
      node: destination,
      distanceMeters: 12345,
      title: 'Gira ligeramente a la derecha hacia el acceso principal',
      voiceInstruction:
          'Continua hasta el edificio de investigacion por el camino accesible.');
  const route = NavRoute(
      steps: [step],
      totalDistance: 12345,
      estimatedMinutes: 124,
      fullyAccessible: true,
      origin: destination,
      destination: destination);
  for (final width in [320.0, 360.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Navigation panels fit at width $width and scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
            body: MapOverlayPanel(
                child: MapNavigationHeader(
                    step: step, onRepeatVoice: () {}, onCancel: () {})),
            bottomNavigationBar: MapBottomPanel(
                child: MapNavigationSummary(
                    navState: const NavigationState(
                        status: NavStatus.navigating, activeRoute: route),
                    route: route,
                    onPrevious: () {},
                    onNext: () {},
                    onCancel: () {})),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
