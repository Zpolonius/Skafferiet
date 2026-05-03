import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/app_colors.dart';

class AddToMealPlanSheet extends ConsumerStatefulWidget {
  final Recipe recipe;

  const AddToMealPlanSheet({super.key, required this.recipe});

  @override
  ConsumerState<AddToMealPlanSheet> createState() => _AddToMealPlanSheetState();
}

class _AddToMealPlanSheetState extends ConsumerState<AddToMealPlanSheet> {
  String? selectedDay;
  String? selectedSlot;

  final days = ['Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'];
  final slots = ['Morgenmad', 'Frokost', 'Aftensmad', 'Snack'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tilføj til madplan',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.recipe.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          
          Text('Vælg dag', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              itemBuilder: (context, index) {
                final day = days[index];
                final isSelected = selectedDay == day;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(day),
                    selected: isSelected,
                    onSelected: (val) => setState(() => selectedDay = val ? day : null),
                    selectedColor: AppColors.primaryContainer,
                    labelStyle: GoogleFonts.beVietnamPro(
                      color: isSelected ? Colors.white : AppColors.onSurface,
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 24),
          Text('Vælg måltid', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: slots.map((slot) {
              final isSelected = selectedSlot == slot;
              return ChoiceChip(
                label: Text(slot),
                selected: isSelected,
                onSelected: (val) => setState(() => selectedSlot = val ? slot : null),
                selectedColor: AppColors.secondaryContainer,
                labelStyle: GoogleFonts.beVietnamPro(
                  color: isSelected ? AppColors.onSecondaryContainer : AppColors.onSurface,
                  fontSize: 13,
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 32),
          FilledButton(
            onPressed: (selectedDay != null && selectedSlot != null)
                ? () {
                    // TODO: Update the actual meal plan provider
                    // (Requires adding a method to the provider)
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tilføjet til $selectedDay ($selectedSlot)'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Bekræft'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
