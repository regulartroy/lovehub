import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../recipe_import/recipe_picture.dart';

/// Opens the camera or the photo library (a file chooser on the web) and
/// returns the picture ready to save, or null when the cook cancels.
typedef RecipePicturePicker = Future<Uint8List?> Function(ImageSource source);

Future<Uint8List?> pickRecipePicture(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    // A first, cheap shrink on the device. prepareRecipeImage does the rest.
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 92,
  );
  if (file == null) return null;
  return prepareRecipeImageAsync(await file.readAsBytes());
}

/// The placeholder recipes have always shown.
class RecipePicturePlaceholder extends StatelessWidget {
  const RecipePicturePlaceholder({super.key, this.size = 40, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.green.shade50,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_menu, size: size, color: Colors.green.shade300),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(label!, style: TextStyle(color: Colors.green.shade700)),
          ],
        ],
      ),
    );
  }
}

/// A saved recipe picture, or the placeholder when there is none or it
/// fails to load.
class RecipeImage extends StatelessWidget {
  const RecipeImage({super.key, required this.imageUrl, this.iconSize = 40});

  final String? imageUrl;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return RecipePicturePlaceholder(size: iconSize);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : RecipePicturePlaceholder(size: iconSize),
      errorBuilder: (context, error, stack) =>
          RecipePicturePlaceholder(size: iconSize),
    );
  }
}

/// Picture box for the recipe sheets: shows the picture (new bytes, or the
/// saved one) and the take / choose / remove buttons.
class RecipePictureEditor extends StatelessWidget {
  const RecipePictureEditor({
    super.key,
    required this.onPick,
    this.bytes,
    this.imageUrl,
    this.loading = false,
    this.caption,
    this.error,
    this.onRemove,
    this.onUseSuggestion,
  });

  final Uint8List? bytes;
  final String? imageUrl;
  final bool loading;
  final String? caption;
  final String? error;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback? onRemove;

  /// Shown as "Use the suggested picture" after the suggestion was removed.
  final VoidCallback? onUseSuggestion;

  static const previewKey = Key('recipe-picture-preview');
  static const cameraKey = Key('recipe-picture-camera');
  static const galleryKey = Key('recipe-picture-gallery');
  static const removeKey = Key('recipe-picture-remove');
  static const useSuggestionKey = Key('recipe-picture-use-suggestion');

  bool get _hasPicture =>
      bytes != null || (imageUrl != null && imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    Widget picture;
    if (loading) {
      picture = Container(
        color: Colors.green.shade50,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.green),
      );
    } else if (bytes != null) {
      picture = Image.memory(
        bytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) =>
            const RecipePicturePlaceholder(label: "Can't show this picture"),
      );
    } else if (_hasPicture) {
      picture = RecipeImage(imageUrl: imageUrl);
    } else {
      picture = const RecipePicturePlaceholder(label: 'No picture');
    }
    final busy = loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          key: previewKey,
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(aspectRatio: 16 / 9, child: picture),
        ),
        if (caption != null && _hasPicture && !busy) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error!, style: TextStyle(color: Colors.red.shade700)),
        ],
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              key: cameraKey,
              onPressed: busy ? null : () => onPick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take photo'),
            ),
            TextButton.icon(
              key: galleryKey,
              onPressed: busy ? null : () => onPick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(kIsWeb ? 'Choose photo or file' : 'Choose photo'),
            ),
            if (_hasPicture && onRemove != null)
              TextButton.icon(
                key: removeKey,
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove picture'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
              ),
            if (!_hasPicture && onUseSuggestion != null)
              TextButton.icon(
                key: useSuggestionKey,
                onPressed: busy ? null : onUseSuggestion,
                icon: const Icon(Icons.undo),
                label: const Text('Use the suggested picture'),
              ),
          ],
        ),
      ],
    );
  }
}
