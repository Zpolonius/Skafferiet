import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/grocery_item.dart';
import '../../core/models/recurring_item.dart';
import 'grocery_defaults.dart';
import 'grocery_provider.dart';

/// Sentinel for "ingen enhed" – en DropdownMenuItem kan ikke have `null` som
/// en valgbar værdi, der kan skelnes fra "intet valgt".
const _noUnit = '';

/// Returneres fra dialogen, når brugeren vil oprette eller redigere en fast
/// vare. Kalderen åbner så den rette skærm, da dialogen er lukket. [item]
/// har de værdier brugeren lige har gemt.
class ManageRecurringRequest {
  final GroceryItem item;

  const ManageRecurringRequest(this.item);
}

class EditGroceryItemDialog extends ConsumerStatefulWidget {
  final GroceryItem item;

  /// Den faste vare som [item] stammer fra, hvis den stadig er aktiv.
  final RecurringItem? recurringItem;

  const EditGroceryItemDialog({
    super.key,
    required this.item,
    this.recurringItem,
  });

  @override
  ConsumerState<EditGroceryItemDialog> createState() =>
      _EditGroceryItemDialogState();
}

class _EditGroceryItemDialogState extends ConsumerState<EditGroceryItemDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late String _selectedCategory;
  late String _selectedUnit;
  late final List<String> _units;

  bool _isSaving = false;
  String? _nameError;
  String? _quantityError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _quantityController = TextEditingController(text: widget.item.quantity);
    _selectedCategory = widget.item.category;
    _selectedUnit = widget.item.unit ?? _noUnit;

    // Varer fra opskrifter/madplan kan have enheder som 'fed' eller 'spsk'.
    // Dropdown'en kræver at den valgte værdi findes i listen, ellers crasher
    // den – så varens egen enhed tilføjes altid.
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

  bool get _isDirty =>
      _nameController.text.trim() != widget.item.name ||
      _quantityController.text.trim() != widget.item.quantity ||
      _selectedCategory != widget.item.category ||
      (_selectedUnit == _noUnit ? null : _selectedUnit) != widget.item.unit;

  /// Gemmer først eventuelle ændringer, så de ikke går tabt, og lukker så
  /// dialogen med en [ManageRecurringRequest].
  Future<void> _manageRecurring() async {
    if (_isDirty) {
      await _save(manageRecurring: true);
    } else {
      Navigator.pop(context, ManageRecurringRequest(widget.item));
    }
  }

  Future<void> _save({bool manageRecurring = false}) async {
    final name = _nameController.text.trim();
    final quantity = _quantityController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? 'Navn må ikke være tomt' : null;
      _quantityError = quantity.isEmpty ? 'Angiv en mængde' : null;
      _saveError = null;
    });
    if (_nameError != null || _quantityError != null) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(groceryListProvider.notifier).updateItem(
            widget.item.id,
            name: name,
            quantity: quantity,
            unit: _selectedUnit == _noUnit ? null : _selectedUnit,
            category: _selectedCategory,
          );
      if (!mounted) return;
      if (manageRecurring) {
        Navigator.pop(
          context,
          ManageRecurringRequest(GroceryItem(
            id: widget.item.id,
            name: name,
            category: _selectedCategory,
            quantity: quantity,
            unit: _selectedUnit == _noUnit ? null : _selectedUnit,
            imageUrl: widget.item.imageUrl,
            isChecked: widget.item.isChecked,
            source: widget.item.source,
            recurringId: widget.item.recurringId,
            createdAt: widget.item.createdAt,
            sortOrder: widget.item.sortOrder,
          )),
        );
      } else {
        Navigator.pop(context);
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = e.code == 'not-found'
            ? 'Varen findes ikke længere – den er måske slettet af en anden.'
            : 'Kunne ikke gemme ændringerne. Prøv igen.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Kunne ikke gemme ændringerne. Prøv igen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final existingCategories = ref.watch(groceryListProvider).maybeWhen(
          data: (items) => items.map((i) => i.category),
          orElse: () => const <String>[],
        );

    // Den valgte kategori tilføjes altid, så dropdown'en ikke crasher hvis en
    // anden i husstanden fjerner den sidste vare i kategorien imens.
    final allCategories = {
      ...defaultGroceryCategories,
      ...existingCategories,
      _selectedCategory,
    }.toList();

    return AlertDialog(
      title: const Text('Rediger vare'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('edit_name'),
              controller: _nameController,
              enabled: !_isSaving,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Navn',
                hintText: 'Indtast varens navn',
                errorText: _nameError,
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('edit_quantity'),
                    controller: _quantityController,
                    enabled: !_isSaving,
                    maxLength: 10,
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
              items: allCategories
                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('edit_recurring'),
                onPressed: _isSaving ? null : _manageRecurring,
                icon: const Icon(Icons.event_repeat),
                label: Text(
                  widget.recurringItem == null
                      ? 'Køb fast (gentag automatisk)'
                      : 'Fast vare · ${widget.recurringItem!.recurrence.label}',
                ),
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 16),
              Text(
                _saveError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Annuller'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : () => _save(),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Gem'),
        ),
      ],
    );
  }
}
