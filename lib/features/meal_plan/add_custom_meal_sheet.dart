import '../../core/theme/theme_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../recipes/recipes_provider.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import 'meal_plan_provider.dart';

class AddCustomMealSheet extends ConsumerStatefulWidget {
  final String? initialDay;
  final String? initialCategory;

  const AddCustomMealSheet({
    super.key,
    this.initialDay,
    this.initialCategory,
  });

  @override
  ConsumerState<AddCustomMealSheet> createState() => _AddCustomMealSheetState();
}

class _AddCustomMealSheetState extends ConsumerState<AddCustomMealSheet> {
  int _activeTab = 1; // 0: Søg opskrifter, 1: Eget måltid
  
  // Form fields for "Eget måltid"
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  late RecipeCategory _selectedCategory;
  int _portions = 4;
  final List<Map<String, String>> _ingredients = [
    {'name': '', 'amount': ''},
  ];
  bool _saveAsRecipe = false;
  
  // Date selection
  late DateTime _selectedDate;
  late List<DateTime> _weekDates;

  @override
  void initState() {
    super.initState();
    final offset = ref.read(weekOffsetProvider);
    _weekDates = _generateWeekDates(offset);
    
    // Brug initialDay hvis den findes, ellers mandag
    if (widget.initialDay != null) {
      final index = _getDayIndex(widget.initialDay!);
      _selectedDate = _weekDates[index];
    } else {
      _selectedDate = _weekDates[0];
    }

    // Brug initialCategory hvis den findes
    if (widget.initialCategory != null) {
      _selectedCategory = _mapStringToCategory(widget.initialCategory!);
    } else {
      _selectedCategory = RecipeCategory.aftensmad;
    }
  }


  RecipeCategory _mapStringToCategory(String cat) {
    switch (cat.toLowerCase()) {
      case 'morgenmad': return RecipeCategory.morgenmad;
      case 'frokost': return RecipeCategory.frokost;
      case 'snack': return RecipeCategory.snack;
      default: return RecipeCategory.aftensmad;
    }
  }

  List<DateTime> _generateWeekDates(int offset) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: offset * 7));
    return List.generate(7, (i) => weekStart.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    // 90 % af den plads sheetet faktisk har (ikke hele skærmen), så det
    // aldrig når op under statuslinjen.
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: context.colors.primary),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Tilføj eget måltid',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48), // Spacer for centering
              ],
            ),
          ),
          
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildTab(0, 'Søg opskrifter'),
                  _buildTab(1, 'Eget måltid'),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _activeTab == 1 ? _buildCustomMealForm() : _buildRecipeSearch(),
            ),
          ),
          
          // Bottom Button — ekstra plads til hjem-stregen i bunden
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + sheetBottomInset(context)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _saveAsRecipe,
                      onChanged: (v) => setState(() => _saveAsRecipe = v ?? false),
                      activeColor: context.colors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    const Text('Gem som opskrift', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _saveMeal(),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 20),
                      SizedBox(width: 8),
                      Text('Gem måltid', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTab(int index, String label) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? context.colors.surfaceContainerLowest : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive ? [BoxShadow(color: context.colors.shadow.withAlpha(13), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? context.colors.primary : context.colors.outline,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomMealForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Image Placeholder
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.colors.surfaceContainerHighest,
              style: BorderStyle.solid,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.colors.surfaceContainerHighest, shape: BoxShape.circle),
                child: Icon(Icons.add_a_photo_outlined, color: context.colors.outline, size: 24),
              ),
              const SizedBox(height: 12),
              const Text('Tilføj et indbydende billede', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('JPEG eller PNG op til 5MB', style: TextStyle(color: context.colors.outline, fontSize: 11)),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        // Meal Name
        TextField(
          controller: _titleController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Hvad skal I have at spise? (f.eks. Rugbrød med pålæg)',
            hintStyle: TextStyle(color: context.colors.outlineVariant, fontSize: 15),
            filled: true,
            fillColor: context.colors.surfaceContainerLowest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Kategori', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: RecipeCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            return ChoiceChip(
              label: Text(cat.name),
              selected: isSelected,
              onSelected: (v) => setState(() => _selectedCategory = cat),
              selectedColor: context.colors.primary,
              labelStyle: TextStyle(
                color: isSelected ? context.colors.onPrimary : context.colors.onSurface,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 24),
        const Text('Personer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          width: 150,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: context.colors.surfaceContainerLowest, borderRadius: BorderRadius.circular(100)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCounterBtn(Icons.remove, () => setState(() => _portions = (_portions > 1 ? _portions - 1 : 1))),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_portions', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('pers.', style: TextStyle(fontSize: 9, color: context.colors.outline)),
                ],
              ),
              _buildCounterBtn(Icons.add, () => setState(() => _portions++)),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        // Ingredients
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: context.colors.surfaceContainerLowest, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ingredienser', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              ...List.generate(_ingredients.length, (index) => _buildIngredientRow(index)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _ingredients.add({'name': '', 'amount': ''})),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.colors.primary, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: context.colors.primary, size: 18),
                        const SizedBox(width: 8),
                        Text('Tilføj ingrediens', style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Noter (valgfrit)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Tilføj noter eller detaljer...',
            hintStyle: TextStyle(color: context.colors.outlineVariant, fontSize: 13),
            filled: true,
            fillColor: context.colors.surfaceContainerLowest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Vælg dag', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _weekDates.map((date) => _buildDateCard(date)).toList(),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCounterBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: context.colors.surfaceContainerLow, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: context.colors.primary),
      ),
    );
  }

  Widget _buildIngredientRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.remove, size: 16, color: context.colors.outline),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildMiniField('Hakkede tomater', (v) => _ingredients[index]['name'] = v),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMiniField('400g', (v) => _ingredients[index]['amount'] = v),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniField(String hint, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: context.colors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: context.colors.outline, fontSize: 13),
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildDateCard(DateTime date) {
    final isSelected = DateUtils.isSameDay(_selectedDate, date);
    final days = ['SØN', 'MAN', 'TIR', 'ONS', 'TOR', 'FRE', 'LØR'];
    
    return GestureDetector(
      onTap: () => setState(() => _selectedDate = date),
      child: Container(
        width: 65,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primary : context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? null : Border.all(color: context.colors.surfaceContainer),
        ),
        child: Column(
          children: [
            Text(
              days[date.weekday % 7],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? context.colors.onPrimary.withValues(alpha: 0.8) : context.colors.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? context.colors.onPrimary : context.colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeSearch() {
    return const Center(child: Text('Her kommer søgning efter opskrifter...'));
  }

  void _saveMeal() async {
    if (_activeTab == 1 && _titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giv venligst måltidet et navn')));
      return;
    }

    final dayName = _getDayName(_selectedDate);
    
    // Map RecipeCategory to Slot name
    String slotName;
    switch (_selectedCategory) {
      case RecipeCategory.morgenmad: slotName = 'breakfast'; break;
      case RecipeCategory.frokost: slotName = 'lunch'; break;
      case RecipeCategory.aftensmad: slotName = 'dinner'; break;
      case RecipeCategory.snack: slotName = 'snack'; break;
    }
    
    if (_activeTab == 1) {
      // Gem som "Eget måltid"
      await ref.read(mealPlanProvider.notifier).updateSlot(
        dayName, 
        slotName, 
        directEntry: _titleController.text
      );
      
      if (_saveAsRecipe) {
        // Gem også som en rigtig opskrift
        final newRecipe = Recipe(
          id: '', // Bliver genereret af Firestore
          title: _titleController.text,
          calories: 0,
          time: '15 min',
          category: _selectedCategory,
          ingredients: _ingredients.where((i) => i['name']!.isNotEmpty).map((i) => Ingredient(
            name: i['name']!,
            quantity: 0, // Simplified
            unit: i['amount']!,
            category: 'Andet',
          )).toList(),
        );
        await ref.read(recipesProvider.notifier).addRecipe(newRecipe);
      }
    }
    
    if (mounted) Navigator.pop(context);
  }

  int _getDayIndex(String day) {
    final days = ['Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'];
    return days.indexOf(day).clamp(0, 6);
  }

  String _getDayName(DateTime date) {
    final days = ['Søndag', 'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag'];
    return days[date.weekday % 7];
  }
}
