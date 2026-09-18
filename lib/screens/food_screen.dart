import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';

import '../models/recipe_model.dart';
import '../repositories/recipe_repository.dart';
import '../repositories/task_repository.dart';
import 'tasks_screen.dart'; // (if you still have this here)

class FoodScreen extends StatefulWidget {
  final User user;
  final List<MapEntry<String, dynamic>> visibleHubs;

  const FoodScreen({super.key, required this.user, required this.visibleHubs});

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _hubId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
    ); // <-- Change length to 4
    if (widget.visibleHubs.isNotEmpty) {
      _hubId = widget.visibleHubs.first.key;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hubId == null) return const Center(child: Text("Join a hub first"));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Kitchen",
          style: TextStyle(
            color: Colors.green.shade900,
            fontWeight: FontWeight.bold,
          ), // Dark green text
        ),
        backgroundColor: Colors.green.shade50, // Light pastel green!
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.green.shade900, // Dark text for the active tab
          unselectedLabelColor:
              Colors.green.shade400, // Softer green for inactive tabs
          indicatorColor: Colors.green.shade600, // Darker green underline
          isScrollable: true,
          tabs: const [
            Tab(text: "SHOPPING"),
            Tab(text: "RECIPES"),
            Tab(text: "PLANNER"),
            Tab(text: "AI CHEF"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // --- NEW: Embedded Shopping List! ---
          TasksScreen(
            user: widget.user,
            visibleHubs: widget.visibleHubs,
            initialList: 'Shopping',
            hideAppBar: true,
            isShoppingOnly: true, // <-- Tell it to hide the other tabs!
          ),
          _RecipesTab(hubId: _hubId!),
          _MealPlannerTab(hubId: _hubId!),
          _FridgeAITab(hubId: _hubId!), // <-- ADD THE HUB ID HERE!
        ],
      ),
    );
  }
}

// --- TAB 1: RECIPES ---
class _RecipesTab extends StatelessWidget {
  final String hubId;
  final RecipeRepository _recipeRepo = RecipeRepository();

  _RecipesTab({required this.hubId});

  void _showAddRecipe(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.green.shade50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddRecipeSheet(hubId: hubId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    int columns = (screenWidth / 180).floor();
    if (columns < 2) columns = 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRecipe(context),
        backgroundColor: Colors.green.shade600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          "New Recipe",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<Recipe>>(
        stream: _recipeRepo.streamRecipes(hubId),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(
              child: Text('Offline.', style: TextStyle(color: Colors.grey)),
            );
          if (!snapshot.hasData)
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );

          final recipes = snapshot.data!;
          if (recipes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book, size: 60, color: Colors.green.shade200),
                  const SizedBox(height: 12),
                  const Text(
                    "No recipes yet. Add your House Standards!",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: recipes.length,
            itemBuilder: (context, index) =>
                _RecipeCard(recipe: recipes[index], hubId: hubId),
          );
        },
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final String hubId;

  const _RecipeCard({required this.recipe, required this.hubId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) =>
              _RecipeDetailSheet(recipe: recipe, hubId: hubId),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  size: 40,
                  color: Colors.green.shade300,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      recipe.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${recipe.ingredients.length} ingredients",
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- RECIPE DETAIL SHEET ---
class _RecipeDetailSheet extends StatelessWidget {
  final Recipe recipe;
  final String hubId;

  const _RecipeDetailSheet({required this.recipe, required this.hubId});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  recipe.title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ),
              // --- NEW: DELETE RECIPE BUTTON ---
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Recipe?'),
                      content: const Text(
                        'This will permanently remove this recipe from your cookbook.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await FirebaseFirestore.instance
                        .collection('hubs')
                        .doc(hubId)
                        .collection('recipes')
                        .doc(recipe.id)
                        .delete();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
              // FIX: Added Edit Button!
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.green),
                onPressed: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.green.shade50,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    builder: (context) =>
                        _AddRecipeSheet(hubId: hubId, existingRecipe: recipe),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  const Text(
                    "INGREDIENTS",
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...recipe.ingredients.map(
                    (ing) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "• ",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              ing,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (recipe.method != null && recipe.method!.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    const Text(
                      "METHOD",
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        recipe.method!,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => IngredientReviewSheet(
                  mealTitle: recipe.title,
                  ingredients: recipe.ingredients,
                  hubId: hubId,
                ),
              );
            },
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text("CHECK INGREDIENTS"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// --- ADD / EDIT RECIPE SHEET ---
class _AddRecipeSheet extends StatefulWidget {
  final String hubId;
  final Recipe? existingRecipe; // NEW: Accepts an existing recipe
  const _AddRecipeSheet({required this.hubId, this.existingRecipe});

  @override
  State<_AddRecipeSheet> createState() => _AddRecipeSheetState();
}

class _AddRecipeSheetState extends State<_AddRecipeSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _ingCtrl;
  late TextEditingController _methodCtrl;
  final RecipeRepository _recipeRepo = RecipeRepository();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the controllers if we are editing!
    _titleCtrl = TextEditingController(
      text: widget.existingRecipe?.title ?? '',
    );
    _ingCtrl = TextEditingController(
      text: widget.existingRecipe?.ingredients.join('\n') ?? '',
    );
    _methodCtrl = TextEditingController(
      text: widget.existingRecipe?.method ?? '',
    );
  }

  void _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);

    List<String> ingredients = _ingCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    try {
      if (widget.existingRecipe != null) {
        // UPDATE EXISTING
        await FirebaseFirestore.instance
            .collection('hubs')
            .doc(widget.hubId)
            .collection('recipes')
            .doc(widget.existingRecipe!.id)
            .update({
              'title': _titleCtrl.text.trim(),
              'ingredients': ingredients,
              'method': _methodCtrl.text.trim(),
            });
      } else {
        // DIRECT CREATE NEW (Bypasses repo to prevent errors)
        await FirebaseFirestore.instance
            .collection('hubs')
            .doc(widget.hubId)
            .collection('recipes')
            .add({
              'title': _titleCtrl.text.trim(),
              'ingredients': ingredients,
              'method': _methodCtrl.text.trim(),
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) Navigator.pop(context); // Close sheet safely!
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving recipe: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text(
              widget.existingRecipe != null ? "Edit Recipe" : "New Recipe",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: "Recipe Name",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ingCtrl,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                labelText: "Ingredients (one per line)",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _methodCtrl,
              maxLines: 8,
              minLines: 3,
              decoration: InputDecoration(
                labelText: "Method / Instructions (Optional)",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      widget.existingRecipe != null
                          ? "Save Changes"
                          : "Save to Cookbook",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// --- TAB 2: MEAL PLANNER ---
class _MealPlannerTab extends StatelessWidget {
  final String hubId;
  const _MealPlannerTab({required this.hubId});

  void _showSmartAddMeal(BuildContext context, DateTime day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.green.shade50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _SmartAddMealSheet(hubId: hubId, date: day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayStart = DateUtils.dateOnly(DateTime.now());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('events')
          .where(
            'start',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
          )
          .orderBy('start')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(
            child: CircularProgressIndicator(color: Colors.green),
          );

        final events = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: 7,
          itemBuilder: (context, index) {
            final day = todayStart.add(Duration(days: index));
            final isToday = index == 0;

            final meals = events.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              if ((d['category'] ?? 'general') != 'meal') return false;
              return DateUtils.isSameDay(
                (d['start'] as Timestamp).toDate(),
                day,
              );
            }).toList();

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isToday ? Colors.green.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isToday ? Colors.green.shade300 : Colors.grey.shade200,
                  width: isToday ? 2 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 50,
                    child: Column(
                      children: [
                        Text(
                          isToday
                              ? "TODAY"
                              : DateFormat('EEE').format(day).toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: isToday
                                ? Colors.green.shade700
                                : Colors.grey,
                          ),
                        ),
                        Text(
                          DateFormat('d').format(day),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isToday
                                ? Colors.green.shade900
                                : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  Expanded(
                    child: meals.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              "No meal planned",
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: meals.map((m) {
                              final d = m.data() as Map<String, dynamic>;
                              final bool hasIngredients =
                                  d.containsKey('ingredients') &&
                                  (d['ingredients'] as List).isNotEmpty;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // FIX: Added a Row to hold the Meal Title and the Delete Button
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "🍽️ ${d['summary']}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.green.shade900,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: Colors.grey,
                                          ),
                                          constraints:
                                              const BoxConstraints(), // Keeps the button small
                                          padding: EdgeInsets.zero,
                                          onPressed: () => m.reference
                                              .delete(), // Instantly deletes the meal!
                                        ),
                                      ],
                                    ),

                                    if (hasIngredients)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            showModalBottomSheet(
                                              context: context,
                                              isScrollControlled: true,
                                              backgroundColor:
                                                  Colors.transparent,
                                              builder: (_) =>
                                                  IngredientReviewSheet(
                                                    mealTitle: d['summary'],
                                                    ingredients:
                                                        d['ingredients'],
                                                    hubId: hubId,
                                                  ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.checklist,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            "Review Ingredients",
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.green.shade600,
                                            foregroundColor: Colors.white,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle,
                      color: isToday
                          ? Colors.green.shade600
                          : Colors.grey.shade400,
                      size: 28,
                    ),
                    onPressed: () => _showSmartAddMeal(context, day),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// --- SMART ADD MEAL SHEET ---
class _SmartAddMealSheet extends StatefulWidget {
  final String hubId;
  final DateTime date;
  const _SmartAddMealSheet({required this.hubId, required this.date});

  @override
  State<_SmartAddMealSheet> createState() => _SmartAddMealSheetState();
}

class _SmartAddMealSheetState extends State<_SmartAddMealSheet> {
  final _textCtrl = TextEditingController();
  Recipe? _selectedRecipe;

  void _save() {
    if (_textCtrl.text.isEmpty && _selectedRecipe == null) return;

    final String title = _selectedRecipe != null
        ? _selectedRecipe!.title
        : _textCtrl.text.trim();

    Map<String, dynamic> eventData = {
      'summary': title,
      'start': Timestamp.fromDate(
        DateTime(widget.date.year, widget.date.month, widget.date.day, 19, 0),
      ),
      'end': Timestamp.fromDate(
        DateTime(widget.date.year, widget.date.month, widget.date.day, 20, 0),
      ),
      'allDay': false,
      'category': 'meal',
      'assignedTo': 'shared',
    };

    if (_selectedRecipe != null) {
      eventData['recipeId'] = _selectedRecipe!.id;
      eventData['ingredients'] = _selectedRecipe!.ingredients;
    }

    FirebaseFirestore.instance
        .collection('hubs')
        .doc(widget.hubId)
        .collection('events')
        .add(eventData);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            "Dinner for ${DateFormat('EEEE').format(widget.date)}",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          TextField(
            controller: _textCtrl,
            decoration: InputDecoration(
              labelText: "Type a custom meal...",
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) {
              if (_selectedRecipe != null)
                setState(() => _selectedRecipe = null);
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              "OR CHOOSE A RECIPE:",
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),

          SizedBox(
            height: 50,
            child: StreamBuilder<List<Recipe>>(
              stream: RecipeRepository().streamRecipes(widget.hubId),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.green),
                  );
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: snapshot.data!
                      .map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(r.title),
                            selected: _selectedRecipe?.id == r.id,
                            selectedColor: Colors.green.shade200,
                            onSelected: (val) {
                              setState(() {
                                _selectedRecipe = val ? r : null;
                                if (val) _textCtrl.clear();
                              });
                            },
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text("Save to Planner"),
          ),
        ],
      ),
    );
  }
}

// --- TAB 3: FRIDGE AI ---
class _FridgeAITab extends StatefulWidget {
  final String hubId; // <-- Now receives the Hub ID
  const _FridgeAITab({required this.hubId});

  @override
  State<_FridgeAITab> createState() => _FridgeAITabState();
}

class _FridgeAITabState extends State<_FridgeAITab> {
  File? _imageFile;
  bool _isAnalyzing = false;
  List<Map<String, dynamic>> _suggestedRecipes =
      []; // <-- Now stores structured data!
  String _errorMessage = '';

  final TextEditingController _promptCtrl =
      TextEditingController(); // <-- NEW: Text Controller

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: source, maxWidth: 800);
      if (pickedFile == null) return;

      setState(() {
        _imageFile = File(pickedFile.path);
        _isAnalyzing = true;
        _suggestedRecipes = [];
        _errorMessage = '';
      });

      // 1. Tell Gemini we want strict JSON output
      final model = FirebaseVertexAI.instance.generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );
      final bytes = await pickedFile.readAsBytes();

      // 2. The Structured Prompt (Updated with custom text!)
      final customText = _promptCtrl.text.trim();

      final prompt =
          """You are a practical home chef. Look at the ingredients in this fridge/pantry. 
      Suggest 3 simple recipes I can make primarily using what you see. 
      ${customText.isNotEmpty ? "\nCRITICAL ADDITIONAL INSTRUCTIONS FROM USER: $customText\n" : ""}
      Return ONLY a valid JSON array of objects. Do not include markdown formatting like ```json.
      Each object MUST have this exact structure:
      {
        "title": "Recipe Name",
        "ingredients": ["Item 1", "Item 2 (need to buy)", "Item 3"],
        "method": "Brief step-by-step instructions."
      }""";

      final response = await model.generateContent([
        Content.multi([TextPart(prompt), InlineDataPart('image/jpeg', bytes)]),
      ]);

      // 3. Parse the JSON
      if (mounted) {
        String rawText = response.text ?? '[]';
        // Clean up any accidental markdown blocks the AI might inject
        rawText = rawText
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final List<dynamic> parsed = jsonDecode(rawText);

        setState(() {
          _suggestedRecipes = parsed.cast<Map<String, dynamic>>();
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error analyzing fridge: $e';
          _isAnalyzing = false;
        });
      }
    }
  }

  void _showImagePickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRecipeToCookbook(Map<String, dynamic> recipe) async {
    try {
      await FirebaseFirestore.instance
          .collection('hubs')
          .doc(widget.hubId)
          .collection('recipes')
          .add({
            'title': recipe['title'],
            'ingredients': List<String>.from(recipe['ingredients']),
            'method': recipe['method'],
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✨ '${recipe['title']}' saved to Recipes!"),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving recipe: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
              image: _imageFile != null
                  ? DecorationImage(
                      image: FileImage(_imageFile!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _imageFile == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.kitchen, size: 60, color: Colors.green),
                      SizedBox(height: 12),
                      Text(
                        "Let AI see what you have.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  )
                : null,
          ),

          const SizedBox(height: 24),

          // --- NEW: CUSTOM INSTRUCTIONS FIELD ---
          TextField(
            controller: _promptCtrl,
            decoration: InputDecoration(
              labelText: "Any specific requests? (Optional)",
              hintText: "e.g., Make it spicy, under 20 mins, no dairy...",
              filled: true,
              fillColor: Colors.green.shade50,
              prefixIcon: const Icon(Icons.tune, color: Colors.green),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          FilledButton.icon(
            onPressed: _isAnalyzing
                ? null
                : () => _showImagePickerOptions(context),
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.camera_alt),
            label: Text(
              _isAnalyzing
                  ? "Gemini is analyzing..."
                  : (_imageFile == null
                        ? "Add Fridge / Pantry Photo"
                        : "Choose New Photo"),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(_errorMessage, style: const TextStyle(color: Colors.red)),
          ],

          if (_suggestedRecipes.isNotEmpty) ...[
            const SizedBox(height: 30),
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  "GEMINI SUGGESTS",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- THE NEW INTERACTIVE RECIPE CARDS ---
            ..._suggestedRecipes.map((recipe) {
              final ingredients = List<String>.from(
                recipe['ingredients'] ?? [],
              );
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Text(
                        recipe['title'] ?? 'Recipe Idea',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                    // --- NEW: DISMISS CARD BUTTON ---
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.orange.shade400),
                      onPressed: () {
                        setState(() {
                          _suggestedRecipes.remove(recipe);
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "INGREDIENTS",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...ingredients.map(
                            (ing) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "• ",
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      ing,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "METHOD",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            recipe['method'] ?? '',
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _saveRecipeToCookbook(recipe),
                              icon: const Icon(
                                Icons.bookmark_add,
                                color: Colors.orange,
                              ),
                              label: const Text(
                                "Save to Recipes",
                                style: TextStyle(color: Colors.orange),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.orange.shade300),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// GLOBAL REUSABLE WIDGET
// ============================================================================
class IngredientReviewSheet extends StatefulWidget {
  final String mealTitle;
  final List<dynamic> ingredients;
  final String hubId;

  const IngredientReviewSheet({
    super.key,
    required this.mealTitle,
    required this.ingredients,
    required this.hubId,
  });

  @override
  State<IngredientReviewSheet> createState() => _IngredientReviewSheetState();
}

class _IngredientReviewSheetState extends State<IngredientReviewSheet> {
  final Set<String> _haveIngredients = {};
  final TaskRepository _taskRepo = TaskRepository();
  bool _isSaving = false;

  void _addToShoppingList() async {
    setState(() => _isSaving = true);
    List<String> missingItems = [];
    for (String item in widget.ingredients) {
      if (!_haveIngredients.contains(item)) missingItems.add(item);
    }

    if (missingItems.isEmpty) {
      Navigator.pop(context);
      return;
    }

    await _taskRepo.addMissingIngredientsToShoppingList(
      widget.hubId,
      missingItems,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Added ${missingItems.length} items to Shopping List"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Prep: ${widget.mealTitle}",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          const Text(
            "CHECK WHAT YOU ALREADY HAVE:",
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: widget.ingredients.length,
              itemBuilder: (context, index) {
                final item = widget.ingredients[index].toString();
                final isChecked = _haveIngredients.contains(item);
                return CheckboxListTile(
                  title: Text(
                    item,
                    style: TextStyle(
                      color: isChecked ? Colors.grey : Colors.black,
                      decoration: isChecked ? TextDecoration.lineThrough : null,
                      fontWeight: isChecked
                          ? FontWeight.normal
                          : FontWeight.w500,
                    ),
                  ),
                  value: isChecked,
                  activeColor: Colors.green,
                  onChanged: (val) {
                    setState(() {
                      val == true
                          ? _haveIngredients.add(item)
                          : _haveIngredients.remove(item);
                    });
                  },
                );
              },
            ),
          ),
          FilledButton.icon(
            onPressed: _isSaving ? null : _addToShoppingList,
            icon: const Icon(Icons.shopping_cart),
            label: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text("SHOP FOR THE REST"),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
