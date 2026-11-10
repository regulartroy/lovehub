import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/recipe_model.dart';

class RecipeRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Recipe>> streamRecipes(String hubId) {
    return _db
        .collection('hubs')
        .doc(hubId)
        .collection('recipes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList(),
        );
  }

  Future<void> addRecipe(String hubId, Recipe recipe) async {
    await _db
        .collection('hubs')
        .doc(hubId)
        .collection('recipes')
        .add(recipe.toMap());
  }

  /// New cookbook entry. [createdAt] matches the manual recipe form.
  Future<void> createRecipe(
    String hubId, {
    required String title,
    required List<String> ingredients,
    required String method,
    String? sourceUrl,
  }) async {
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
    await _db.collection('hubs').doc(hubId).collection('recipes').add(data);
  }
}
