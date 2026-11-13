import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/recipe_model.dart';
import '../recipe_import/recipe_picture.dart';
import '../services/hub_collection.dart';

/// Where recipe pictures live. Swappable in tests.
abstract class RecipeImageStore {
  /// Uploads a JPEG and returns its download URL.
  Future<String> upload(String path, Uint8List jpegBytes);

  Future<void> delete(String path);
}

class FirebaseRecipeImageStore implements RecipeImageStore {
  FirebaseRecipeImageStore([FirebaseStorage? storage]) : _storage = storage;
  final FirebaseStorage? _storage;

  FirebaseStorage get _s => _storage ?? FirebaseStorage.instance;

  @override
  Future<String> upload(String path, Uint8List jpegBytes) async {
    final ref = _s.ref(path);
    await ref.putData(
      jpegBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000',
      ),
    );
    return ref.getDownloadURL();
  }

  @override
  Future<void> delete(String path) => _s.ref(path).delete();
}

class RecipeRepository {
  RecipeRepository({FirebaseFirestore? db, RecipeImageStore? images})
    : _dbOverride = db,
      _images = images ?? FirebaseRecipeImageStore();

  final FirebaseFirestore? _dbOverride;
  final RecipeImageStore _images;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _recipes(String hubId) =>
      _db.collection(kHubsCollection).doc(hubId).collection('recipes');

  Stream<List<Recipe>> streamRecipes(String hubId) {
    return _recipes(hubId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList(),
        );
  }

  Future<void> addRecipe(String hubId, Recipe recipe) async {
    await _recipes(hubId).add(recipe.toMap());
  }

  /// New cookbook entry. [createdAt] matches the manual recipe form.
  /// [imageJpeg] (already resized) is uploaded first, then the recipe is
  /// written with `imagePath` and `imageUrl`. If the write fails the
  /// uploaded picture is removed again.
  Future<void> createRecipe(
    String hubId, {
    required String title,
    required List<String> ingredients,
    required String method,
    String? sourceUrl,
    Uint8List? imageJpeg,
  }) async {
    final doc = _recipes(hubId).doc();
    final data = <String, dynamic>{
      'title': title,
      'ingredients': ingredients,
      'method': method,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final source = sourceUrl?.trim();
    if (source != null && source.isNotEmpty) {
      data['sourceUrl'] = source;
    }
    String? uploadedPath;
    if (imageJpeg != null && imageJpeg.isNotEmpty) {
      uploadedPath = recipeImageStoragePath(hubId, doc.id);
      data['imageUrl'] = await _images.upload(uploadedPath, imageJpeg);
      data['imagePath'] = uploadedPath;
    }
    try {
      await doc.set(data);
    } catch (_) {
      if (uploadedPath != null) await _deleteQuietly(uploadedPath);
      rethrow;
    }
  }

  /// Saves edits to [existing]. A replaced or removed picture's old Storage
  /// object is deleted after the recipe is updated.
  Future<void> updateRecipe(
    String hubId,
    Recipe existing, {
    required String title,
    required List<String> ingredients,
    required String method,
    RecipePictureChange picture = const KeepRecipePicture(),
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'ingredients': ingredients,
      'method': method,
    };
    String? uploadedPath;
    switch (picture) {
      case KeepRecipePicture():
        break;
      case RemoveRecipePicture():
        data['imageUrl'] = FieldValue.delete();
        data['imagePath'] = FieldValue.delete();
      case ReplaceRecipePicture(:final jpegBytes):
        uploadedPath = recipeImageStoragePath(hubId, existing.id);
        data['imageUrl'] = await _images.upload(uploadedPath, jpegBytes);
        data['imagePath'] = uploadedPath;
    }
    try {
      await _recipes(hubId).doc(existing.id).update(data);
    } catch (_) {
      if (uploadedPath != null) await _deleteQuietly(uploadedPath);
      rethrow;
    }
    final oldPath = existing.imagePath;
    if (picture is! KeepRecipePicture &&
        oldPath != null &&
        oldPath != uploadedPath) {
      await _deleteQuietly(oldPath);
    }
  }

  /// Deletes the recipe, then its picture if it has one.
  Future<void> deleteRecipe(String hubId, Recipe recipe) async {
    await _recipes(hubId).doc(recipe.id).delete();
    final path = recipe.imagePath;
    if (path != null) await _deleteQuietly(path);
  }

  Future<void> _deleteQuietly(String path) async {
    // Only ever delete our own recipe pictures.
    if (!path.startsWith('hubs/') || !path.contains('/recipes/')) return;
    try {
      await _images.delete(path);
    } catch (_) {
      debugPrint('Recipe picture cleanup failed');
    }
  }
}
