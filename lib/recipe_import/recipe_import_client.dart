import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'recipe_page_parser.dart';
import 'recipe_url.dart';

const recipeImportRegion = 'europe-west2';
const recipeImportFunction = 'importRecipePage';
const recipeImageFunction = 'fetchRecipeImage';

class RecipeImportException implements Exception {
  RecipeImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class FetchedRecipePage {
  const FetchedRecipePage({
    required this.finalUrl,
    required this.html,
    this.imageUrl,
  });
  final String finalUrl;
  final String html;

  /// Picture the server found on the page, if any.
  final String? imageUrl;
}

/// Fetches a recipe page through the signed-in Cloud Function and parses it.
class RecipeImportClient {
  RecipeImportClient({
    Future<FetchedRecipePage> Function(String url, String hubId)? fetchPage,
    String? Function()? currentUserId,
    Future<Uint8List> Function(String url, String hubId)? fetchImage,
  }) : _fetchPage = fetchPage,
       _currentUserId = currentUserId,
       _fetchImage = fetchImage;

  final Future<Uint8List> Function(String url, String hubId)? _fetchImage;

  final Future<FetchedRecipePage> Function(String url, String hubId)?
  _fetchPage;
  final String? Function()? _currentUserId;

  Future<ParsedRecipe> importUrl({
    required String hubId,
    required String url,
  }) async {
    final String normalised;
    try {
      normalised = validateRecipeImportUrl(url);
    } on RecipeUrlException catch (error) {
      throw RecipeImportException(error.message);
    }

    final uid = (_currentUserId ?? _firebaseUserId)();
    if (uid == null || uid.isEmpty) {
      throw RecipeImportException('Sign in to import a recipe.');
    }
    if (hubId.trim().isEmpty) {
      throw RecipeImportException('Missing hub.');
    }

    final page = await (_fetchPage ?? _firebaseFetch)(normalised, hubId.trim());
    final parsed = parseRecipePage(
      page.html,
      pageUrl: page.finalUrl.isEmpty ? normalised : page.finalUrl,
    );
    final recipe = parsed.recipe;
    if (recipe == null) {
      throw RecipeImportException(
        parsed.error ?? "Couldn't read a recipe from that page.",
      );
    }
    return recipe.withImageUrl(_httpUrlOrNull(page.imageUrl));
  }

  /// Downloads a suggested picture through the server (recipe sites don't
  /// allow the browser to read their images). Returns the original bytes.
  Future<Uint8List> fetchSuggestedImage({
    required String hubId,
    required String url,
  }) async {
    final safe = _httpUrlOrNull(url);
    if (safe == null) {
      throw RecipeImportException("That picture link can't be used.");
    }
    return (_fetchImage ?? _firebaseFetchImage)(safe, hubId.trim());
  }
}

String? _httpUrlOrNull(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  if (uri.host.isEmpty) return null;
  return text;
}

Future<Uint8List> _firebaseFetchImage(String url, String hubId) async {
  final functions = FirebaseFunctions.instanceFor(region: recipeImportRegion);
  final callable = functions.httpsCallable(
    recipeImageFunction,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
  );
  try {
    final result = await callable.call<dynamic>({'url': url, 'hubId': hubId});
    return imageBytesFromCallable(result.data);
  } on FirebaseFunctionsException catch (error) {
    throw RecipeImportException(
      messageForRecipeImportCode(error.code, error.message),
    );
  }
}

Uint8List imageBytesFromCallable(dynamic data) {
  if (data is Map) {
    final encoded = data['base64'];
    if (encoded is String && encoded.isNotEmpty) {
      try {
        return base64Decode(encoded);
      } on FormatException {
        // fall through
      }
    }
  }
  throw RecipeImportException("Couldn't load the suggested picture.");
}

String? _firebaseUserId() => FirebaseAuth.instance.currentUser?.uid;

Future<FetchedRecipePage> _firebaseFetch(String url, String hubId) async {
  final functions = FirebaseFunctions.instanceFor(region: recipeImportRegion);
  final callable = functions.httpsCallable(
    recipeImportFunction,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
  );
  try {
    final result = await callable.call<dynamic>({
      'url': url,
      'hubId': hubId,
    });
    return fetchedPageFromCallable(result.data, fallbackUrl: url);
  } on FirebaseFunctionsException catch (error) {
    throw RecipeImportException(
      messageForRecipeImportCode(error.code, error.message),
    );
  }
}

FetchedRecipePage fetchedPageFromCallable(
  dynamic data, {
  required String fallbackUrl,
}) {
  if (data is! Map) {
    throw RecipeImportException(
      'Recipe import returned an unexpected response.',
    );
  }
  final map = data.map((key, value) => MapEntry(key.toString(), value));
  final html = map['html'];
  final finalUrl = map['finalUrl'];
  final imageUrl = map['imageUrl'];
  if (html is! String || html.trim().isEmpty) {
    throw RecipeImportException(
      "That page didn't include anything we could read.",
    );
  }
  return FetchedRecipePage(
    finalUrl: finalUrl is String && finalUrl.isNotEmpty ? finalUrl : fallbackUrl,
    html: html,
    imageUrl: imageUrl is String && imageUrl.isNotEmpty ? imageUrl : null,
  );
}

String messageForRecipeImportCode(String code, String? message) {
  final text = message?.trim() ?? '';
  switch (code) {
    case 'unauthenticated':
      return 'Sign in to import a recipe.';
    case 'permission-denied':
      return 'You need to be a member of this hub to import a recipe.';
    case 'deadline-exceeded':
      return 'The recipe site took too long to answer.';
    case 'resource-exhausted':
      return text.isEmpty
          ? 'Too many imports. Wait a minute and try again.'
          : text;
    case 'not-found':
      if (text == "Couldn't find that website.") return text;
      return "Recipe import isn't available yet. It needs the importRecipePage function to be deployed.";
    case 'unavailable':
      return text.isEmpty ? "The recipe site couldn't be reached." : text;
    case 'internal':
      if (text.isEmpty || text.toLowerCase() == 'internal') {
        return "Recipe import isn't available right now. If this keeps happening, the import function may not be deployed yet.";
      }
      return text;
    case 'invalid-argument':
    case 'failed-precondition':
      return text.isEmpty ? "Couldn't import that link." : text;
    default:
      return text.isEmpty ? "Couldn't import that link." : text;
  }
}
