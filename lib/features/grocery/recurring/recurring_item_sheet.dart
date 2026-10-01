import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/grocery_item.dart';
import '../../../core/models/recurrence.dart';
import '../../../core/models/recurring_item.dart';
import '../../../core/services/recurring_schedule.dart';
import '../../../shared/utils/image_upload_service.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../auth/auth_provider.dart';
import '../../profile/household_provider.dart';
import '../grocery_defaults.dart';
import '../grocery_provider.dart';
import 'recurrence_picker.dart';
import 'recurring_items_provider.dart';
import 'recurring_items_service.dart';

/// Sentinel for "ingen enhed" i dropdown'en.
const _noUnit = '';

/// Opretter eller redigerer en fast vare.
///
/// - [existing] sat: redigér den faste vare (og mulighed for at stoppe den).
/// - [fromGroceryItem] sat: gør en vare på indkøbslisten til en fast vare.
class RecurringItemSheet extends ConsumerStatefulWidget {
  final RecurringItem? existing;
  final GroceryItem? fromGroceryItem;

  const RecurringItemSheet({super.key, this.existing, this.fromGroceryItem})
      : assert(existing == null || fromGroceryItem == null);

  static Future<void> show(
    BuildContext context, {
    RecurringItem? existing,
    GroceryItem? fromGroceryItem,
  }) {
    return showAppBottomSheet(
      context: context,
      builder: (_) => RecurringItemSheet(
        existing: existing,
        fromGroceryItem: fromGroceryItem,
      ),
    );
  }

  @override
  ConsumerState<RecurringItemSheet> createState() => _RecurringItemSheetState();
}

class _RecurringItemSheetState extends ConsumerState<RecurringItemSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late String _selectedUnit;
  late String _selectedCategory;
  late final List<String> _units;
  late Recurrence _recurrence;
  String? _imageUrl;
  int? _chosenWeekday;

  bool _isSaving = false;
  bool _isUploadingImage = false;
  String? _nameError;
  String? _quantityError;
  String? _saveError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final grocery = widget.fromGroceryItem;
    _nameController =
        TextEditingController(text: existing?.name ?? grocery?.name ?? '');
    _quantityController = TextEditingController(
        text: existing?.quantity ?? grocery?.quantity ?? '1');
    _selectedUnit = existing != null
        ? existing.unit ?? _noUnit
        : grocery != null
            ? grocery.unit ?? _noUnit
            : 'stk';
    _selectedCategory = existing?.category ?? grocery?.category ?? 'Andet';
    _imageUrl = existing?.imageUrl ?? grocery?.imageUrl;
    _recurrence = existing?.recurrence ?? const WeeklyRecurrence(1);
    _units = [
      _noUnit,
      ...defaultGroceryUnits,
      if (!defaultGroceryUnits.contains(_selectedUnit) &&
          _selectedUnit != _noUnit)
        _selectedUnit,
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;
    setState(() => _isUploadingImage = true);
    try {
      final url = await ImageUploadService.pickAndUpload(context,
          storagePath: 'households/$householdId/grocery');
      if (mounted && url != null) setState(() => _imageUrl = url);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final quantity = _quantityController.text.trim();
    final household = ref.read(householdProvider);
    final householdId = household.householdId;
    final needsWeekday = _recurrence is WeeklyRecurrence &&
        household.shoppingWeekday == null &&
        _chosenWeekday == null;

    final categoryError = RecurringItem.validateCategory(_selectedCategory);
    setState(() {
      _nameError = RecurringItem.validateName(name);
      _quantityError = RecurringItem.validateQuantity(quantity);
      _saveError = needsWeekday ? 'Vælg jeres indkøbsdag' : categoryError;
    });
    if (_nameError != null || _quantityError != null || _saveError != null) {
      return;
    }
    if (householdId == null) {
      setState(() => _saveError = 'Du skal være i en husstand først.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final service = ref.read(recurringItemsServiceProvider);
      final items = ref.read(recurringItemsProvider).valueOrNull ?? const [];
      final weekday = await service.ensureShoppingWeekday(
        householdId,
        current: household.shoppingWeekday,
        // Kun ugentlige varer sætter husstandens indkøbsdag.
        chosen: _recurrence is WeeklyRecurrence ? _chosenWeekday : null,
        items: items,
      );
      final draft = RecurringItemDraft(
        name: name,
        quantity: quantity,
        unit: _selectedUnit == _noUnit ? null : _selectedUnit,
        category: _selectedCategory,
        imageUrl: _imageUrl,
        recurrence: _recurrence,
      );
      final existing = widget.existing;
      if (existing != null) {
        await service.update(householdId, existing, draft,
            shoppingWeekday: weekday);
      } else {
        await service.create(
          householdId,
          draft,
          shoppingWeekday: weekday,
          createdBy: ref.read(authProvider).user?.uid ?? '',
          linkGroceryItemId: widget.fromGroceryItem?.id,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      developer.log('Kunne ikke gemme fast vare',
          error: e, name: 'recurring_items');
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Kunne ikke gemme. Tjek din forbindelse og prøv igen.';
      });
    }
  }

  Future<void> _confirmStop() async {
    final existing = widget.existing!;
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop fast genkøb?'),
        content: Text(
          '"${existing.name}" bliver ikke længere tilføjet automatisk. '
          'Varer der allerede står på indkøbslisten bliver der.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuller'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(recurringItemsServiceProvider)
          .delete(householdId, existing.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      developer.log('Kunne ikke stoppe fast vare',
          error: e, name: 'recurring_items');
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Kunne ikke stoppe. Tjek din forbindelse og prøv igen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final householdWeekday =
        ref.watch(householdProvider.select((h) => h.shoppingWeekday));
    final existingCategories = ref.watch(groceryListProvider).maybeWhen(
          data: (items) => items.map((i) => i.category),
          orElse: () => const <String>[],
        );
    final categories = {
      ...defaultGroceryCategories,
      ...existingCategories,
      _selectedCategory,
    }.toList();
    final today = dateOnly(ref.watch(clockProvider)());

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context) + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Rediger fast vare' : 'Ny fast vare',
                    style: textTheme.displayMedium,
                  ),
                ),
                IconButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
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
                    key: const Key('recurring_name'),
                    controller: _nameController,
                    enabled: !_isSaving,
                    autofocus: !_isEditing && widget.fromGroceryItem == null,
                    maxLength: RecurringItem.maxNameLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Vare',
                      hintText: 'F.eks. Mælk',
                      errorText: _nameError,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _ImageButton(
                  imageUrl: _imageUrl,
                  isUploading: _isUploadingImage,
                  onTap: _isSaving || _isUploadingImage ? null : _pickImage,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('recurring_quantity'),
                    controller: _quantityController,
                    enabled: !_isSaving,
                    maxLength: RecurringItem.maxQuantityLength,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Mængde',
                      errorText: _quantityError,
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
                    items: _units
                        .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(u == _noUnit ? '—' : u),
                            ))
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (v) => setState(() => _selectedUnit = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 24),
            RecurrencePicker(
              recurrence: _recurrence,
              onChanged: (r) => setState(() => _recurrence = r),
              householdWeekday: householdWeekday,
              chosenWeekday: _chosenWeekday,
              onWeekdayChanged: (d) => setState(() => _chosenWeekday = d),
              today: today,
              savedRecurrence: widget.existing?.recurrence,
              savedNextDate: widget.existing?.nextDate,
              enabled: !_isSaving,
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 16),
              Text(
                _saveError!,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
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
                  : Text(_isEditing ? 'Gem ændringer' : 'Gem fast vare'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _confirmStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop fast genkøb'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  foregroundColor: colorScheme.error,
                  side: BorderSide(color: colorScheme.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageButton extends StatelessWidget {
  final String? imageUrl;
  final bool isUploading;
  final VoidCallback? onTap;

  const _ImageButton({
    required this.imageUrl,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: imageUrl == null ? 'Tilføj billede' : 'Skift billede',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
            image: imageUrl != null
                ? DecorationImage(
                    image: NetworkImage(imageUrl!), fit: BoxFit.cover)
                : null,
          ),
          child: isUploading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : imageUrl == null
                  ? Icon(Icons.add_a_photo_outlined,
                      color: colorScheme.onSurfaceVariant)
                  : null,
        ),
      ),
    );
  }
}
