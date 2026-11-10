import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest side of a saved recipe picture, in pixels.
const recipeImageMaxSide = 1200;

/// JPEG quality for saved recipe pictures.
const recipeImageJpegQuality = 80;

/// Refuse to decode anything bigger than this (the server caps at 5 MB too).
const recipeImageMaxInputBytes = 15 * 1024 * 1024;

class RecipePictureException implements Exception {
  RecipePictureException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Turns any JPEG, PNG, GIF or WebP into an upright JPEG no larger than
/// [recipeImageMaxSide] on its longest side, at [recipeImageJpegQuality].
/// Transparent areas become white. Throws [RecipePictureException] when the
/// bytes are not a picture we can read.
Uint8List prepareRecipeImage(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw RecipePictureException("That file isn't a picture.");
  }
  if (bytes.length > recipeImageMaxInputBytes) {
    throw RecipePictureException('That picture is too large.');
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    throw RecipePictureException("That file isn't a picture we can use.");
  }
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > recipeImageMaxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: recipeImageMaxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: recipeImageMaxSide,
            interpolation: img.Interpolation.average,
          );
  }
  if (image.hasAlpha) {
    final background = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 3,
    );
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(background, image);
  }
  return Uint8List.fromList(
    img.encodeJpg(image, quality: recipeImageJpegQuality),
  );
}

/// [prepareRecipeImage] off the UI isolate where the platform allows it.
Future<Uint8List> prepareRecipeImageAsync(Uint8List bytes) {
  return compute(prepareRecipeImage, bytes);
}

/// Storage object for a recipe picture. A fresh name per upload so a
/// replaced picture never serves a stale cached copy.
String recipeImageStoragePath(String hubId, String recipeId, {DateTime? now}) {
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return 'hubs/$hubId/recipes/$recipeId/$stamp.jpg';
}

/// What the edit sheet wants done with a recipe's picture on save.
sealed class RecipePictureChange {
  const RecipePictureChange();
}

class KeepRecipePicture extends RecipePictureChange {
  const KeepRecipePicture();
}

class RemoveRecipePicture extends RecipePictureChange {
  const RemoveRecipePicture();
}

class ReplaceRecipePicture extends RecipePictureChange {
  const ReplaceRecipePicture(this.jpegBytes);
  final Uint8List jpegBytes;
}
