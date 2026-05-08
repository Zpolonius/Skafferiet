import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/meal_plan.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/profile_avatar.dart';

import 'meal_plan_provider.dart';


import 'add_custom_meal_sheet.dart';

class MealPlanScreen extends ConsumerWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealPlan = ref.watch(mealPlanProvider);
    final selectedDay = ref.watch(selectedDayProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => const AddCustomMealSheet(),
        ),
        label: const Text('Tilføj måltid'),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF0F5238),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: mealPlan.when(
          data: (plan) {
            final dailyPlan = plan.days[selectedDay] ?? DailyPlan.empty();
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Image.asset('assets/images/logo.png', height: 32),
                                const SizedBox(width: 12),
                                Text(
                                  'Madplan',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            const ProfileAvatar(),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SearchBar(),
                        const SizedBox(height: 24),
                        _WeekNavigation(),
                        const SizedBox(height: 16),
                        _WeeklyCarousel(
                          weekStart: mealPlan.value?.weekStart ?? DateTime.now(),
                          selectedDay: selectedDay,
                          onDaySelected: (day) => ref.read(selectedDayProvider.notifier).state = day,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$selectedDay\'s Madplan',
                              style: Theme.of(context).textTheme.displayMedium,
                            ),
                            TextButton.icon(
                              onPressed: () => _transferWeekToShopping(context, ref, plan),
                              icon: const Icon(Icons.sync_alt, size: 18),
                              label: const Text('Overfør til indkøb', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                backgroundColor: AppColors.primaryFixed.withValues(alpha: 0.5),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _MealSection(
                        title: 'Morgenmad',
                        icon: Icons.wb_twilight,
                        slot: dailyPlan.breakfast,
                        onTap: () => _showEditSlot(context, selectedDay, 'Morgenmad', dailyPlan.breakfast),
                      ),
                      _MealSection(
                        title: 'Frokost',
                        icon: Icons.light_mode,
                        slot: dailyPlan.lunch,
                        onTap: () => _showEditSlot(context, selectedDay, 'Frokost', dailyPlan.lunch),
                      ),
                      _MealSection(
                        title: 'Aftensmad',
                        icon: Icons.dark_mode,
                        slot: dailyPlan.dinner,
                        onTap: () => _showEditSlot(context, selectedDay, 'Aftensmad', dailyPlan.dinner),
                      ),
                      _MealSection(
                        title: 'Snack',
                        icon: Icons.cookie,
                        slot: dailyPlan.snack,
                        onTap: () => _showEditSlot(context, selectedDay, 'Snack', dailyPlan.snack),
                      ),
                      const SizedBox(height: 100),
                    ]),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Fejl: $err')),
        ),
      ),
    );
  }

  void _showEditSlot(BuildContext context, String day, String type, MealSlot slot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddCustomMealSheet(initialDay: day, initialCategory: type),
    );
  }

  Future<void> _transferWeekToShopping(BuildContext context, WidgetRef ref, WeeklyMealPlan plan) async {
    final count = await ref.read(mealPlanProvider.notifier).transferToShoppingList();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count varer overført til indkøbslisten'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const TextField(
      decoration: InputDecoration(
        hintText: 'Find opskrifter til din plan...',
        prefixIcon: Icon(Icons.search, color: AppColors.outline),
      ),
    );
  }
}

class _WeeklyCarousel extends StatelessWidget {
  final DateTime weekStart;
  final String selectedDay;
  final ValueChanged<String> onDaySelected;

  const _WeeklyCarousel({
    required this.weekStart,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final days = ['Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'];
    
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        itemBuilder: (context, index) {
          final day = days[index];
          final isSelected = day == selectedDay;
          final date = weekStart.add(Duration(days: index));
          
          return GestureDetector(
            onTap: () => onDaySelected(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 65,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ] : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day.substring(0, 3).toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isSelected ? Colors.white70 : AppColors.outline,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WeekNavigation extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(weekOffsetProvider);
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: offset * 7));
    
    // Beregn ugenummer (simpel version)
    final weekNum = ((weekStart.difference(DateTime(weekStart.year, 1, 1)).inDays) / 7).floor() + 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Uge $weekNum',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryContainer,
          ),
        ),
        Row(
          children: [
            _NavBtn(
              icon: Icons.chevron_left,
              onTap: () => ref.read(weekOffsetProvider.notifier).state--,
            ),
            const SizedBox(width: 8),
            _NavBtn(
              icon: Icons.chevron_right,
              onTap: () => ref.read(weekOffsetProvider.notifier).state++,
            ),
          ],
        ),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final MealSlot slot;
  final VoidCallback onTap;

  const _MealSection({
    required this.title,
    required this.icon,
    required this.slot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.outline),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: slot.recipe != null
              ? _FilledSlotCard(recipe: slot.recipe!)
              : slot.directEntry != null
                  ? _DirectEntryCard(text: slot.directEntry!)
                  : _EmptySlotCard(title: title),
        ),
      ],
    );
  }
}

class _FilledSlotCard extends StatelessWidget {
  final dynamic recipe;

  const _FilledSlotCard({required this.recipe});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: NetworkImage(recipe.imageUrl ?? ''),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipe.title, style: Theme.of(context).textTheme.bodyLarge),
                Text('${recipe.calories} kcal • ${recipe.time}',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.outline),
        ],
      ),
    );
  }
}

class _DirectEntryCard extends StatelessWidget {
  final String text;

  const _DirectEntryCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: AppColors.primary),
          const SizedBox(width: 16),
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
          const Spacer(),
          const Icon(Icons.chevron_right, color: AppColors.outline),
        ],
      ),
    );
  }
}

class _EmptySlotCard extends StatelessWidget {
  final String title;

  const _EmptySlotCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_circle_outline, 
              color: AppColors.primary.withValues(alpha: 0.4),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Tilføj ${title.toLowerCase()}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.outline.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
