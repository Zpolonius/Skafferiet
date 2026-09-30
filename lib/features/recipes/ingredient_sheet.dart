import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/recipe.dart';
import '../../core/models/recipe_units.dart';
import '../../shared/utils/number_format.dart';

/// Åbner bottom sheet til at tilføje eller rette en ingrediens.
/// Returnerer den nye/rettede ingrediens, eller null hvis brugeren fortryder.
Future<Ingredient?> showIngredientSheet(BuildContext context, {Ingredient? initial}) {
  return showModalBottomSheet<Ingredient>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => IngredientSheet(initial: initial),
  );
}

class IngredientSheet extends StatefulWidget {
  final Ingredient? initial;
  const IngredientSheet({super.key, this.initial});

  @override
  State<IngredientSheet> createState() => _IngredientSheetState();
}

class _IngredientSheetState extends State<IngredientSheet> {
  static const _maxNameLength = 60;
  static const _maxKcalPer100 = 900.0; // Rent fedt er ca. 900 kcal pr. 100 g
  static const _maxGramsPer100 = 100.0;

  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _customUnitController;
  late final TextEditingController _kcalController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;

  String _selectedUnit = 'g';
  bool _isCustomUnit = false;
  bool _showNutrition = false;
  bool _submitted = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final ing = widget.initial;
    final n = ing?.nutritionPer100;
    String fmt(double? v) => v == null ? '' : formatDanishNumber(v);

    _nameController = TextEditingController(text: ing?.name ?? '');
    _quantityController = TextEditingController(
      text: ing != null && ing.quantity > 0 ? formatDanishNumber(ing.quantity, maxDecimals: 2) : '',
    );
    _kcalController = TextEditingController(text: fmt(n?.kcal));
    _proteinController = TextEditingController(text: fmt(n?.protein));
    _carbsController = TextEditingController(text: fmt(n?.carbs));
    _fatController = TextEditingController(text: fmt(n?.fat));
    _showNutrition = n != null;

    final unit = ing?.unit.trim() ?? '';
    if (unit.isEmpty) {
      _selectedUnit = 'g';
    } else if (recipeUnits.contains(unit)) {
      _selectedUnit = unit;
    } else {
      _isCustomUnit = true;
    }
    _customUnitController = TextEditingController(text: _isCustomUnit ? unit : '');
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _quantityController,
      _customUnitController,
      _kcalController,
      _proteinController,
      _carbsController,
      _fatController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _unit => _isCustomUnit ? _customUnitController.text.trim() : _selectedUnit;

  // ── Validering ──────────────────────────────────────────────────────────────
  // Fejl vises først, når brugeren har forsøgt at gemme (_submitted).

  String? get _nameError => _nameController.text.trim().isEmpty ? 'Skriv navnet på ingrediensen' : null;

  String? get _quantityError {
    final text = _quantityController.text.trim();
    if (text.isEmpty) return null; // Mængde er valgfri, fx "salt efter smag"
    final v = parseDanishNumber(text);
    if (v == null) return 'Ugyldigt tal';
    if (v > 100000) return 'For stort tal';
    return null;
  }

  String? get _unitError => _isCustomUnit && _customUnitController.text.trim().isEmpty ? 'Skriv en enhed' : null;

  String? _nutritionError(TextEditingController c, double max) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    final v = parseDanishNumber(text);
    if (v == null) return 'Ugyldigt tal';
    if (v > max) return 'Maks. ${formatDanishNumber(max)}';
    return null;
  }

  bool get _nutritionHasErrors =>
      _nutritionFieldsActive &&
      (_nutritionError(_kcalController, _maxKcalPer100) != null ||
          _nutritionError(_proteinController, _maxGramsPer100) != null ||
          _nutritionError(_carbsController, _maxGramsPer100) != null ||
          _nutritionError(_fatController, _maxGramsPer100) != null);

  bool get _nutritionFieldsActive => _showNutrition && canConvertUnit(_unit);

  bool get _hasNutritionInput =>
      [_kcalController, _proteinController, _carbsController, _fatController].any((c) => c.text.trim().isNotEmpty);

  void _submit() {
    setState(() => _submitted = true);
    if (_nameError != null || _quantityError != null || _unitError != null || _nutritionHasErrors) {
      return;
    }

    // Næring gemmes kun, når enheden kan omregnes til gram/ml.
    // Tomme næringsfelter tæller som 0.
    Nutrition? nutrition;
    if (_nutritionFieldsActive && _hasNutritionInput) {
      double read(TextEditingController c) => parseDanishNumber(c.text) ?? 0;
      nutrition = Nutrition(
        kcal: read(_kcalController),
        protein: read(_proteinController),
        carbs: read(_carbsController),
        fat: read(_fatController),
      );
    }

    Navigator.pop(
      context,
      Ingredient(
        name: _nameController.text.trim(),
        quantity: parseDanishNumber(_quantityController.text) ?? 0,
        unit: _unit,
        category: widget.initial?.category ?? 'Andet',
        nutritionPer100: nutrition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Ret ingrediens' : 'Tilføj ingrediens',
                    style: theme.textTheme.displayMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Luk',
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('ingredient-name'),
              controller: _nameController,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxNameLength)],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Ingrediens',
                hintText: 'F.eks. Spaghetti',
                errorText: _submitted ? _nameError : null,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('ingredient-quantity'),
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalInputFormatters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Mængde',
                hintText: 'F.eks. 400 eller 1,5',
                suffixText: _unit,
                errorText: _submitted ? _quantityError : null,
              ),
            ),
            const SizedBox(height: 20),
            Text('Enhed', style: theme.textTheme.labelSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...recipeUnits.map((u) => ChoiceChip(
                      label: Text(u),
                      selected: !_isCustomUnit && _selectedUnit == u,
                      onSelected: (_) => setState(() {
                        _selectedUnit = u;
                        _isCustomUnit = false;
                      }),
                    )),
                ChoiceChip(
                  label: const Text('+ Anden'),
                  selected: _isCustomUnit,
                  onSelected: (_) => setState(() => _isCustomUnit = true),
                ),
              ],
            ),
            if (_isCustomUnit) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('ingredient-custom-unit'),
                controller: _customUnitController,
                autofocus: _customUnitController.text.isEmpty,
                inputFormatters: [LengthLimitingTextInputFormatter(maxCustomUnitLength)],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'F.eks. skive eller knivspids',
                  prefixIcon: const Icon(Icons.straighten),
                  errorText: _submitted ? _unitError : null,
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildNutritionSection(theme),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('ingredient-submit'),
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(_isEditing ? 'Gem ingrediens' : 'Tilføj ingrediens'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionSection(ThemeData theme) {
    final colors = theme.colorScheme;
    final per = isVolumeUnit(_unit) ? '100 ml' : '100 g';

    if (!_showNutrition) {
      return OutlinedButton.icon(
        key: const Key('ingredient-add-nutrition'),
        onPressed: () => setState(() => _showNutrition = true),
        icon: const Icon(Icons.local_fire_department_outlined),
        label: const Text('Tilføj næring pr. 100 g/ml (valgfrit)'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Næring pr. $per', style: theme.textTheme.titleSmall),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _showNutrition = false;
                  for (final c in [_kcalController, _proteinController, _carbsController, _fatController]) {
                    c.clear();
                  }
                }),
                child: const Text('Fjern'),
              ),
            ],
          ),
          if (!canConvertUnit(_unit))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Næring kan kun regnes ud, når enheden er g, kg, ml, dl, l, tsk eller spsk. '
                'Vælg en af dem, eller angiv næringen samlet på opskriften.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else ...[
            Text(
              'Se varedeklarationen på pakken. Tomme felter tæller som 0.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _nutritionField('Energi', 'kcal', _kcalController, _maxKcalPer100)),
                const SizedBox(width: 12),
                Expanded(child: _nutritionField('Protein', 'g', _proteinController, _maxGramsPer100)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _nutritionField('Kulhydrat', 'g', _carbsController, _maxGramsPer100)),
                const SizedBox(width: 12),
                Expanded(child: _nutritionField('Fedt', 'g', _fatController, _maxGramsPer100)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _nutritionField(String label, String suffix, TextEditingController c, double max) {
    return TextField(
      key: Key('ingredient-nutrition-$label'),
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: decimalInputFormatters,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        errorText: _submitted ? _nutritionError(c, max) : null,
      ),
    );
  }
}
