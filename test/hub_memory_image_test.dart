import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/hub_memory_image.dart';

void main() {
  const url =
      'https://firebasestorage.googleapis.com/v0/b/lovehub-26107.firebasestorage.app/o/hubs%2Fhome%2Fphotos%2Fa.jpg?alt=media&token=abc';

  test('provider keeps the download url and does not force an xhr fetch', () {
    final provider = hubMemoryImageProvider(url);
    expect(provider.url, url);
    expect(provider.headers, isNull);
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.prefer);
    expect(provider, hubMemoryImageProvider(url));
    expect(provider.url.contains('functions'), isFalse);
    expect(provider.url.contains('proxy'), isFalse);
  });

  test('load gate reports one failure per url until the url changes', () {
    final gate = HubMemoryLoadGate();
    expect(gate.claim(url), isTrue);
    expect(gate.claim(url), isFalse);
    expect(gate.claim('https://photos.example/other.jpg'), isTrue);
    gate.reset();
    expect(gate.claim(url), isTrue);
  });

  testWidgets('memory image uses that provider without adding headers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HubMemoryImage(url: url, errorBuilder: _quietError),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, url);
    expect(provider.headers, isNull);
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.prefer);
  });
}

Widget _quietError(BuildContext context, Object error, StackTrace? stack) {
  return const SizedBox.shrink();
}
