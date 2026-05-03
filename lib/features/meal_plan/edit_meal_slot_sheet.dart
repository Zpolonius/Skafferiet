import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/app_colors.dart';
import '../../features/recipes/recipes_provider.dart';
import '../../features/meal_plan/meal_plan_provider.dart';

class EditMealSlotSheet extends ConsumerStatefulWidget {
  final String day;
  final String slotType;
  final MealSlot currentSlot;

  const EditMealSlotSheet({
    super.key,
    required this.day,
    required this.slotType,
    required this.currentSlot,
  });

  @override
  ConsumerState<EditMealSlotSheet> createState() => _EditMealSlotSheetState();
}

class _EditMealSlotSheetState extends ConsumerState<EditMealSlotSheet> {
  final _textController = TextEditingController();
  Recipe? _selectedRecipe;

  @override
  void initState() {
    super.initState();
    _textController.text = widget.currentSlot.directEntry ?? '';
    _selectedRecipe = widget.currentSlot.recipe;
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(recipesProvider);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.slotType} - ${widget.day}',
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 24),
          Text('Indtast manuelt', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              hintText: 'F.eks. Rugbrød med ost eller Takeout',
              prefixIcon: Icon(Icons.edit_note),
            ),
          ),
          const SizedBox(height: 24),
          Text('Eller vælg en opskrift', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: recipesAsync.when(
              data: (recipes) => ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recipes.length,
                itemBuilder: (context, index) {
                  final recipe = recipes[index];
                  final isSelected = _selectedRecipe?.id == recipe.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedRecipe = isSelected ? null : recipe),
                    child: Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                        image: DecorationImage(
                          image: NetworkImage(recipe.imageUrl ?? ''),
                          fit: BoxFit.cover,
                          colorFilter: isSelected 
                            ? ColorFilter.mode(AppColors.primary.withValues(alpha: 0.3), BlendMode.srcOver)
                            : null,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          recipe.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Kunne ikke hente opskrifter'),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(mealPlanProvider.notifier).updateSlot(widget.day, widget.slotType);
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Ryd felt'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    ref.read(mealPlanProvider.notifier).updateSlot(
                      widget.day,
                      widget.slotType,
                      recipe: _selectedRecipe,
                      directEntry: _textController.text.isNotEmpty ? _textController.text : null,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Gem'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
