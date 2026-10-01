import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../auth/auth_provider.dart';
import '../meal_plan/meal_plan_provider.dart';
import '../grocery/grocery_provider.dart';
import '../../core/models/meal_plan.dart';
import '../../shared/widgets/profile_avatar.dart';
import 'package:gap/gap.dart';
import '../../core/theme/theme_context.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final mealPlan = ref.watch(mealPlanProvider);
    final groceryList = ref.watch(groceryListProvider);
    
    final userName = authState.user?.displayName?.split(' ').first ?? 'Bruger';
    final today = DateFormat('EEEE, d. MMMM', 'da_DK').format(DateTime.now()).toUpperCase();
    final greeting = _getGreeting();

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
          _buildAppBar(context, authState),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, today, userName, greeting),
                  const Gap(24),
                  _buildQuickActions(context),
                  const Gap(32),
                  _buildSectionHeader(context, 'Dagens Plan', 'Se hele ugen', () => context.go('/meal-plan')),
                  const Gap(16),
                  _buildDailyPlan(mealPlan),
                  const Gap(32),
                  _buildShoppingPreview(context, groceryList),
                  const Gap(40),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 10) return 'Godmorgen';
    if (hour >= 10 && hour < 12) return 'Godformiddag';
    if (hour >= 12 && hour < 17) return 'Godeftermiddag';
    if (hour >= 17 && hour < 22) return 'Godaften';
    return 'Godnat';
  }

  Widget _buildAppBar(BuildContext context, AuthState auth) {
    return SliverAppBar(
      floating: true,
      backgroundColor: context.colors.surfaceContainerLowest,
      elevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          Image.asset('assets/images/logo.png', height: 32),
          const Gap(12),
          Text(
            'Skafferiet',
            style: context.text.headlineLarge?.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ],
      ),
      actions: const [
        ProfileAvatar(),
        Gap(8),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, String date, String name, String greeting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.wb_sunny_outlined, color: context.colors.secondaryContainer, size: 20),
            const Gap(8),
            Text(
              date,
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const Gap(8),
        Text(
          '$greeting, $name!',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: context.colors.onSurface,
            height: 1.2,
          ),
        ),
        const Gap(4),
        Text(
          'Her er dit overblik for i dag.',
          style: TextStyle(
            fontSize: 18,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            label: 'Tilføj måltid',
            icon: Icons.restaurant_menu,
            color: context.colors.primary,
            onTap: () => context.go('/meal-plan'),
          ),
        ),
        const Gap(16),
        Expanded(
          child: _QuickActionButton(
            label: 'Tilføj vare',
            icon: Icons.shopping_basket_outlined,
            color: context.colors.primaryFixed,
            textColor: context.colors.primary,
            onTap: () => context.go('/grocery'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, String action, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: context.colors.onSurface),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyPlan(AsyncValue<WeeklyMealPlan> planAsync) {
    return planAsync.when(
      data: (plan) {
        final rawDayName = DateFormat('EEEE', 'da_DK').format(DateTime.now());
        final dayName = rawDayName.isNotEmpty
            ? '${rawDayName[0].toUpperCase()}${rawDayName.substring(1)}'
            : rawDayName;
        final day = plan.days[dayName];
        
        return Column(
          children: [
            _MealCard(type: 'MORGENMAD', slot: day?.breakfast ?? MealSlot()),
            const Gap(12),
            _MealCard(type: 'FROKOST', slot: day?.lunch ?? MealSlot()),
            const Gap(12),
            _MealCard(type: 'AFTENSMAD', slot: day?.dinner ?? MealSlot()),
            const Gap(12),
            _MealCard(type: 'SNACK', slot: day?.snack ?? MealSlot()),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => const Text('Kunne ikke hente madplan'),
    );
  }

  Widget _buildShoppingPreview(BuildContext context, AsyncValue<List<dynamic>> listAsync) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '3 vigtige ting at huske',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Icon(Icons.shopping_cart_outlined, color: context.colors.onSurfaceVariant),
            ],
          ),
          const Gap(16),
          listAsync.when(
            data: (items) {
              final topItems = items.where((i) => !i.isChecked).take(3).toList();
              if (topItems.isEmpty) {
                return Column(
                  children: [
                    const Gap(8),
                    Text(
                      'Din indkøbsliste er tom. Mangler du mælk, æg eller måske noget lækkert til aftensmaden?',
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const Gap(16),
                    FilledButton.icon(
                      onPressed: () => context.go('/grocery'),
                      icon: const Icon(Icons.add),
                      label: const Text('Tilføj vare'),
                    ),
                  ],
                );
              }
              return Column(
                children: topItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border.all(color: context.colors.outlineVariant, width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const Gap(12),
                      Text(
                        item.name,
                        style: TextStyle(fontSize: 16, color: context.colors.onSurface),
                      ),
                    ],
                  ),
                )).toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Kunne ikke hente liste'),
          ),
          const Gap(8),
          Center(
            child: TextButton(
              onPressed: () => context.go('/grocery'),
              child: Text(
                'Åbn fuld indkøbsliste',
                style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color? textColor;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor ?? context.colors.onPrimary, size: 32),
            const Gap(12),
            Text(
              label,
              style: TextStyle(
                color: textColor ?? context.colors.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final String type;
  final MealSlot slot;

  const _MealCard({required this.type, required this.slot});

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = slot.recipe == null && slot.directEntry == null;
    
    return GestureDetector(
      onTap: () => context.go('/meal-plan'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.surfaceContainer),
          boxShadow: isEmpty ? null : [
            BoxShadow(
              color: context.colors.shadow.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isEmpty 
                ? Container(
                    width: 64,
                    height: 64,
                    color: context.colors.surfaceContainerLow,
                    child: Icon(Icons.add_circle_outline, color: context.colors.primary),
                  )
                : CachedNetworkImage(
                    imageUrl: slot.recipe?.imageUrl ?? 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=200',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 64,
                      height: 64,
                      color: context.colors.surfaceContainerLow,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 64,
                      height: 64,
                      color: context.colors.surfaceContainerLow,
                      child: Icon(Icons.error_outline, color: context.colors.error),
                    ),
                  ),
            ),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: TextStyle(
                      color: context.colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    isEmpty ? 'Tilføj til madplan' : (slot.recipe?.title ?? slot.directEntry!),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isEmpty ? context.colors.outline : context.colors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (!isEmpty && slot.recipe != null) ...[
                    const Gap(4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: context.colors.onSurfaceVariant),
                        const Gap(4),
                        Text(slot.recipe!.time, style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                        const Gap(12),
                        Icon(Icons.local_fire_department_outlined, size: 14, color: context.colors.onSurfaceVariant),
                        const Gap(4),
                        Text('${slot.recipe!.calories} kcal', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
