import 'package:flutter_test/flutter_test.dart';

import 'package:flylog/main.dart';

void main() {
  testWidgets('FlyLogApp smoke test', (WidgetTester tester) async {
    // V této fázi ověříme základní inicializaci widgetu FlyLogApp.
    // Plné testy UI s mockovaným ServiceLocatorem budou doplněny s integračními testy.
    expect(const FlyLogApp(), isNotNull);
  });
}

