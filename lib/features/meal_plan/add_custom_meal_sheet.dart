import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/recipe.dart';
import '../../core/models/meal_plan.dart';
import '../recipes/recipes_provider.dart';
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
      _selectedCategory = RecipeCategory.Aftensmad;
    }
  }


  RecipeCategory _mapStringToCategory(String cat) {
    switch (cat.toLowerCase()) {
      case 'morgenmad': return RecipeCategory.Morgenmad;
      case 'frokost': return RecipeCategory.Frokost;
      case 'snack': return RecipeCategory.Snack;
      default: return RecipeCategory.Aftensmad;
    }
  }

  List<DateTime> _generateWeekDates(int offset) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: offset * 7));
    return List.generate(7, (i) => weekStart.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9F8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  icon: const Icon(Icons.close, color: Color(0xFF0F5238)),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Add custom meal',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F5238),
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
                color: const Color(0xFFF0F2F0),
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
          
          // Bottom Button
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _saveAsRecipe,
                      onChanged: (v) => setState(() => _saveAsRecipe = v ?? false),
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    const Text('Gem som opskrift', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _saveMeal(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
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
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF0F5238) : Colors.grey[600],
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
            color: const Color(0xFFF0F2F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.grey[300]!,
              style: BorderStyle.solid,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Color(0xFFE0E4E0), shape: BoxShape.circle),
                child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey, size: 24),
              ),
              const SizedBox(height: 12),
              const Text('Tilføj et indbydende billede', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('JPEG eller PNG op til 5MB', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
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
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
            filled: true,
            fillColor: Colors.white,
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
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(100)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCounterBtn(Icons.remove, () => setState(() => _portions = (_portions > 1 ? _portions - 1 : 1))),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_portions', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const Text('pers.', style: TextStyle(fontSize: 9, color: Colors.grey)),
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
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
                    border: Border.all(color: AppColors.primary, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: AppColors.primary, size: 18),
                        SizedBox(width: 8),
                        Text('Tilføj ingrediens', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
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
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            filled: true,
            fillColor: Colors.white,
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
        decoration: const BoxDecoration(color: Color(0xFFF0F2F0), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: const Color(0xFF0F5238)),
      ),
    );
  }

  Widget _buildIngredientRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.remove, size: 16, color: Colors.grey),
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
      decoration: BoxDecoration(color: const Color(0xFFF0F2F0), borderRadius: BorderRadius.circular(8)),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
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
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? null : Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Text(
              days[date.weekday % 7],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white.withOpacity(0.8) : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.black87,
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
      case RecipeCategory.Morgenmad: slotName = 'breakfast'; break;
      case RecipeCategory.Frokost: slotName = 'lunch'; break;
      case RecipeCategory.Aftensmad: slotName = 'dinner'; break;
      case RecipeCategory.Snack: slotName = 'snack'; break;
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
