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
}
