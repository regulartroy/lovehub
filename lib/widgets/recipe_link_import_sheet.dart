import 'package:flutter/material.dart';

import '../recipe_import/recipe_import_client.dart';
import '../recipe_import/recipe_page_parser.dart';

/// Paste a recipe link, check the parsed title, ingredients, and method,
/// then save. Nothing is written until Save.
class RecipeLinkImportSheet extends StatefulWidget {
  const RecipeLinkImportSheet({
    super.key,
    required this.importPage,
    required this.onSave,
  });

  final Future<ParsedRecipe> Function(String url) importPage;
  final Future<void> Function(ParsedRecipe recipe) onSave;

  static const urlFieldKey = Key('recipe-import-url');
  static const importButtonKey = Key('recipe-import-fetch');
  static const titleFieldKey = Key('recipe-import-title');
  static const ingredientsFieldKey = Key('recipe-import-ingredients');
  static const methodFieldKey = Key('recipe-import-method');
  static const saveButtonKey = Key('recipe-import-save');
  static const manualButtonKey = Key('recipe-import-manual');
  static const errorKey = Key('recipe-import-error');
  static const notesKey = Key('recipe-import-notes');

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

  void _apply(ParsedRecipe recipe) {
    _titleCtrl.text = recipe.title;
    _ingCtrl.text = recipe.ingredients.join('\n');
    _methodCtrl.text = recipe.method;
    setState(() {
      _parsed = recipe;
      _showForm = true;
      _loading = false;
      _error = null;
    });
  }

  void _addByHand() {
    _titleCtrl.clear();
    _ingCtrl.clear();
    _methodCtrl.clear();
    setState(() {
      _parsed = null;
      _showForm = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
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
    try {
      await widget.onSave(recipe);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Error saving recipe: $error';
      });
    }
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
              TextField(
                key: RecipeLinkImportSheet.titleFieldKey,
                controller: _titleCtrl,
                decoration: _fieldDecoration('Recipe Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: RecipeLinkImportSheet.ingredientsFieldKey,
                controller: _ingCtrl,
                maxLines: 8,
                minLines: 4,
                decoration: _fieldDecoration('Ingredients (one per line)'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: RecipeLinkImportSheet.methodFieldKey,
                controller: _methodCtrl,
                maxLines: 10,
                minLines: 4,
                decoration: _fieldDecoration('Method'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: RecipeLinkImportSheet.saveButtonKey,
                onPressed: _saving || _titleCtrl.text.trim().isEmpty
                    ? null
                    : _save,
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
