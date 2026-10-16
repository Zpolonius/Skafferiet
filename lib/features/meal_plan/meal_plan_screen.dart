import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/models/grocery_item.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/meal_type.dart';
import '../../core/services/week_copy.dart';
import '../../core/services/week_dates.dart';
import '../../shared/widgets/profile_avatar.dart';
import '../grocery/grocery_provider.dart';
import '../profile/household_provider.dart';
import '../recipes/recipes_provider.dart';
import 'meal_plan_provider.dart';

import '../../shared/widgets/app_bottom_sheet.dart';
import 'add_custom_meal_sheet.dart';
import 'edit_meal_slot_sheet.dart';
import 'meal_types_sheet.dart';
import '../../core/theme/theme_context.dart';

class MealPlanScreen extends ConsumerWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealPlan = ref.watch(mealPlanProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final mealTypes = ref.watch(householdProvider.select((h) => h.mealTypes));
    final offset = ref.watch(weekOffsetProvider);
    final today = ref.watch(todayProvider);
    final weekStart = addWeeks(weekStartOf(today), offset);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAppBottomSheet(
          context: context,
          builder: (context) => AddCustomMealSheet(initialDay: selectedDay),
        ),
        label: const Text('Tilføj måltid'),
        icon: const Icon(Icons.add),
        backgroundColor: context.colors.primary,
        foregroundColor: context.colors.onPrimary,
      ),
      body: SafeArea(
        child: mealPlan.when(
          skipLoadingOnReload: true,
          data: (plan) {
            final dailyPlan = plan.days[selectedDay] ?? DailyPlan.empty();
            final calories = dailyPlan.totalCaloriesFor(mealTypes);
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
                                  style: context.text.headlineLarge?.copyWith(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: context.colors.primaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            const ProfileAvatar(),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const _SearchBar(),
                        const SizedBox(height: 24),
                        _WeekNavigation(weekStart: weekStart, offset: offset, today: today),
                        if (offset == 0 && today.weekday >= DateTime.saturday)
                          const _WeekendHint(),
                        _CopyOffer(
                          plan: plan,
                          weekStart: weekStart,
                          offset: offset,
                          loading: mealPlan.isLoading,
                        ),
                        const SizedBox(height: 16),
                        _WeeklyCarousel(
                          weekStart: weekStart,
                          selectedDay: selectedDay,
                          onDaySelected: (day) => ref.read(selectedDayProvider.notifier).state = day,
                        ),
                        const SizedBox(height: 24),
                        // Wrap: på en smal telefon (fx 390 pt) ryger knappen ned
                        // på næste linje i stedet for at løbe ud over kanten.
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${selectedDay}ens madplan',
                                  style: context.text.displayMedium,
                                ),
                                if (calories > 0) ...[
                                  const SizedBox(width: 10),
                                  Tooltip(
                                    message: 'Beregnet ud fra opskrifter i madplanen',
                                    triggerMode: TooltipTriggerMode.tap,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: context.colors.secondaryFixed,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.local_fire_department,
                                            size: 14,
                                            color: context.colors.secondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${NumberFormat('#,###', 'da_DK').format(calories)} kcal',
                                            style: context.text.titleSmall?.copyWith(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: context.colors.onSecondaryFixedVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () => _transferWeekToShopping(context, ref, plan),
                              icon: const Icon(Icons.sync_alt, size: 18),
                              label: const Text('Overfør til indkøb', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: context.colors.primary,
                                backgroundColor: context.colors.primaryFixed.withValues(alpha: 0.5),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                            ),
                          ],
                        ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      for (final type in mealTypes)
                        _MealSection(
                          title: type.label,
                          icon: type.icon,
                          slot: dailyPlan.slot(type),
                          onTap: () => _showEditSlot(context, selectedDay, type, dailyPlan.slot(type)),
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

  /// Et udfyldt måltid (opskrift, eget måltid eller slettet opskrift) åbner
  /// redigeringsarket; et tomt åbner "Tilføj måltid" på den dag og det måltid.
  void _showEditSlot(BuildContext context, String day, MealType type, MealSlot slot) {
    // recipeId er sat for både opskrifter, slettede opskrifter og opskrifter
    // der ikke er indlæst endnu.
    final filled = slot.recipeId != null || slot.directEntry != null;
    showAppBottomSheet(
      context: context,
      builder: (context) => filled
          ? EditMealSlotSheet(day: day, mealType: type, slot: slot)
          : AddCustomMealSheet(initialDay: day, initialCategory: type.label),
    );
  }

  Future<void> _transferWeekToShopping(BuildContext context, WidgetRef ref, WeeklyMealPlan plan) async {
    final count = await ref.read(mealPlanProvider.notifier).transferToShoppingList();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count varer overført til indkøbslisten'),
          backgroundColor: context.colors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Ser ud som et søgefelt, men åbner Opskrifter med markøren i søgefeltet dér.
/// Så findes søgningen ét sted, og fra en opskrift kan man lægge den i madplanen.
class _SearchBar extends ConsumerWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextField(
      readOnly: true,
      onTap: () {
        ref.read(focusRecipeSearchProvider.notifier).state = true;
        context.go('/recipes');
      },
      decoration: InputDecoration(
        hintText: 'Find opskrifter til din plan...',
        prefixIcon: Icon(Icons.search, color: context.colors.outline),
        suffixIcon: Icon(Icons.chevron_right, color: context.colors.outline),
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
          final date = daysOfWeek(weekStart)[index];
          
          return GestureDetector(
            onTap: () => onDaySelected(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 65,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? context.colors.primary : context.colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? context.colors.primary : context.colors.outlineVariant,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: context.colors.primary.withValues(alpha: 0.2),
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
                      color: isSelected ? context.colors.onPrimary.withValues(alpha: 0.7) : context.colors.outline,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: context.text.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? context.colors.onPrimary : context.colors.onSurface,
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

/// Overskrift med ugenummer og datoer, "Denne uge"/"Næste uge"/"Sidste uge"-
/// badge og knapperne til at skifte uge.
class _WeekNavigation extends ConsumerWidget {
  final DateTime weekStart;
  final int offset;
  final DateTime today;

  const _WeekNavigation({
    required this.weekStart,
    required this.offset,
    required this.today,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = weekBadgeLabel(offset);
    void setOffset(int value) => ref.read(weekOffsetProvider.notifier).state = value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  label: weekSemanticsLabel(weekStart, offset: offset, today: today),
                  excludeSemantics: true,
                  child: Text(
                    weekHeaderLabel(weekStart, today: today),
                    style: context.text.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.colors.primaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (badge != null) _WeekBadge(label: badge, isCurrent: offset == 0),
                    if (offset != 0)
                      TextButton(
                        onPressed: () => setOffset(0),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Gå til denne uge', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _NavBtn(
          icon: Icons.tune,
          tooltip: 'Mine måltider',
          onTap: () => MealTypesSheet.show(context),
        ),
        const SizedBox(width: 4),
        _NavBtn(
          icon: Icons.chevron_left,
          tooltip: 'Forrige uge',
          onTap: () => setOffset(offset - 1),
        ),
        const SizedBox(width: 4),
        _NavBtn(
          icon: Icons.chevron_right,
          tooltip: 'Næste uge',
          onTap: () => setOffset(offset + 1),
        ),
      ],
    );
  }
}

class _WeekBadge extends StatelessWidget {
  final String label;
  final bool isCurrent;

  const _WeekBadge({required this.label, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent ? colors.primaryFixed : colors.secondaryFixed,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: isCurrent ? colors.onPrimaryFixedVariant : colors.onSecondaryFixedVariant,
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        minimumSize: const Size(48, 48),
        foregroundColor: context.colors.primary,
        backgroundColor: context.colors.surfaceContainerLowest,
        side: BorderSide(color: context.colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Fælles ramme om de to tips over ugestriben.
class _HintCard extends StatelessWidget {
  final Widget child;
  final String closeTooltip;
  final VoidCallback onClose;

  const _HintCard({super.key, required this.child, required this.closeTooltip, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      decoration: BoxDecoration(
        color: context.colors.primaryFixed.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: child,
            ),
          ),
          IconButton(
            tooltip: closeTooltip,
            onPressed: onClose,
            icon: Icon(Icons.close, size: 20, color: context.colors.primary),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }
}

/// Lørdag og søndag, når man ser denne uge: de fleste planlægger den kommende
/// uge i weekenden og ender ellers med at lægge planen i den forkerte uge.
class _WeekendHint extends ConsumerWidget {
  const _WeekendHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekId = weekIdOf(ref.watch(todayProvider));
    if (ref.watch(weekendHintDismissedProvider) == weekId) return const SizedBox.shrink();

    return _HintCard(
      key: const Key('weekend-hint'),
      closeTooltip: 'Skjul',
      onClose: () => ref.read(weekendHintDismissedProvider.notifier).state = weekId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Planlægger du næste uge?', style: context.text.titleSmall),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => ref.read(weekOffsetProvider.notifier).state = 1,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.primary,
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(48, 48),
            ),
            child: const Text('Gå til næste uge'),
          ),
        ],
      ),
    );
  }
}

/// Står den viste uge tom, mens ugen før har måltider, tilbydes en kopi. Det
/// redder også dem, der allerede har planlagt i den forkerte uge.
class _CopyOffer extends ConsumerStatefulWidget {
  final WeeklyMealPlan plan;
  final DateTime weekStart;
  final int offset;

  /// Planen genindlæses (ugeskift, skift af husstand): så er den viste plan ikke
  /// til at stole på, og tilbuddet skjules.
  final bool loading;

  const _CopyOffer({
    required this.plan,
    required this.weekStart,
    required this.offset,
    required this.loading,
  });

  @override
  ConsumerState<_CopyOffer> createState() => _CopyOfferState();
}

class _CopyOfferState extends ConsumerState<_CopyOffer> {
  /// Kopieringen venter på serveren; et tryk mere i mellemtiden ville se ugen
  /// som fyldt og erstatte "kopieret"-beskeden og dens Fortryd.
  bool _copying = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final weekStart = widget.weekStart;
    final weekId = weekIdOf(weekStart);
    final previousStart = addWeeks(weekStart, -1);
    // Under ugeskift viser både plan og forrige uge kort den forrige visning.
    if (widget.loading || plan.id != weekId) return const SizedBox.shrink();
    if (ref.watch(householdProvider.select((h) => h.householdId)) == null) {
      return const SizedBox.shrink();
    }
    if (ref.watch(copyOfferDismissedProvider).contains(weekId)) return const SizedBox.shrink();
    final previous = ref.watch(previousWeekSlotsProvider).valueOrNull;
    if (previous == null || previous.weekId != weekIdOf(previousStart)) {
      return const SizedBox.shrink();
    }
    if (previous.slots.isEmpty || slotsOfPlan(plan).isNotEmpty) return const SizedBox.shrink();
    final hidden = hiddenCount(previous.slots, ref.watch(householdProvider.select((h) => h.mealTypes)));

    return _HintCard(
      key: const Key('copy-offer'),
      closeTooltip: 'Skjul forslag',
      onClose: () => ref.read(copyOfferDismissedProvider.notifier).update((s) => {...s, weekId}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copyOfferLabel(
              offset: widget.offset,
              fromWeek: isoWeekNumber(previousStart),
              toWeek: isoWeekNumber(weekStart),
              count: previous.slots.length,
              hidden: hidden,
            ),
            style: context.text.titleSmall,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _copying ? null : () => _copy(previous.slots),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Kopiér'),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Future<void> _copy(List<PlannedSlot> previous) async {
    setState(() => _copying = true);
    try {
      await _runCopy(previous);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _runCopy(List<PlannedSlot> previous) async {
    final notifier = ref.read(mealPlanProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = context.colors.error;

    SnackBar errorBar(String text, {SnackBarAction? action}) => SnackBar(
          content: Text(text),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          action: action,
        );

    final visible = ref.read(householdProvider).mealTypes;
    final WeekCopy? result;
    try {
      result = await notifier.copyWeek(from: previous);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(errorBar('Måltiderne kunne ikke kopieres. Prøv igen.'));
      return;
    }
    if (result == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Ugen har allerede måltider – intet blev kopieret.'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    final copy = result;

    // Huskes, så Fortryd ved om serveren har nået at bekræfte kopieringen.
    var confirmed = false;
    copy.write.then<void>((_) {
      confirmed = true;
    }, onError: (Object _) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(errorBar('Måltiderne kunne ikke kopieres. Prøv igen.'));
    });

    Future<void> undo() async {
      try {
        await notifier.undoCopy(copy, ownWritePending: !confirmed);
      } catch (e) {
        final changed = SlotChangedException.matches(e);
        messenger.showSnackBar(errorBar(
          changed
              ? 'Måltiderne er ændret i mellemtiden – kunne ikke fortryde.'
              : 'Kunne ikke fortryde. Prøv igen.',
          action: changed ? null : SnackBarAction(label: 'Prøv igen', onPressed: undo),
        ));
      }
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
            '${mealCountWithHidden(copy.slots.length, hiddenCount(copy.slots, visible))} kopieret'),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Fortryd', onPressed: undo),
      ));
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
              Icon(icon, size: 18, color: context.colors.outline),
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
                  : slot.missingRecipe
                      ? const _MissingRecipeCard()
                      : slot.recipeId != null
                          ? const _PendingRecipeCard()
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
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          // Opskrifter uden billede fik før NetworkImage('') — en fejl hver
          // gang kortet blev tegnet. Nu vises et ikon i stedet.
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              image: (recipe.imageUrl?.isNotEmpty ?? false)
                  ? DecorationImage(
                      image: NetworkImage(recipe.imageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: (recipe.imageUrl?.isNotEmpty ?? false)
                ? null
                : Icon(Icons.restaurant_menu_outlined, color: context.colors.outline),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.title,
                  style: Theme.of(context).textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  '${recipe.calories} kcal • ${recipe.time}',
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: context.colors.outline),
        ],
      ),
    );
  }
}

class _MissingRecipeCard extends StatelessWidget {
  const _MissingRecipeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.link_off, color: context.colors.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Opskriften findes ikke længere',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: context.colors.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opskrift med id, men opskrifterne er ikke indlæst endnu (eller kunne ikke
/// hentes). Viser aldrig "Tilføj …", da pladsen ikke er tom.
class _PendingRecipeCard extends ConsumerWidget {
  const _PendingRecipeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(recipesProvider.select((r) => r.hasError));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.restaurant_menu_outlined, color: context.colors.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              failed ? 'Opskriften kunne ikke hentes' : 'Henter opskrift…',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: context.colors.outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectEntryCard extends ConsumerStatefulWidget {
  final String text;

  const _DirectEntryCard({required this.text});

  @override
  ConsumerState<_DirectEntryCard> createState() => _DirectEntryCardState();
}

class _DirectEntryCardState extends ConsumerState<_DirectEntryCard> {
  bool _isAdded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.text,
              style: Theme.of(context).textTheme.bodyLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _isAdded ? Icons.check : Icons.add_shopping_cart,
              size: 20,
            ),
            color: _isAdded ? context.colors.primary : context.colors.primary,
            tooltip: _isAdded ? 'Allerede tilføjet til indkøbsliste' : 'Tilføj til indkøbsliste',
            style: IconButton.styleFrom(
              backgroundColor: _isAdded
                  ? context.colors.primary.withValues(alpha: 0.15)
                  : context.colors.primaryFixed.withValues(alpha: 0.4),
              padding: const EdgeInsets.all(8),
            ),
            onPressed: _isAdded
                ? null
                : () {
                    setState(() => _isAdded = true);
                    ref.read(groceryListProvider.notifier).addItem(
                          GroceryItem(
                            id: '',
                            name: widget.text,
                            category: 'Måltider',
                            quantity: '1',
                            unit: 'stk',
                            source: 'meal_plan',
                            createdAt: DateTime.now(),
                          ),
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tilføjet "${widget.text}" til indkøbslisten'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: context.colors.outline),
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
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colors.outlineVariant.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.colors.primaryContainer.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_circle_outline, 
              color: context.colors.primary.withValues(alpha: 0.4),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          // Expanded: ved stor tekst brydes linjen i stedet for at løbe ud.
          Expanded(
            child: Text(
              'Tilføj ${title.toLowerCase()}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.outline.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
