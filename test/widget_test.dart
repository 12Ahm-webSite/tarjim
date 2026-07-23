import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tarjim/core/constants/app_constants.dart';
import 'package:tarjim/main.dart';

void main() {
  testWidgets('Tarjim home screen launches', (WidgetTester tester) async {
    await tester.pumpWidget(const TarjimApp());

    expect(find.text(AppConstants.appName), findsWidgets);
    expect(find.text(AppConstants.appNameArabic), findsOneWidget);
    expect(find.text('Screen Capture'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Request Permissions'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Request Permissions'), findsOneWidget);
  });
}
