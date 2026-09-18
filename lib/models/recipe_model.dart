import 'package:cloud_firestore/cloud_firestore.dart';

class Recipe {
  final String id;
  final String title;
  final List<String> ingredients;
  final String? method; // Optional method field

  Recipe({
    required this.id,
    required this.title,
    required this.ingredients,
    this.method,
  });

  // This is the missing method the repository was looking for!
  factory Recipe.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Recipe(
      id: doc.id,
      title: data['title'] ?? '',
      ingredients: List<String>.from(data['ingredients'] ?? []),
      method: data['method'], // Loads the method from the database
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'ingredients': ingredients,
      'method': method, // Saves the method to the database
    };
  }
}
