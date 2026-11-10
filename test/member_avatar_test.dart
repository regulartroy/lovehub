import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/member_avatar.dart';

void main() {
  testWidgets('shows an initial when no photo URL is present', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberAvatar(name: 'Maria', radius: 24),
        ),
      ),
    );

    expect(find.text('M'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows a person icon when asked and photo is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberAvatar(
            name: 'Maria',
            radius: 24,
            icon: Icons.person,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.text('M'), findsNothing);
  });

  testWidgets('builds Image.network for a usable photo URL', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberAvatar(
            name: 'Maria',
            photoURL: 'https://lh3.googleusercontent.com/a/ACg8ocMaria=s96-c',
            radius: 24,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    final provider = image.image as NetworkImage;
    expect(
      provider.url,
      'https://lh3.googleusercontent.com/a/ACg8ocMaria=s96-c',
    );
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.prefer);
    expect(provider.headers, isNull);
  });

  testWidgets('shared heart uses the icon instead of a network image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberAvatar(
            photoURL: 'https://example.com/should-not-load.jpg',
            name: 'Shared',
            radius: 14,
            icon: Icons.favorite_rounded,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
