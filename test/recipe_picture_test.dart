import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lovehub/models/recipe_model.dart';
import 'package:lovehub/recipe_import/recipe_picture.dart';
import 'package:lovehub/repositories/recipe_repository.dart';

class FakeImageStore implements RecipeImageStore {
  final objects = <String, Uint8List>{};
  final deleted = <String>[];
  bool failUpload = false;

  @override
  Future<String> upload(String path, Uint8List jpegBytes) async {
    if (failUpload) throw Exception('storage/unauthorized');
    objects[path] = jpegBytes;
    return 'https://storage.example/${Uri.encodeComponent(path)}?alt=media';
  }

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    objects.remove(path);
  }
}

Uint8List pngBytes(int width, int height, {bool transparent = false}) {
  final image = img.Image(
    width: width,
    height: height,
    numChannels: transparent ? 4 : 3,
  );
  img.fill(
    image,
    color: transparent
        ? img.ColorRgba8(0, 0, 0, 0)
        : img.ColorRgb8(200, 30, 30),
  );
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('prepareRecipeImage', () {
    test('shrinks a big picture to 1200px on the long side as JPEG', () {
      final out = prepareRecipeImage(pngBytes(3000, 2000));
      expect(out.sublist(0, 3), [0xff, 0xd8, 0xff]);
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 1200);
      expect(decoded.height, 800);
    });

    test('portrait pictures are capped by height', () {
      final decoded = img.decodeJpg(prepareRecipeImage(pngBytes(900, 2400)))!;
      expect(decoded.height, 1200);
      expect(decoded.width, 450);
    });

    test('keeps a small picture its size', () {
      final decoded = img.decodeJpg(prepareRecipeImage(pngBytes(640, 480)))!;
      expect([decoded.width, decoded.height], [640, 480]);
    });

    test('transparent areas become white, not black', () {
      final decoded = img.decodeJpg(
        prepareRecipeImage(pngBytes(50, 50, transparent: true)),
      )!;
      final pixel = decoded.getPixel(25, 25);
      expect(pixel.r, greaterThan(240));
      expect(pixel.g, greaterThan(240));
      expect(pixel.b, greaterThan(240));
    });

    test('refuses something that is not a picture', () {
      expect(
        () => prepareRecipeImage(Uint8List.fromList('<html>'.codeUnits)),
        throwsA(isA<RecipePictureException>()),
      );
      expect(
        () => prepareRecipeImage(Uint8List(0)),
        throwsA(isA<RecipePictureException>()),
      );
    });
  });

  test('storage path is under the hub and recipe', () {
    expect(
      recipeImageStoragePath(
        'hub1',
        'r1',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
      'hubs/hub1/recipes/r1/1700000000000.jpg',
    );
  });

  group('RecipeRepository pictures', () {
    late FakeFirebaseFirestore db;
    late FakeImageStore store;
    late RecipeRepository repo;
    final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 3]);

    setUp(() {
      db = FakeFirebaseFirestore();
      store = FakeImageStore();
      repo = RecipeRepository(db: db, images: store);
    });

    Future<Recipe> only() async {
      final docs = await db.collection('hubs/test-hub/recipes').get();
      expect(docs.docs, hasLength(1));
      return Recipe.fromFirestore(docs.docs.single);
    }

    test('create with a picture stores imagePath and imageUrl', () async {
      await repo.createRecipe(
        'test-hub',
        title: 'Rice',
        ingredients: ['rice'],
        method: '1. Cook.',
        sourceUrl: 'https://example.com/r',
        imageJpeg: jpeg,
      );
      final recipe = await only();
      expect(
        recipe.imagePath,
        startsWith('hubs/test-hub/recipes/${recipe.id}/'),
      );
      expect(recipe.imagePath, endsWith('.jpg'));
      expect(recipe.imageUrl, startsWith('https://storage.example/'));
      expect(store.objects.keys, [recipe.imagePath]);
      expect(recipe.sourceUrl, 'https://example.com/r');
    });

    test('create without a picture keeps the placeholder', () async {
      await repo.createRecipe(
        'test-hub',
        title: 'Rice',
        ingredients: const [],
        method: '',
      );
      final recipe = await only();
      expect(recipe.imageUrl, isNull);
      expect(recipe.imagePath, isNull);
      expect(store.objects, isEmpty);
    });

    test('a failed upload saves nothing', () async {
      store.failUpload = true;
      await expectLater(
        repo.createRecipe(
          'test-hub',
          title: 'Rice',
          ingredients: const [],
          method: '',
          imageJpeg: jpeg,
        ),
        throwsException,
      );
      final docs = await db.collection('hubs/test-hub/recipes').get();
      expect(docs.docs, isEmpty);
    });

    test('replace uploads the new picture and deletes the old one', () async {
      await repo.createRecipe(
        'test-hub',
        title: 'Rice',
        ingredients: const [],
        method: '',
        imageJpeg: jpeg,
      );
      final before = await only();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await repo.updateRecipe(
        'test-hub',
        before,
        title: 'Rice 2',
        ingredients: const ['rice'],
        method: '1. Cook.',
        picture: ReplaceRecipePicture(
          Uint8List.fromList([0xff, 0xd8, 0xff, 9]),
        ),
      );
      final after = await only();
      expect(after.title, 'Rice 2');
      expect(after.imagePath, isNot(before.imagePath));
      expect(store.deleted, [before.imagePath]);
      expect(store.objects.keys, [after.imagePath]);
    });

    test('remove clears the fields and deletes the object', () async {
      await repo.createRecipe(
        'test-hub',
        title: 'Rice',
        ingredients: const [],
        method: '',
        imageJpeg: jpeg,
      );
      final before = await only();
      await repo.updateRecipe(
        'test-hub',
        before,
        title: 'Rice',
        ingredients: const [],
        method: '',
        picture: const RemoveRecipePicture(),
      );
      final after = await only();
      expect(after.imageUrl, isNull);
      expect(after.imagePath, isNull);
      expect(store.deleted, [before.imagePath]);
    });

    test('keep leaves the picture alone', () async {
      await repo.createRecipe(
        'test-hub',
        title: 'Rice',
        ingredients: const [],
        method: '',
        imageJpeg: jpeg,
      );
      final before = await only();
      await repo.updateRecipe(
        'test-hub',
        before,
        title: 'Rice!',
        ingredients: const [],
        method: '',
      );
      final after = await only();
      expect(after.imageUrl, before.imageUrl);
      expect(store.deleted, isEmpty);
    });

    test('deleting a recipe deletes its picture', () async {
      await repo.createRecipe(
        'test-hub',
        title: 'Rice',
        ingredients: const [],
        method: '',
        imageJpeg: jpeg,
      );
      final recipe = await only();
      await repo.deleteRecipe('test-hub', recipe);
      final docs = await db.collection('hubs/test-hub/recipes').get();
      expect(docs.docs, isEmpty);
      expect(store.deleted, [recipe.imagePath]);
      expect(store.objects, isEmpty);
    });

    test('never deletes a path outside recipe pictures', () async {
      await db.collection('hubs/test-hub/recipes').doc('x').set({
        'title': 'Odd',
        'ingredients': <String>[],
        'imagePath': 'hubs/test-hub/photos/gallery.jpg',
        'imageUrl': 'https://storage.example/gallery',
      });
      await repo.deleteRecipe('test-hub', await only());
      expect(store.deleted, isEmpty);
    });
  });
}
