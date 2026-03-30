import 'package:flutter_test/flutter_test.dart';
import 'package:sinait/main.dart';

void main() {
  testWidgets('SINAIT app carga correctamente', (WidgetTester tester) async {
    await tester.pumpWidget(const SinaitApp());

    expect(find.text('SINAIT'), findsOneWidget);
    expect(find.text('Iniciar navegación'), findsOneWidget);
  });
}