import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/memory_photos.dart';

const _pathA = 'hubs/home/photos/a.jpg';
const _urlA =
    'https://firebasestorage.googleapis.com/v0/b/lovehub-26107.firebasestorage.app/o/a?alt=media&token=old';
const _urlAFresh =
    'https://firebasestorage.googleapis.com/v0/b/lovehub-26107.firebasestorage.app/o/a?alt=media&token=new';

MemoryPhoto _photo(int index, {String? path}) {
  return MemoryPhoto(
    id: '$index',
    url: 'https://photos.example/$index.jpg',
    storagePath: path ?? 'hubs/home/photos/$index.jpg',
  );
}

void main() {
  test('snapshot rows keep urls and leave non-strings off the path', () {
    final photos = memoryPhotosFromDocs(const [
      (
        id: '1',
        data: {'url': ' https://photos.example/a.jpg ', 'storagePath': _pathA},
      ),
      (id: '2', data: {'url': '', 'storagePath': 'hubs/home/photos/b.jpg'}),
      (id: '3', data: {'storagePath': 'hubs/home/photos/c.jpg'}),
      (
        id: '4',
        data: {'url': 'https://photos.example/d.jpg', 'storagePath': 12},
      ),
      (id: '5', data: {'url': 'https://lh3.googleusercontent.com/a.jpg'}),
    ]);

    expect(photos.map((photo) => photo.id), ['1', '4', '5']);
    expect(photos[0].url, 'https://photos.example/a.jpg');
    expect(photos[0].storagePath, _pathA);
    expect(photos[1].storagePath, isNull);
    expect(photos[2].storagePath, isNull);
  });

  test('only an uploaded hub photo path can be refreshed', () {
    expect(
      canonicalHubPhotoStoragePath('hubs/home/photos/171000_1_uid.jpg'),
      'hubs/home/photos/171000_1_uid.jpg',
    );
    expect(
      canonicalHubPhotoStoragePath('hubs/home/photos/../../secret'),
      isNull,
    );
    expect(canonicalHubPhotoStoragePath('https://evil.example/proxy'), isNull);
    expect(canonicalHubPhotoStoragePath('/hubs/home/photos/a.jpg'), isNull);
    expect(canonicalHubPhotoStoragePath('users/uid/photo.jpg'), isNull);
  });

  test('rotation commits the new photo before rebuild', () {
    final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
    deck.setPhotos([_photo(0), _photo(1)]);
    expect(deck.currentUrl, 'https://photos.example/0.jpg');

    String? painted;
    commitMemoryRotation(
      advance: deck.advance,
      evict: (_) {},
      rebuild: () {
        painted = deck.currentUrl;
      },
    );

    expect(painted, 'https://photos.example/1.jpg');
    expect(deck.currentUrl, painted);
  });

  test('a failed photo is evicted only when it is shown again', () {
    final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
    const first = 'https://photos.example/0.jpg';
    const second = 'https://photos.example/1.jpg';
    deck.setPhotos([
      const MemoryPhoto(id: '0', url: first),
      const MemoryPhoto(id: '1', url: second),
    ]);

    expect(deck.onFailed(first), isA<MemoryPhotoShow>());
    expect(deck.currentUrl, second);

    final evicted = <String>[];
    String? painted;
    commitMemoryRotation(
      advance: deck.advance,
      evict: evicted.add,
      rebuild: () => painted = deck.currentUrl,
    );

    expect(painted, first);
    expect(evicted, [first]);

    commitMemoryRotation(
      advance: deck.advance,
      evict: evicted.add,
      rebuild: () {},
    );
    expect(evicted, [first]);
  });

  test(
    'repeated failures stop without walking the album or re-reading',
    () async {
      var reads = 0;
      var changes = 0;
      final seen = <String>{};
      final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
      deck.setPhotos([for (var i = 0; i < 8; i++) _photo(i)]);

      for (var n = 0; n < 20; n++) {
        final current = deck.currentUrl;
        expect(current, isNotNull);
        seen.add(current!);
        await recoverMemoryPhoto(
          deck: deck,
          failedUrl: current,
          refreshDownloadUrl: (_) async {
            reads++;
            return null;
          },
          evict: (_) {},
          onChanged: () => changes++,
        );
        if (deck.holdingError) break;
      }

      expect(deck.holdingError, isTrue);
      expect(seen.length, lessThanOrEqualTo(4));
      expect(changes, lessThanOrEqualTo(4));
      expect(reads, 1);
      expect(deck.refreshedPathCount, 1);

      final stuck = deck.currentUrl;
      await recoverMemoryPhoto(
        deck: deck,
        failedUrl: stuck!,
        refreshDownloadUrl: (_) async {
          reads++;
          return 'https://photos.example/should-not.jpg';
        },
        evict: (_) {},
        onChanged: () => changes++,
      );
      expect(deck.currentUrl, stuck);
      expect(deck.holdingError, isTrue);
      expect(reads, 1);
      expect(changes, lessThanOrEqualTo(4));
    },
  );

  test('a download url is refreshed once and kept across snapshots', () async {
    var reads = 0;
    final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
    deck.setPhotos([
      const MemoryPhoto(id: '1', url: _urlA, storagePath: _pathA),
    ]);

    await recoverMemoryPhoto(
      deck: deck,
      failedUrl: _urlA,
      refreshDownloadUrl: (path) async {
        reads++;
        expect(path, _pathA);
        return _urlAFresh;
      },
      evict: (_) {},
      onChanged: () {},
    );

    expect(reads, 1);
    expect(deck.currentUrl, _urlAFresh);
    expect(deck.holdingError, isFalse);

    deck.setPhotos([
      const MemoryPhoto(id: '1', url: _urlA, storagePath: _pathA),
    ]);
    expect(deck.currentUrl, _urlAFresh);

    await recoverMemoryPhoto(
      deck: deck,
      failedUrl: deck.currentUrl!,
      refreshDownloadUrl: (_) async {
        reads++;
        return 'https://photos.example/again.jpg';
      },
      evict: (_) {},
      onChanged: () {},
    );
    expect(reads, 1);
    expect(deck.holdingError, isTrue);
  });

  test('a hung download-url read is abandoned once', () async {
    var reads = 0;
    final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
    deck.setPhotos(const [
      MemoryPhoto(id: '1', url: _urlA, storagePath: _pathA),
      MemoryPhoto(id: '2', url: 'https://photos.example/b.jpg'),
    ]);

    await recoverMemoryPhoto(
      deck: deck,
      failedUrl: _urlA,
      refreshTimeout: const Duration(milliseconds: 30),
      refreshDownloadUrl: (_) async {
        reads++;
        await Completer<String?>().future;
        return 'https://photos.example/late.jpg';
      },
      evict: (_) {},
      onChanged: () {},
    );

    expect(reads, 1);
    expect(deck.currentUrl, 'https://photos.example/b.jpg');
    expect(deck.holdingError, isFalse);

    await recoverMemoryPhoto(
      deck: deck,
      failedUrl: deck.currentUrl!,
      refreshDownloadUrl: (_) async {
        reads++;
        return 'https://photos.example/should-not.jpg';
      },
      evict: (_) {},
      onChanged: () {},
    );
    expect(reads, 1);
    expect(deck.holdingError, isTrue);
  });

  test('a replaced server url wins and a foreign path is never read', () async {
    var reads = 0;
    final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
    deck.setPhotos([
      const MemoryPhoto(id: '1', url: _urlA, storagePath: _pathA),
      const MemoryPhoto(
        id: '2',
        url: 'https://photos.example/proxy.jpg',
        storagePath: 'https://evil.example/proxy',
      ),
    ]);

    await recoverMemoryPhoto(
      deck: deck,
      failedUrl: _urlA,
      refreshDownloadUrl: (_) async {
        reads++;
        return _urlAFresh;
      },
      evict: (_) {},
      onChanged: () {},
    );
    expect(deck.currentUrl, _urlAFresh);

    const replaced = 'https://photos.example/replaced.jpg';
    deck.setPhotos([
      const MemoryPhoto(id: '1', url: replaced, storagePath: _pathA),
    ]);
    expect(deck.currentUrl, replaced);
    expect(deck.refreshedPathCount, 0);

    // The replacement is a new stored URL. This turn already used its one
    // Storage read, so a failure here waits for the next rotation.
    await recoverMemoryPhoto(
      deck: deck,
      failedUrl: replaced,
      refreshDownloadUrl: (_) async {
        reads++;
        return null;
      },
      evict: (_) {},
      onChanged: () {},
    );
    expect(reads, 1);
    expect(deck.holdingError, isTrue);

    deck.advance();
    await recoverMemoryPhoto(
      deck: deck,
      failedUrl: deck.currentUrl!,
      refreshDownloadUrl: (path) async {
        reads++;
        expect(path, _pathA);
        return null;
      },
      evict: (_) {},
      onChanged: () {},
    );
    expect(reads, 2);

    final foreign = MemoryPhotoDeck(pickIndex: (_) => 0);
    foreign.setPhotos(const [
      MemoryPhoto(
        id: '9',
        url: 'https://photos.example/a.jpg',
        storagePath: 'hubs/home/photos/../../secret',
      ),
    ]);
    await recoverMemoryPhoto(
      deck: foreign,
      failedUrl: foreign.currentUrl!,
      refreshDownloadUrl: (_) async {
        reads++;
        return 'https://photos.example/nope.jpg';
      },
      evict: (_) {},
      onChanged: () {},
    );
    expect(reads, 2);
    expect(foreign.holdingError, isTrue);
  });

  test(
    'overlapping reports and a late refresh do not spin or clobber',
    () async {
      var reads = 0;
      var changes = 0;
      final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
      const other = 'https://photos.example/b.jpg';
      deck.setPhotos(const [
        MemoryPhoto(id: '1', url: _urlA, storagePath: _pathA),
        MemoryPhoto(id: '2', url: other),
      ]);

      final gate = Completer<void>();
      final first = recoverMemoryPhoto(
        deck: deck,
        failedUrl: _urlA,
        refreshDownloadUrl: (path) async {
          reads++;
          expect(path, _pathA);
          await gate.future;
          return _urlAFresh;
        },
        evict: (_) {},
        onChanged: () => changes++,
      );
      final second = recoverMemoryPhoto(
        deck: deck,
        failedUrl: _urlA,
        refreshDownloadUrl: (_) async {
          reads++;
          return 'https://photos.example/should-not.jpg';
        },
        evict: (_) {},
        onChanged: () => changes++,
      );
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);

      deck.advance();
      expect(deck.currentUrl, other);
      gate.complete();
      await Future.wait([first, second]);

      expect(reads, 1);
      expect(changes, 0);
      expect(deck.currentUrl, other);

      deck.setPhotos(const [
        MemoryPhoto(id: '1', url: _urlA, storagePath: _pathA),
        MemoryPhoto(id: '2', url: other),
      ]);
      deck.advance();
      if (deck.currentUrl == _urlAFresh) {
        await recoverMemoryPhoto(
          deck: deck,
          failedUrl: deck.currentUrl!,
          refreshDownloadUrl: (_) async {
            reads++;
            return 'https://photos.example/third.jpg';
          },
          evict: (_) {},
          onChanged: () {},
        );
      }
      expect(reads, 1);
    },
  );

  test(
    'the following rotation retries one photo and does not re-read it',
    () async {
      var reads = 0;
      final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
      deck.setPhotos([for (var i = 0; i < 5; i++) _photo(i)]);

      Future<void> failCurrent() {
        return recoverMemoryPhoto(
          deck: deck,
          failedUrl: deck.currentUrl!,
          refreshDownloadUrl: (_) async {
            reads++;
            return null;
          },
          evict: (_) {},
          onChanged: () {},
        );
      }

      for (var i = 0; i < 10 && !deck.holdingError; i++) {
        await failCurrent();
      }
      expect(deck.holdingError, isTrue);
      expect(reads, 1);

      final evict = deck.advance();
      expect(deck.holdingError, isFalse);
      expect(evict, 'https://photos.example/0.jpg');

      for (var i = 0; i < 10 && !deck.holdingError; i++) {
        await failCurrent();
      }
      expect(deck.holdingError, isTrue);
      expect(reads, 2);
      expect(deck.refreshedPathCount, 2);
    },
  );

  test(
    'a snapshot does not clear a held error or rotate the current photo',
    () {
      final deck = MemoryPhotoDeck(pickIndex: (_) => 0);
      final photos = [
        for (var i = 0; i < 4; i++)
          MemoryPhoto(id: '$i', url: 'https://photos.example/$i.jpg'),
      ];
      deck.setPhotos(photos);
      final first = deck.currentUrl;
      deck.setPhotos(photos);
      expect(deck.currentUrl, first);

      deck.onFailed(first!);
      deck.onFailed(deck.currentUrl!);
      deck.onFailed(deck.currentUrl!);
      deck.onFailed(deck.currentUrl!);
      expect(deck.holdingError, isTrue);
      final held = deck.currentUrl;
      deck.setPhotos(photos);
      expect(deck.holdingError, isTrue);
      expect(deck.currentUrl, held);
    },
  );
}
