import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/navigation/app_navigation.dart';
import 'package:navia/core/navigation/app_back_scope.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';

class _Screen extends StatefulWidget {
  final int index;
  final VoidCallback onCreate;
  const _Screen(this.index, this.onCreate);
  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ElevatedButton(
            onPressed: () => AppNavigation.push(context, AppRoutes.settings),
            child: const Text('Ajustes')),
        bottomNavigationBar: BottomNav(currentIndex: widget.index),
      );
}

VoidCallback navTap(WidgetTester tester, String label) => tester
    .widget<GestureDetector>(find
        .ancestor(
            of: find.text(label).last, matching: find.byType(GestureDetector))
        .first)
    .onTap!;

void main() {
  Future<void> mount(WidgetTester tester, Map<String, int> created) async {
    Widget screen(String route, int index) => AppBackScope(
        child: _Screen(index,
            () => created.update(route, (n) => n + 1, ifAbsent: () => 1)));
    await tester.pumpWidget(MaterialApp(initialRoute: AppRoutes.home, routes: {
      AppRoutes.home: (_) => screen(AppRoutes.home, 0),
      AppRoutes.credential: (_) => screen(AppRoutes.credential, 1),
      AppRoutes.profile: (_) => screen(AppRoutes.profile, 2),
      AppRoutes.openMap: (_) => screen(AppRoutes.openMap, 3),
      AppRoutes.settings: (_) => screen(AppRoutes.settings, -1),
    }));
    await tester.pumpAndSettle();
  }

  testWidgets('Repeated taps on Inicio do not reload Home', (tester) async {
    final created = <String, int>{};
    await mount(tester, created);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Inicio'));
    }
    await tester.pumpAndSettle();
    expect(created[AppRoutes.home], 1);
  });
  testWidgets('Rapid taps open one route and block taps during transition',
      (tester) async {
    final created = <String, int>{};
    await mount(tester, created);
    final idTap = navTap(tester, 'ID');
    final profileTap = navTap(tester, 'Perfil');
    idTap();
    idTap();
    profileTap();
    await tester.pump(const Duration(milliseconds: 50));
    navTap(tester, 'Perfil')();
    await tester.pumpAndSettle();
    expect(created[AppRoutes.credential], 1);
    expect(created[AppRoutes.profile], isNull);
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(created[AppRoutes.profile], 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Repeated taps on Ajustes do not stack duplicate screens',
      (tester) async {
    final created = <String, int>{};
    await mount(tester, created);
    final openSettings =
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed!;
    openSettings();
    openSettings();
    await tester.pumpAndSettle();
    expect(created[AppRoutes.settings], 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('System Back walks history and stays at Home', (tester) async {
    final created = <String, int>{};
    await mount(tester, created);
    await tester.tap(find.text('ID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 0);
    expect(created[AppRoutes.home], 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Inicio reuses Home and clears intermediate history',
      (tester) async {
    final created = <String, int>{};
    await mount(tester, created);
    await tester.tap(find.text('ID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(created[AppRoutes.home], 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 0);
  });
  testWidgets('Back from a root map goes to Home instead of closing',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(initialRoute: AppRoutes.openMap, routes: {
      AppRoutes.openMap: (_) => AppBackScope(child: _Screen(3, () {})),
      AppRoutes.home: (_) => AppBackScope(child: _Screen(0, () {})),
    }));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 0);
  });
  testWidgets('System Back closes a dialog before changing the screen',
      (tester) async {
    final created = <String, int>{};
    await mount(tester, created);
    showDialog<void>(
        context: tester.element(find.byType(BottomNav)),
        builder: (_) => const AlertDialog(title: Text('Confirmar')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Confirmar'), findsNothing);
    expect(tester.widget<BottomNav>(find.byType(BottomNav)).currentIndex, 0);
    expect(created[AppRoutes.home], 1);
  });
}
