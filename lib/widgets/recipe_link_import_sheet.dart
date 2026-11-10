import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../recipe_import/recipe_import_client.dart';
import '../recipe_import/recipe_page_parser.dart';
import '../recipe_import/recipe_picture.dart';
import 'recipe_picture.dart';

/// Paste a recipe link, check the parsed title, ingredients, and method,
/// then save. Nothing is written until Save.
class RecipeLinkImportSheet extends StatefulWidget {
  const RecipeLinkImportSheet({
    super.key,
    required this.importPage,
    required this.onSave,
    this.saveTimeout = const Duration(seconds: 20),
    this.loadSuggestedImage,
    this.pickPicture = pickRecipePicture,
  });

  final Future<ParsedRecipe> Function(String url) importPage;

  /// Saves the recipe. [imageJpeg] is the resized picture, or null.
  final Future<void> Function(ParsedRecipe recipe, Uint8List? imageJpeg) onSave;

  /// Fetches the page's suggested picture and returns it ready to save.
  final Future<Uint8List?> Function(String imageUrl)? loadSuggestedImage;

  final RecipePicturePicker pickPicture;

  /// A save that has not finished by then is reported as failed, so the
  /// button never just spins (for example offline on the web).
  final Duration saveTimeout;

  static const urlFieldKey = Key('recipe-import-url');
  static const importButtonKey = Key('recipe-import-fetch');
  static const titleFieldKey = Key('recipe-import-title');
  static const ingredientsFieldKey = Key('recipe-import-ingredients');
  static const methodFieldKey = Key('recipe-import-method');
  static const saveButtonKey = Key('recipe-import-save');
  static const manualButtonKey = Key('recipe-import-manual');
  static const errorKey = Key('recipe-import-error');
  static const notesKey = Key('recipe-import-notes');
  static const saveErrorKey = Key('recipe-import-save-error');

  @override
  State<RecipeLinkImportSheet> createState() => _RecipeLinkImportSheetState();
}

class _RecipeLinkImportSheetState extends State<RecipeLinkImportSheet> {
  final _urlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _ingCtrl = TextEditingController();
  final _methodCtrl = TextEditingController();

  ParsedRecipe? _parsed;
  bool _showForm = false;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _saveError;

  Uint8List? _imageBytes;
  Uint8List? _suggestedBytes;
  bool _usingSuggestion = false;
  bool _imageLoading = false;
  String? _imageError;
  int _imageToken = 0;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onTitleChanged);
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    _ingCtrl.dispose();
    _methodCtrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Paste a full http or https recipe link.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recipe = await widget.importPage(url);
      if (!mounted) return;
      _apply(recipe);
    } on RecipeImportException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't import that link.";
      });
    }
  }

  void _resetPicture() {
    _imageToken++;
    _imageBytes = null;
    _suggestedBytes = null;
    _usingSuggestion = false;
    _imageLoading = false;
    _imageError = null;
  }

  Future<void> _loadSuggestion(String url) async {
    final loader = widget.loadSuggestedImage;
    if (loader == null) return;
    final token = ++_imageToken;
    setState(() => _imageLoading = true);
    Uint8List? bytes;
    String? error;
    try {
      bytes = await loader(url);
    } catch (_) {
      error = "Couldn't load the picture from that page.";
    }
    if (!mounted || token != _imageToken) return;
    setState(() {
      _imageLoading = false;
      if (bytes != null && bytes.isNotEmpty) {
        _suggestedBytes = bytes;
        _imageBytes = bytes;
        _usingSuggestion = true;
      } else {
        _imageError = error;
      }
    });
  }

  Future<void> _pickPicture(ImageSource source) async {
    final token = ++_imageToken;
    setState(() {
      _imageLoading = true;
      _imageError = null;
    });
    Uint8List? bytes;
    String? error;
    try {
      bytes = await widget.pickPicture(source);
    } on RecipePictureException catch (e) {
      error = e.message;
    } catch (_) {
      error = "Couldn't use that picture.";
    }
    if (!mounted || token != _imageToken) return;
    setState(() {
      _imageLoading = false;
      _imageError = error;
      if (bytes != null) {
        _imageBytes = bytes;
        _usingSuggestion = false;
      }
    });
  }

  void _removePicture() {
    setState(() {
      _imageBytes = null;
      _usingSuggestion = false;
      _imageError = null;
    });
  }

  void _useSuggestion() {
    setState(() {
      _imageBytes = _suggestedBytes;
      _usingSuggestion = true;
    });
  }

  void _apply(ParsedRecipe recipe) {
    _resetPicture();
    _titleCtrl.text = recipe.title;
    _ingCtrl.text = recipe.ingredients.join('\n');
    _methodCtrl.text = recipe.method;
    setState(() {
      _parsed = recipe;
      _showForm = true;
      _loading = false;
      _error = null;
    });
    final imageUrl = recipe.imageUrl;
    if (imageUrl != null) _loadSuggestion(imageUrl);
  }

  void _addByHand() {
    _titleCtrl.clear();
    _ingCtrl.clear();
    _methodCtrl.clear();
    _resetPicture();
    setState(() {
      _parsed = null;
      _showForm = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (_saving || _imageLoading) return;
    if (title.isEmpty) {
      _showSaveError('Add a recipe name before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final ingredients = _ingCtrl.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final recipe = ParsedRecipe(
      title: title,
      ingredients: ingredients,
      method: _methodCtrl.text.trim(),
      sourceUrl: _parsed?.sourceUrl,
      source: _parsed?.source ?? 'manual',
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.onSave(recipe, _imageBytes).timeout(widget.saveTimeout);
    } on TimeoutException {
      if (!mounted) return;
      _showSaveError(
        "Couldn't save the recipe. Check your connection and try again.",
      );
      return;
    } catch (error) {
      if (!mounted) return;
      _showSaveError("Couldn't save the recipe: $error");
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(content: Text('Saved "$title" to your Cookbook.')),
    );
  }

  void _showSaveError(String message) {
    setState(() {
      _saving = false;
      _saveError = message;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final host = importedRecipeHost(parsed?.sourceUrl);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 24,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Import recipe',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Paste a link. You can edit the recipe before it is saved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: RecipeLinkImportSheet.urlFieldKey,
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _loading ? null : _import(),
                    decoration: InputDecoration(
                      labelText: 'Recipe link',
                      hintText: 'https://www.nigella.com/recipes/...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_showForm)
                    OutlinedButton.icon(
                      key: RecipeLinkImportSheet.importButtonKey,
                      onPressed: _loading || _saving ? null : _import,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Fetch link again'),
                    )
                  else
                    FilledButton(
                      key: RecipeLinkImportSheet.importButtonKey,
                      onPressed: _loading ? null : _import,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Import',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: RecipeLinkImportSheet.errorKey,
                      style: const TextStyle(color: Colors.red),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: RecipeLinkImportSheet.manualButtonKey,
                        onPressed: _addByHand,
                        child: const Text('Add by hand instead'),
                      ),
                    ),
                  ],
                  if (_showForm) ...[
                    const SizedBox(height: 20),
                    if (host.isNotEmpty)
                      Text(
                        'From $host. Check it, then save.',
                        style: TextStyle(color: Colors.green.shade900),
                      )
                    else
                      Text(
                        'Check it, then save.',
                        style: TextStyle(color: Colors.green.shade900),
                      ),
                    if (parsed != null && parsed.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        parsed.notes.join(' '),
                        key: RecipeLinkImportSheet.notesKey,
                        style: const TextStyle(color: Colors.brown),
                      ),
                    ],
                    const SizedBox(height: 12),
                    RecipePictureEditor(
                      bytes: _imageBytes,
                      loading: _imageLoading,
                      error: _imageError,
                      caption: _usingSuggestion
                          ? 'Picture from ${host.isEmpty ? 'the page' : host}. '
                                'Keep it, remove it, or choose your own.'
                          : null,
                      onPick: _pickPicture,
                      onRemove: _removePicture,
                      onUseSuggestion:
                          _suggestedBytes != null && !_usingSuggestion
                          ? _useSuggestion
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: RecipeLinkImportSheet.titleFieldKey,
                      controller: _titleCtrl,
                      decoration: _fieldDecoration('Recipe Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: RecipeLinkImportSheet.ingredientsFieldKey,
                      controller: _ingCtrl,
                      maxLines: null,
                      minLines: 4,
                      keyboardType: TextInputType.multiline,
                      decoration: _fieldDecoration(
                        'Ingredients (one per line)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: RecipeLinkImportSheet.methodFieldKey,
                      controller: _methodCtrl,
                      maxLines: null,
                      minLines: 4,
                      keyboardType: TextInputType.multiline,
                      decoration: _fieldDecoration('Method'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          if (_showForm) ...[
            if (_saveError != null)
              Container(
                key: RecipeLinkImportSheet.saveErrorKey,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _saveError!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: RecipeLinkImportSheet.saveButtonKey,
              onPressed: _saving || _imageLoading ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save to Cookbook',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
