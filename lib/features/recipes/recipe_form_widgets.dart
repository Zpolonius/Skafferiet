import 'package:flutter/material.dart';
import '../../core/models/recipe.dart';
import '../../core/services/nutrition_calculator.dart';
import '../../shared/utils/number_format.dart';
import '../../core/theme/theme_context.dart';
import 'ingredient_sheet.dart';

/// "400 g", "1,5 dl" eller bare "fed" hvis der ikke er en mængde.
String formatIngredientAmount(Ingredient ing) {
  final qty = ing.quantity > 0 ? formatDanishNumber(ing.quantity, maxDecimals: 2) : '';
  return [qty, ing.unit.trim()].where((s) => s.isNotEmpty).join(' ');
}

// ── Ingredienser ──────────────────────────────────────────────────────────────

/// Liste over ingredienser. Tryk på en linje for at rette den i et bottom sheet.
class IngredientListEditor extends StatelessWidget {
  final List<Ingredient> ingredients;
  final ValueChanged<List<Ingredient>> onChanged;

  const IngredientListEditor({super.key, required this.ingredients, required this.onChanged});

  Future<void> _edit(BuildContext context, int index) async {
    final updated = await showIngredientSheet(context, initial: ingredients[index]);
    if (updated == null) return;
    onChanged([...ingredients]..[index] = updated);
  }

  Future<void> _add(BuildContext context) async {
    final added = await showIngredientSheet(context);
    if (added == null) return;
    onChanged([...ingredients, added]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ingredients.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Ingen ingredienser endnu.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ...ingredients.asMap().entries.map((entry) {
          final idx = entry.key;
          final ing = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _edit(context, idx),
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        formatIngredientAmount(ing),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(ing.name, style: theme.textTheme.bodyMedium),
                    ),
                    if (ing.nutritionPer100 != null)
                      Tooltip(
                        message: 'Har næring pr. 100 g/ml',
                        child: Icon(Icons.local_fire_department_outlined, size: 18, color: colors.secondary),
                      ),
                    IconButton(
                      tooltip: 'Fjern ${ing.name}',
                      onPressed: () => onChanged([...ingredients]..removeAt(idx)),
                      icon: Icon(Icons.remove_circle_outline, color: colors.error),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const Key('add-ingredient'),
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: const Text('Tilføj ingrediens'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        ),
      ],
    );
  }
}

// ── Portioner ─────────────────────────────────────────────────────────────────

/// Stepper til antal portioner. Null betyder "ikke angivet".
class ServingsStepper extends StatelessWidget {
  static const maxServings = 50;

  final int? value;
  final ValueChanged<int?> onChanged;

  const ServingsStepper({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Portioner', style: theme.textTheme.titleSmall),
              Text(
                'Bruges til næring pr. portion',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          tooltip: 'Færre portioner',
          // Fra 1 går man tilbage til "ikke angivet".
          onPressed: v == null ? null : () => onChanged(v > 1 ? v - 1 : null),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 44,
          child: Semantics(
            label: 'Antal portioner',
            value: v?.toString() ?? 'ikke angivet',
            child: ExcludeSemantics(
              child: Text(
                v?.toString() ?? '–',
                key: const Key('servings-value'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Flere portioner',
          onPressed: (v ?? 0) >= maxServings ? null : () => onChanged((v ?? 0) + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

// ── Næring pr. portion ────────────────────────────────────────────────────────

/// Værdierne der gemmes på opskriften.
class ResolvedNutrition {
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final bool fromIngredients;

  const ResolvedNutrition({
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    required this.fromIngredients,
  });
}

/// Holder de fire felter for næring pr. portion.
/// Et tomt felt betyder "brug beregningen fra ingredienserne" (hvis der er en).
class NutritionFormControllers {
  static const maxKcal = 10000.0;
  static const maxGrams = 1000.0;

  final kcal = TextEditingController();
  final protein = TextEditingController();
  final carbs = TextEditingController();
  final fat = TextEditingController();

  List<TextEditingController> get all => [kcal, protein, carbs, fat];

  /// Fylder felterne fra en gemt opskrift. Hvis tallene tidligere blev
  /// beregnet fra ingredienserne, lades felterne tomme, så beregningen
  /// følger med, når ingredienserne ændres.
  void loadFrom(Recipe recipe) {
    if (recipe.nutritionFromIngredients) return;
    String fmt(double? v) => v == null ? '' : formatDanishNumber(v);
    kcal.text = recipe.calories > 0 ? recipe.calories.toString() : '';
    protein.text = fmt(recipe.protein);
    carbs.text = fmt(recipe.carbs);
    fat.text = fmt(recipe.fat);
  }

  static String? errorFor(TextEditingController c, double max) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    final v = parseDanishNumber(text);
    if (v == null) return 'Ugyldigt tal';
    if (v > max) return 'Maks. ${formatDanishNumber(max)}';
    return null;
  }

  bool get hasErrors =>
      errorFor(kcal, maxKcal) != null ||
      errorFor(protein, maxGrams) != null ||
      errorFor(carbs, maxGrams) != null ||
      errorFor(fat, maxGrams) != null;

  /// Kombinerer brugerens tal med beregningen: det brugeren har skrevet vinder.
  ResolvedNutrition resolve(Nutrition? calculated) {
    double? round1(double v) => (v * 10).roundToDouble() / 10;
    double? field(TextEditingController c, double? fallback) {
      final v = parseDanishNumber(c.text);
      if (v != null) return v;
      return fallback == null ? null : round1(fallback);
    }

    final allEmpty = all.every((c) => c.text.trim().isEmpty);
    return ResolvedNutrition(
      calories: (parseDanishNumber(kcal.text) ?? calculated?.kcal ?? 0).round(),
      protein: field(protein, calculated?.protein),
      carbs: field(carbs, calculated?.carbs),
      fat: field(fat, calculated?.fat),
      fromIngredients: allEmpty && calculated != null,
    );
  }

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

/// Felterne for kalorier, protein, kulhydrat og fedt pr. portion.
/// Tomme felter viser den beregnede værdi i gråt og bruger den ved gem.
class NutritionFields extends StatelessWidget {
  final NutritionFormControllers controllers;
  final NutritionCalculation calculation;
  final int? servings;
  final bool showErrors;
  final VoidCallback onChanged;

  const NutritionFields({
    super.key,
    required this.controllers,
    required this.calculation,
    required this.servings,
    required this.showErrors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perServing = calculation.perServing(servings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoBanner(calculation: calculation, servings: servings),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(theme, 'Kalorier', 'kcal', controllers.kcal, NutritionFormControllers.maxKcal,
                  perServing?.kcal.roundToDouble()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                  theme, 'Protein', 'g', controllers.protein, NutritionFormControllers.maxGrams, perServing?.protein),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                  theme, 'Kulhydrat', 'g', controllers.carbs, NutritionFormControllers.maxGrams, perServing?.carbs),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(theme, 'Fedt', 'g', controllers.fat, NutritionFormControllers.maxGrams, perServing?.fat),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(ThemeData theme, String label, String suffix, TextEditingController c, double max, double? calculated) {
    return TextField(
      key: Key('recipe-nutrition-$label'),
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: decimalInputFormatters,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        // Label svæver altid, så den beregnede værdi kan ses som hint.
        floatingLabelBehavior: calculated != null ? FloatingLabelBehavior.always : null,
        hintText: calculated != null ? formatDanishNumber(calculated) : null,
        errorText: showErrors ? NutritionFormControllers.errorFor(c, max) : null,
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final NutritionCalculation calculation;
  final int? servings;

  const _InfoBanner({required this.calculation, required this.servings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final IconData icon;
    final String text;
    if (!calculation.hasData) {
      icon = Icons.lightbulb_outline;
      text = 'Skriv næringen pr. portion her – eller tilføj næring pr. 100 g/ml '
          'på ingredienserne, så regner appen det ud for dig.';
    } else if (servings == null) {
      icon = Icons.info_outline;
      text = 'Angiv antal portioner ovenfor, så regner appen næringen pr. portion '
          'ud fra ingredienserne.';
    } else {
      icon = Icons.calculate_outlined;
      final c = calculation;
      final count = c.countedIngredients == c.totalIngredients
          ? 'alle ${c.totalIngredients} ingredienser'
          : '${c.countedIngredients} af ${c.totalIngredients} ingredienser';
      text = 'Beregnet ud fra $count. Tomme felter udfyldes automatisk – '
          'skriv selv et tal for at overskrive.';
    }

    return Container(
      key: const Key('nutrition-info'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fremgangsmåde ─────────────────────────────────────────────────────────────

/// Grænser for fremgangsmåden. Antallet håndhæves også af `firestore.rules`;
/// tegn pr. trin kan reglerne ikke tjekke (de kan ikke løbe en liste igennem),
/// så det holdes kun her i appen.
const int maxRecipeSteps = 50;
const int maxRecipeStepLength = 1000;

/// Trimmer trinene og fjerner tomme, så kun rigtige trin gemmes.
List<String> cleanInstructions(Iterable<String> steps) =>
    steps.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

class _StepEntry {
  final int id;
  final TextEditingController controller;
  final bool autofocus;
  _StepEntry(this.id, String text, {this.autofocus = false})
      : controller = TextEditingController(text: text);
}

/// Nummererede trin som kan rettes, slettes og flyttes (træk i håndtaget eller
/// med "Flyt op"/"Flyt ned"). Fælles for opret- og redigeringsskærmen.
/// `onChanged` får de rå tekster; kald [cleanInstructions] ved gem.
class RecipeStepsEditor extends StatefulWidget {
  final List<String> initialSteps;
  final ValueChanged<List<String>> onChanged;

  const RecipeStepsEditor(
      {super.key, this.initialSteps = const [], required this.onChanged});

  @override
  State<RecipeStepsEditor> createState() => _RecipeStepsEditorState();
}

class _RecipeStepsEditorState extends State<RecipeStepsEditor> {
  late final List<_StepEntry> _entries;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _entries = [for (final s in widget.initialSteps) _StepEntry(_nextId++, s)];
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.controller.dispose();
    }
    super.dispose();
  }

  void _notify() =>
      widget.onChanged(_entries.map((e) => e.controller.text).toList());

  void _add() {
    if (_entries.length >= maxRecipeSteps) return;
    setState(() => _entries.add(_StepEntry(_nextId++, '', autofocus: true)));
    _notify();
  }

  void _remove(int index) {
    final removed = _entries.removeAt(index);
    setState(() {});
    // Controlleren bruges stadig af det felt der er ved at forsvinde.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => removed.controller.dispose());
    _notify();
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _entries.length || from == to) return;
    setState(() => _entries.insert(to, _entries.removeAt(from)));
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final atLimit = _entries.length >= maxRecipeSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _entries.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            _move(oldIndex, newIndex);
          },
          itemBuilder: (context, i) {
            final entry = _entries[i];
            return Padding(
              key: ValueKey(entry.id),
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                // Eget semantik-kort: ellers flettes kortet (inkl. knapperne) ind i
                // tekstfeltets node, og feltet dækker knapperne for skærmlæsere/web.
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextField(
                          controller: entry.controller,
                          autofocus: entry.autofocus,
                          maxLength: maxRecipeStepLength,
                          minLines: 1,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          // Plads under feltet, så tastaturet ikke dækker det.
                          scrollPadding:
                              const EdgeInsets.fromLTRB(20, 20, 20, 160),
                          buildCounter: (context,
                                  {required currentLength,
                                  required isFocused,
                                  maxLength}) =>
                              currentLength >= 900
                                  ? Text('$currentLength/$maxLength')
                                  : null,
                          decoration: InputDecoration(
                              labelText: 'Trin ${i + 1}',
                              hintText: 'Beskriv trinnet'),
                          onChanged: (_) => _notify(),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Flyt op',
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: const Icon(Icons.keyboard_arrow_up),
                            onPressed: i == 0 ? null : () => _move(i, i - 1),
                          ),
                          IconButton(
                            tooltip: 'Flyt ned',
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: const Icon(Icons.keyboard_arrow_down),
                            onPressed: i == _entries.length - 1
                                ? null
                                : () => _move(i, i + 1),
                          ),
                          IconButton(
                            tooltip: 'Slet trin',
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon:
                                Icon(Icons.delete_outline, color: colors.error),
                            onPressed: () => _remove(i),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Tooltip(
                              message: 'Træk for at flytte',
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(Icons.drag_indicator,
                                    color: colors.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: atLimit ? null : _add,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.add),
            label: const Text('Tilføj trin'),
          ),
        ),
        if (atLimit)
          Text(
            'Du kan højst have $maxRecipeSteps trin',
            style: context.text.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
      ],
    );
  }
}

// ── Deling ────────────────────────────────────────────────────────────────────

/// Valg om opskriften kun er for husstanden (standard) eller deles med alle
/// brugere af appen, med en forklaring af hvad det betyder.
class ShareRecipeSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Falsk når brugeren ikke selv har lavet opskriften: kun skaberen må dele
  /// den med alle, men enhver i husstanden kan holde op med at dele den.
  final bool canShare;

  const ShareRecipeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.canShare = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Del med alle brugere',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch(
                    key: const Key('share-recipe-switch'),
                    value: value,
                    onChanged: (value || canShare) ? onChanged : null,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              !canShare && !value
                  ? 'Kun den, der har lavet opskriften, kan dele den med alle'
                  : !canShare
                  ? 'Delt med alle brugere af den, der har lavet opskriften, under '
                      'skaberens fornavn. Du kan slå deling fra for jeres husstand, men '
                      'kun skaberen kan dele den igen.'
                  : value
                  ? 'Alle brugere af appen kan se, søge i og gemme en kopi af opskriften: '
                      'titel, billede, ingredienser, fremgangsmåde, næring og dit fornavn. '
                      'Kun jeres husstand kan redigere eller slette den. Du kan slå deling '
                      'fra igen når som helst. Et billedlink, som andre allerede har åbnet, '
                      'kan dog stadig virke bagefter.'
                  : 'Slået fra: kun din husstand kan se opskriften. Slå til for at dele den '
                      'med alle brugere af appen. Så kan de se titel, billede, ingredienser, '
                      'fremgangsmåde, næring og dit fornavn. Du kan altid slå deling fra igen, '
                      'men et billedlink, som andre allerede har åbnet, kan stadig virke.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
