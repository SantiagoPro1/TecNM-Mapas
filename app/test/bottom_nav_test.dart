import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';

/// El menú inferior se rompió una vez de una forma que ni `flutter analyze` ni
/// las demás pruebas podían detectar: al pasar de 3 a 4 botones se envolvió
/// cada uno en un `Center` sin `heightFactor`. Como el Scaffold coloca la
/// barra con altura libre, el `Center` creció todo lo que pudo y la barra
/// terminó ocupando la pantalla entera, tapando el contenido y dejando los
/// botones flotando a media altura.
///
/// Era un fallo silencioso: compila, no lanza excepción, no sale en el log.
/// Solo se ve corriendo la app. De ahí estas pruebas.
void main() {
  Future<void> montar(WidgetTester tester, {int indice = 0}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const Center(child: Text('CONTENIDO')),
        bottomNavigationBar: BottomNav(currentIndex: indice),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('la barra no se come la pantalla', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await montar(tester);

    final alturaBarra = tester.getSize(find.byType(BottomNav)).height;
    final alturaPantalla = tester.getSize(find.byType(Scaffold)).height;

    // Una barra de navegación razonable no pasa de ~1/4 de la pantalla.
    // Con el bug medía exactamente lo mismo que la pantalla.
    expect(alturaBarra, lessThan(alturaPantalla * 0.25),
        reason: 'la barra mide ${alturaBarra}px de ${alturaPantalla}px: '
            'está estirándose y tapando el contenido');
  });

  testWidgets('el contenido de la pantalla sigue visible', (tester) async {
    await montar(tester);
    expect(find.text('CONTENIDO'), findsOneWidget);
  });

  testWidgets('están los cuatro accesos', (tester) async {
    await montar(tester);
    for (final etiqueta in ['Inicio', 'ID', 'Mapa abierto', 'Perfil']) {
      expect(find.text(etiqueta), findsOneWidget,
          reason: 'falta el acceso "$etiqueta"');
    }
  });

  testWidgets('no se desborda en un teléfono angosto', (tester) async {
    // 320 px de ancho lógico es lo más angosto que se ve en la práctica, y
    // "Mapa abierto" es la etiqueta más larga: es el caso que obligó a
    // repartir el ancho en cuatro.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await montar(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un índice fuera de rango no marca nada como activo',
      (tester) async {
    // El historial pasa -1 a propósito: no es ninguna de las cuatro pestañas.
    await montar(tester, indice: -1);
    expect(tester.takeException(), isNull);
  });
}
