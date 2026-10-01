import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/grocery_item.dart';
import '../../core/models/recurrence.dart';
import '../../core/models/recurring_item.dart';
import '../../core/services/recurring_schedule.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/grocery/grocery_defaults.dart';
import '../../features/grocery/grocery_provider.dart';
import '../../features/grocery/recurring/recurrence_picker.dart';
import '../../features/grocery/recurring/recurring_items_provider.dart';
import '../../features/grocery/recurring/recurring_items_service.dart';
import '../../features/profile/household_provider.dart';
import '../utils/danish_dates.dart';
import '../utils/image_upload_service.dart';
import 'app_bottom_sheet.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/theme_context.dart';

class AddGroceryItemSheet extends ConsumerStatefulWidget {
  const AddGroceryItemSheet({super.key});

  @override
  ConsumerState<AddGroceryItemSheet> createState() =>
      _AddGroceryItemSheetState();
}

class _AddGroceryItemSheetState extends ConsumerState<AddGroceryItemSheet> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _customCategoryController = TextEditingController();

  String _selectedCategory = 'Grønt';
  String _selectedUnit = 'stk';
  bool _isAddingCustomCategory = false;
  String? _imageUrl;
  bool _isUploadingImage = false;

  // Fast genkøb
  bool _repeat = false;
  Recurrence _recurrence = const WeeklyRecurrence(1);
  int? _chosenWeekday;
  bool _isSaving = false;
  String? _error;

  final categories = defaultGroceryCategories;
  final units = defaultGroceryUnits;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final quantity = _quantityController.text.trim();
    final category = _selectedCategory.trim();
    if (name.isEmpty) return;
    if (category.isEmpty) {
      setState(() => _error = 'Angiv en kategori');
      return;
    }

    if (!_repeat) {
      ref.read(groceryListProvider.notifier).addItem(
            GroceryItem(
              id: const Uuid().v4(),
              name: name,
              category: category,
              quantity: quantity,
              unit: _selectedUnit,
              source: GroceryItem.sourceManual,
              createdAt: DateTime.now(),
              imageUrl: _imageUrl,
            ),
          );
      Navigator.pop(context);
      return;
    }

    final household = ref.read(householdProvider);
    final householdId = household.householdId;
    final validationError = RecurringItem.validateName(name) ??
        RecurringItem.validateQuantity(quantity) ??
        RecurringItem.validateCategory(category);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    if (_recurrence is WeeklyRecurrence &&
        household.shoppingWeekday == null &&
        _chosenWeekday == null) {
      setState(() => _error = 'Vælg jeres indkøbsdag');
      return;
    }
    if (householdId == null) {
      setState(() => _error = 'Du skal være i en husstand først.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final service = ref.read(recurringItemsServiceProvider);
      final weekday = await service.ensureShoppingWeekday(
        householdId,
        current: household.shoppingWeekday,
        // Kun ugentlige varer sætter husstandens indkøbsdag.
        chosen: _recurrence is WeeklyRecurrence ? _chosenWeekday : null,
        items: ref.read(recurringItemsProvider).valueOrNull ?? const [],
      );
      await service.create(
        householdId,
        RecurringItemDraft(
          name: name,
          quantity: quantity,
          unit: _selectedUnit,
          category: category,
          imageUrl: _imageUrl,
          recurrence: _recurrence,
        ),
        shoppingWeekday: weekday,
        createdBy: ref.read(authProvider).user?.uid ?? '',
      );
      if (!mounted) return;
      final today = dateOnly(ref.read(clockProvider)());
      final first =
          addToListDate(_recurrence.firstDate(today, shoppingWeekday: weekday));
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(
          '$name er gemt som fast vare – første gang på listen: '
          '${formatShortDate(first, today: today)}',
        ),
      ));
    } catch (e) {
      developer.log('Kunne ikke oprette fast vare',
          error: e, name: 'recurring_items');
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Kunne ikke gemme. Tjek din forbindelse og prøv igen.';
      });
    }
  }

  Future<void> _pickImage(BuildContext context) async {
    final householdId = ref.read(householdProvider).householdId;
    final folder = householdId != null
        ? 'households/$householdId/grocery'
        : 'temp/grocery';
    setState(() => _isUploadingImage = true);
    try {
      final url =
          await ImageUploadService.pickAndUpload(context, storagePath: folder);
      if (mounted && url != null) setState(() => _imageUrl = url);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groceryList = ref.watch(groceryListProvider);
    final existingCategories = groceryList.when(
      data: (items) => items.map((i) => i.category).toSet().toList(),
      loading: () => <String>[],
      error: (_, __) => <String>[],
    );

    // Merge predefined with existing
    final allCategories = {...categories, ...existingCategories}.toList();

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context) + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Expanded: titlen ombrydes i stedet for at flyde ud over
                // kanten ved stor skrift (tilgængelighed).
                Expanded(
                  child: Text(
                    'Tilføj vare',
                    style: Theme.of(context).textTheme.displayMedium,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    maxLines: 2,
                    maxLength: RecurringItem.maxNameLength,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'Hvad skal du bruge? (f.eks. Mælk)',
                      prefixIcon: Icon(Icons.shopping_cart_outlined),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _isUploadingImage ? null : () => _pickImage(context),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.outlineVariant),
                      image: _imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _isUploadingImage
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _imageUrl == null
                            ? Icon(Icons.add_a_photo_outlined,
                                color: context.colors.outline)
                            : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    maxLength: RecurringItem.maxQuantityLength,
                    decoration: const InputDecoration(
                      labelText: 'Mængde',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedUnit,
                    decoration: const InputDecoration(labelText: 'Enhed'),
                    items: units
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedUnit = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Kategori', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...allCategories.map((cat) {
                  final isSelected =
                      _selectedCategory == cat && !_isAddingCustomCategory;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        _selectedCategory = cat;
                        _isAddingCustomCategory = false;
                      });
                    },
                  );
                }),
                ChoiceChip(
                  label: const Text('+ Ny'),
                  selected: _isAddingCustomCategory,
                  onSelected: (val) {
                    setState(() {
                      _isAddingCustomCategory = true;
                    });
                  },
                ),
              ],
            ),
            if (_isAddingCustomCategory) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customCategoryController,
                maxLength: RecurringItem.maxCategoryLength,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'Navn på ny kategori...',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('add_repeat_switch'),
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.event_repeat,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Gentag automatisk'),
              subtitle: const Text(
                  'Kommer på listen af sig selv med et fast interval'),
              value: _repeat,
              onChanged: _isSaving
                  ? null
                  : (v) => setState(() {
                        _repeat = v;
                        _error = null;
                      }),
            ),
            if (_repeat) ...[
              const SizedBox(height: 8),
              RecurrencePicker(
                recurrence: _recurrence,
                onChanged: (r) => setState(() => _recurrence = r),
                householdWeekday: ref
                    .watch(householdProvider.select((h) => h.shoppingWeekday)),
                chosenWeekday: _chosenWeekday,
                onWeekdayChanged: (d) => setState(() => _chosenWeekday = d),
                today: dateOnly(ref.watch(clockProvider)()),
                enabled: !_isSaving,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_repeat ? 'Gem som fast vare' : 'Tilføj til liste'),
            ),
          ],
        ),
      ),
    );
  }
}
