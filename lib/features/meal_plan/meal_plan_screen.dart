import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'meal_plan_provider.dart';
import '../../core/models/meal_plan.dart';
import '../../core/theme/app_colors.dart';

class MealPlanScreen extends ConsumerWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealPlan = ref.watch(mealPlanProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final dailyPlan = mealPlan.days[selectedDay] ?? DailyPlan.empty();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kitchen Harmony',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SearchBar(),
                    const SizedBox(height: 24),
                    _WeeklyCarousel(
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryFixed,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '1,850 kcal',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.primary,
                                ),
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
                  ),
                  _MealSection(
                    title: 'Frokost',
                    icon: Icons.light_mode,
                    slot: dailyPlan.lunch,
                  ),
                  _MealSection(
                    title: 'Aftensmad',
                    icon: Icons.dark_mode,
                    slot: dailyPlan.dinner,
                  ),
                  _MealSection(
                    title: 'Snack',
                    icon: Icons.cookie,
                    slot: dailyPlan.snack,
                  ),
                  const SizedBox(height: 100),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
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
  final String selectedDay;
  final ValueChanged<String> onDaySelected;

  const _WeeklyCarousel({required this.selectedDay, required this.onDaySelected});

  @override
  Widget build(BuildContext context) {
    final days = ['Søn', 'Man', 'Tirs', 'Ons', 'Tors', 'Fre', 'Lør'];
    final fullDays = ['Søndag', 'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag'];
    
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        itemBuilder: (context, index) {
          final isSelected = selectedDay == fullDays[index];
          return GestureDetector(
            onTap: () => onDaySelected(fullDays[index]),
            child: Container(
              width: 64,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: isSelected ? null : Border.all(color: AppColors.outlineVariant),
                boxShadow: isSelected
                    ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 8))]
                    : [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    days[index],
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white.withValues(alpha: 0.9) : AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${11 + index}', // Mock date
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
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

class _MealSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final MealSlot slot;

  const _MealSection({required this.title, required this.icon, required this.slot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.tertiaryContainer),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.tertiaryContainer,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        if (slot.recipe != null)
          _FilledSlotCard(recipe: slot.recipe!)
        else if (slot.directEntry != null)
          _DirectEntryCard(text: slot.directEntry!)
        else
          _EmptySlotCard(title: title),
      ],
    );
  }
}

class _FilledSlotCard extends StatelessWidget {
  final dynamic recipe; // Recipe model

  const _FilledSlotCard({required this.recipe});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: [
          BoxShadow(color: AppColors.primaryContainer.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              recipe.imageUrl ?? 'https://via.placeholder.com/88',
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 14, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('15m', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(width: 12),
                    const Icon(Icons.local_fire_department, size: 14, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('420 cal', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.more_vert, color: AppColors.outline),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.secondaryContainer, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text('Direkte indtastning', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.shopping_basket, size: 18),
            label: const Text('Tilføj'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.tertiaryFixed,
              foregroundColor: AppColors.onTertiaryFixed,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
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
      height: 104,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, style: BorderStyle.none), // Mocking dashed border with CustomPainter would be better
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppColors.primaryFixed, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: AppColors.primaryContainer),
              ),
              const SizedBox(height: 8),
              Text(
                'Tilføj opskrift til $title',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// Note: In a real app, I'd use a CustomPainter for the dashed border of the empty card.
