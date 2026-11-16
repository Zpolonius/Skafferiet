import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/meal_type.dart';
import '../../core/models/recipe_units.dart';
import '../../core/models/recipe.dart';
import '../../core/services/meal_plan_dates.dart';
import '../recipes/recipes_provider.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../profile/household_provider.dart';
import 'edit_meal_slot_sheet.dart';
import 'meal_plan_provider.dart';
import 'recipe_picker.dart';
import 'slot_write.dart';
import '../../core/theme/theme_context.dart';

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
  int _activeTab = 1; // 0: Søg opskrifter, 1: Eget måltid (sættes i initState)

  // Form fields for "Eget måltid"
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  late RecipeCategory _selectedCategory;
  int _portions = 4;
  final List<Map<String, String>> _ingredients = [
    {'name': '', 'amount': ''},
  ];
  bool _saveAsRecipe = false;
  bool _saving = false;

  /// Sat ved enhver interaktion med arket (fane, dag, måltid, felter …), så
  /// fanen ikke skifter under brugeren, når opskrifterne bliver indlæst.
  bool _touched = false;
  String? _error;

  // Date selection
  late DateTime _selectedDate;
  late List<DateTime> _weekDates;

  @override
  void initState() {
    super.initState();
    // Har husstanden opskrifter, er det oftest dem man vil vælge imellem.
    // (Opskrifterne er normalt allerede indlæst; ellers skiftes når de er det,
    // medmindre brugeren allerede har rørt ved arket.)
    ref.listenManual(recipesProvider, (_, next) {
      final hasRecipes = next.valueOrNull?.isNotEmpty ?? false;
      if (hasRecipes && !_touched && _activeTab != 0) {
        setState(() => _activeTab = 0);
      }
    }, fireImmediately: true);
    final offset = ref.read(weekOffsetProvider);
    _weekDates = _generateWeekDates(offset);

    // Brug initialDay hvis den findes, ellers plan-ugens første dag
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

    // Har brugeren fravalgt måltidet, vælges det første de har valgt.
    final mealTypes = ref.read(householdProvider).mealTypes;
    if (!mealTypes.contains(MealType.fromCategory(_selectedCategory))) {
      _selectedCategory = mealTypes.first.recipeCategory;
    }
  }

  /// Ændrer formularen og husker, at brugeren har rørt ved den.
  void _touch(VoidCallback change) => setState(() {
        _touched = true;
        change();
      });

  void _markTouched(String _) => _touched = true;

  RecipeCategory _mapStringToCategory(String cat) {
    switch (cat.toLowerCase()) {
      case 'morgenmad':
        return RecipeCategory.morgenmad;
      case 'frokost':
        return RecipeCategory.frokost;
      case 'snack':
        return RecipeCategory.snack;
      default:
        return RecipeCategory.aftensmad;
    }
  }

  List<DateTime> _generateWeekDates(int offset) {
    // Samme ugeregning som madplanen selv, så datoerne her passer til ugen.
    final now = ref.read(todayProvider);
    return daysOfPlanWeek(planWeekStart(now, ref.read(planStartWeekdayProvider), offset));
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
                    tooltip: 'Luk',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: context.colors.primary),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _activeTab == 0
                            ? 'Tilføj måltid'
                            : 'Tilføj eget måltid',
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
                // Fanen 'Søg opskrifter' har ingen bundknap, så tastaturets højde
                // lægges til her; ellers dækker det filteret og listen.
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, _activeTab == 0 ? sheetBottomInset(context) : 0),
                child: _activeTab == 1
                    ? _buildCustomMealForm()
                    : _buildRecipeSearch(),
              ),
            ),

            // Bottom Button — ekstra plads til hjem-stregen i bunden.
            // Fanen 'Søg opskrifter' gemmer ved tryk på en opskrift.
            if (_activeTab == 1)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, 20 + sheetBottomInset(context)),
                child: Column(
                  children: [
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            style: TextStyle(color: context.colors.error)),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Én node for skærmlæsere: "Gem som opskrift, afkrydsningsfelt".
                    MergeSemantics(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: _saveAsRecipe,
                            onChanged: (v) =>
                                _touch(() => _saveAsRecipe = v ?? false),
                            activeColor: context.colors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                          ),
                          Flexible(
                            child: GestureDetector(
                              onTap: () =>
                                  _touch(() => _saveAsRecipe = !_saveAsRecipe),
                              child: const Text('Gem som opskrift',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saving ? null : _saveMeal,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 20),
                          SizedBox(width: 8),
                          Text('Gem måltid',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
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
      child: Semantics(
        button: true,
        selected: isActive,
        excludeSemantics: true,
        label: label,
        onTap: () => _touch(() => _activeTab = index),
        child: GestureDetector(
          onTap: () => _touch(() => _activeTab = index),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? context.colors.surfaceContainerLowest
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                          color: context.colors.shadow.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? context.colors.primary
                      : context.colors.onSurfaceVariant,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
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
              color: context.colors.outlineVariant,
              style: BorderStyle.solid,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest,
                    shape: BoxShape.circle),
                child: Icon(Icons.add_a_photo_outlined,
                    color: context.colors.outline, size: 24),
              ),
              const SizedBox(height: 12),
              const Text('Tilføj et indbydende billede',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('JPEG eller PNG op til 5MB',
                  style: TextStyle(
                      color: context.colors.onSurfaceVariant, fontSize: 11)),
            ],
          ),
        ),

        const SizedBox(height: 24),
        // Meal Name
        TextField(
          controller: _titleController,
          onChanged: _markTouched,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Hvad skal I have at spise? (f.eks. Rugbrød med pålæg)',
            hintStyle: TextStyle(color: context.colors.outline, fontSize: 15),
            filled: true,
            fillColor: context.colors.surfaceContainerLowest,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),

        const SizedBox(height: 24),
        const Text('Kategori',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        _buildCategoryChips(),

        const SizedBox(height: 24),
        const Text('Personer',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: context.colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(100)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCounterBtn(Icons.remove, 'Færre personer',
                  _portions > 1 ? () => _touch(() => _portions--) : null),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_portions',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('pers.',
                      style: TextStyle(
                          fontSize: 9, color: context.colors.outline)),
                ],
              ),
              const SizedBox(width: 12),
              _buildCounterBtn(
                  Icons.add, 'Flere personer', () => _touch(() => _portions++)),
            ],
          ),
        ),

        const SizedBox(height: 32),
        // Ingredients
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: context.colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ingredienser',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              ...List.generate(
                  _ingredients.length, (index) => _buildIngredientRow(index)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () =>
                    _touch(() => _ingredients.add({'name': '', 'amount': ''})),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: context.colors.primary,
                        style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add,
                            color: context.colors.primary, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text('Tilføj ingrediens',
                              style: TextStyle(
                                  color: context.colors.primary,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text('Noter (valgfrit)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          onChanged: _markTouched,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Tilføj noter eller detaljer...',
            hintStyle: TextStyle(color: context.colors.outline, fontSize: 13),
            filled: true,
            fillColor: context.colors.surfaceContainerLowest,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),

        const SizedBox(height: 24),
        const Text('Vælg dag',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  Widget _buildCategoryChips() {
    return Wrap(
      spacing: 8,
      children: ref
          .watch(householdProvider.select((h) => h.mealTypes))
          .map((t) => t.recipeCategory)
          .map((cat) {
        final isSelected = _selectedCategory == cat;
        return ChoiceChip(
          label: Text(cat.name),
          selected: isSelected,
          onSelected: (v) => _touch(() => _selectedCategory = cat),
          selectedColor: context.colors.primary,
          labelStyle: TextStyle(
            color: isSelected
                ? context.colors.onPrimary
                : context.colors.onSurface,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        );
      }).toList(),
    );
  }

  Widget _buildCounterBtn(IconData icon, String label, VoidCallback? onTap) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: context.colors.surfaceContainerLow,
        foregroundColor: context.colors.primary,
      ),
      icon: Icon(icon, size: 18),
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
            child: _buildMiniField('Hakkede tomater', (v) {
              _touched = true;
              _ingredients[index]['name'] = v;
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMiniField('400g', (v) {
              _touched = true;
              _ingredients[index]['amount'] = v;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniField(String hint, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8)),
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

    return Semantics(
      button: true,
      selected: isSelected,
      container: true,
      child: GestureDetector(
        onTap: () => _touch(() => _selectedDate = date),
        child: Container(
          width: 65,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.primary
                : context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? null
                : Border.all(color: context.colors.surfaceContainerHigh),
          ),
          child: Column(
            children: [
              Text(
                days[date.weekday % 7],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? context.colors.onPrimary.withValues(alpha: 0.8)
                      : context.colors.outline,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? context.colors.onPrimary
                      : context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('Vælg dag',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
              children:
                  _weekDates.map((date) => _buildDateCard(date)).toList()),
        ),
        const SizedBox(height: 24),
        const Text('Måltid',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        _buildCategoryChips(),
        const SizedBox(height: 24),
        const Text('Tryk på en opskrift for at lægge den i madplanen',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        RecipePicker(
          enabled: !_saving,
          onPick: _saveRecipe,
          // Dag og måltid er allerede valgt; kun fanen og titlen skiftes.
          onNoMatch: (query) => _touch(() {
            _titleController.text = query;
            _activeTab = 1;
          }),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(_error!, style: TextStyle(color: context.colors.error)),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  MealType get _mealType => MealType.fromCategory(_selectedCategory)!;
  String get _slotKey => _mealType.key;

  /// Hvad der står på den valgte dag og det valgte måltid lige nu (eller null).
  MealSlot? _currentSlot() {
    final plan = ref.read(mealPlanProvider).valueOrNull;
    final slot = plan?.days[_getDayName(_selectedDate)]?.slot(_mealType);
    if (slot == null) return null;
    final filled = slot.recipeId != null ||
        slot.recipe != null ||
        slot.missingRecipe ||
        (slot.directEntry?.isNotEmpty ?? false);
    return filled ? slot : null;
  }

  /// Er pladsen allerede udfyldt med noget andet, spørges brugeren, før det
  /// overskrives. Returnerer true, hvis der må gemmes.
  Future<bool> _confirmReplace({Recipe? recipe, String? text}) async {
    final current = _currentSlot();
    if (current == null) return true;
    // Samme måltid igen: intet går tabt.
    if (recipe != null && current.recipeId == recipe.id) return true;
    if (text != null &&
        current.recipeId == null &&
        current.directEntry == text) {
      return true;
    }
    final recipesFailed = ref.read(recipesProvider).hasError;
    final oldTitle =
        EditMealSlotSheet.describe(current, recipesFailed: recipesFailed);
    final newTitle = recipe?.title ?? text!;
    final day = _getDayName(_selectedDate).toLowerCase();
    final meal = _mealType.label.toLowerCase();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Erstat $oldTitle?'),
        content: Text(
            '$oldTitle står allerede som $meal $day. Vil du erstatte det med $newTitle?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuller'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erstat'),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// Skriver til madplanen og lukker arket. Venter kun kort på serveren;
  /// offline lukkes arket og skrivningen synkroniseres senere (en sen fejl
  /// meldes på messengeren). Svarer serveren hurtigt med en fejl, bliver
  /// arket åbent med [errorText].
  Future<void> _write(
    Future<void> Function() write, {
    required String lateErrorText,
    required String errorText,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = context.colors.error;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await awaitSlotWrite(
        write(),
        onLateError: (_) => messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(lateErrorText),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
          )),
      );
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText;
        });
      }
    }
  }

  /// Lægger en valgt opskrift på den valgte dag og det valgte måltid.
  Future<void> _saveRecipe(Recipe recipe) async {
    if (_saving) return;
    if (!await _confirmReplace(recipe: recipe)) return;
    final notifier = ref.read(mealPlanProvider.notifier);
    final loc = locate(_selectedDate);
    final slot = _slotKey;
    await _write(
      () => notifier.updateSlot(loc.dayName, slot, recipe: recipe, weekId: loc.weekId),
      lateErrorText: 'Opskriften kunne ikke gemmes i madplanen.',
      errorText:
          'Kunne ikke gemme opskriften. Tjek din forbindelse og prøv igen.',
    );
  }

  Future<void> _saveMeal() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Giv venligst måltidet et navn')));
      return;
    }
    if (!await _confirmReplace(text: title)) return;

    final mealPlan = ref.read(mealPlanProvider.notifier);
    final recipes = ref.read(recipesProvider.notifier);
    final loc = locate(_selectedDate);
    final slot = _slotKey;
    final newRecipe = _saveAsRecipe
        ? Recipe(
            id: '', // Bliver genereret af Firestore
            title: title,
            calories: 0,
            time: '15 min',
            category: _selectedCategory,
            ingredients: ingredientsFromCustomMeal(_ingredients),
          )
        : null;

    await _write(
      () async {
        await mealPlan.updateSlot(loc.dayName, slot,
            directEntry: title, weekId: loc.weekId);
        if (newRecipe != null) await recipes.addRecipe(newRecipe);
      },
      lateErrorText: 'Måltidet kunne ikke gemmes i madplanen.',
      errorText:
          'Kunne ikke gemme måltidet. Tjek din forbindelse og prøv igen.',
    );
  }

  int _getDayIndex(String day) =>
      _weekDates.indexWhere((d) => dayNameOf(d) == day).clamp(0, 6);

  String _getDayName(DateTime date) => dayNameOf(date);
}

/// Ingredienserne fra "Eget måltid" som rigtige [Ingredient]er til "Gem som
/// opskrift": tomme navne springes over, og mængdeteksten deles i mængde og
/// enhed med [parseIngredientAmount]. En mængde uden tal ("efter smag")
/// gemmes uden mængde og står i stedet efter navnet i parentes.
List<Ingredient> ingredientsFromCustomMeal(List<Map<String, String>> rows) => [
      for (final row in rows)
        if ((row['name'] ?? '').trim().isNotEmpty)
          () {
            final amount = parseIngredientAmount(row['amount'] ?? '');
            final name = row['name']!.trim();
            return Ingredient(
              name: amount.note == null ? name : '$name (${amount.note})',
              quantity: amount.quantity,
              unit: amount.unit,
              category: 'Andet',
            );
          }(),
    ];
