import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lovehub/main.dart';

void main() {
  testWidgets('login screen shows the logo, name, and sign-in button', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Lovehub'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
