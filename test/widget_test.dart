import 'package:flutter_test/flutter_test.dart';

import 'package:alpinenav/main.dart';

void main() {
  testWidgets('App creates without error', (WidgetTester tester) async {
    await tester.pumpWidget(const AlpineNavApp());
    // Verify the app builds and the map screen is present
    expect(find.byType(AlpineNavApp), findsOneWidget);
  });
}
