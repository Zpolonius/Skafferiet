import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_provider.dart';
import '../meal_plan/meal_plan_provider.dart';
import '../grocery/grocery_provider.dart';
import '../../core/models/meal_plan.dart';
import 'package:gap/gap.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final mealPlan = ref.watch(mealPlanProvider);
    final groceryList = ref.watch(groceryListProvider);
    
    final userName = authState.user?.displayName?.split(' ').first ?? 'Mette';
    final today = DateFormat('EEEE, d. MMMM', 'da_DK').format(DateTime.now()).toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, authState),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(today, userName),
                  const Gap(24),
                  _buildQuickActions(context),
                  const Gap(32),
                  _buildSectionHeader('Dagens Plan', 'Se hele ugen', () => context.go('/meal-plan')),
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
    );
  }

  Widget _buildAppBar(BuildContext context, AuthState auth) {
    return SliverAppBar(
      floating: true,
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryContainer,
            backgroundImage: auth.user?.photoURL != null ? NetworkImage(auth.user!.photoURL!) : null,
            child: auth.user?.photoURL == null ? const Icon(Icons.person, size: 20, color: Colors.white) : null,
          ),
          const Gap(12),
          Text(
            'Kitchen Harmony',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF0F5238),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Color(0xFF0F5238)),
          onPressed: () {},
        ),
        const Gap(8),
      ],
    );
  }

  Widget _buildHeader(String date, String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.wb_sunny_outlined, color: Colors.orange, size: 20),
            const Gap(8),
            Text(
              date,
              style: const TextStyle(
                color: Color(0xFF404943),
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const Gap(8),
        Text(
          'Godmorgen, $name!',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF191C1D),
            height: 1.2,
          ),
        ),
        const Gap(4),
        const Text(
          'Her er dit overblik for i dag.',
          style: TextStyle(
            fontSize: 18,
            color: Color(0xFF404943),
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
            color: const Color(0xFF0F5238),
            onTap: () => context.go('/meal-plan'),
          ),
        ),
        const Gap(16),
        Expanded(
          child: _QuickActionButton(
            label: 'Tilføj vare',
            icon: Icons.shopping_basket_outlined,
            color: const Color(0xFFB1F0CE),
            textColor: const Color(0xFF0F5238),
            onTap: () => context.go('/grocery'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String action, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF191C1D)),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: const TextStyle(color: Color(0xFF0F5238), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyPlan(AsyncValue<WeeklyMealPlan> planAsync) {
    return planAsync.when(
      data: (plan) {
        final dayName = DateFormat('EEEE', 'da_DK').format(DateTime.now());
        // Map dansk dag til engelsk nøgle hvis nødvendigt, eller brug dansk hvis modellen bruger det
        final day = plan.days[dayName] ?? plan.days['Mandag'] ?? DailyPlan.empty();
        
        return Column(
          children: [
            _MealCard(type: 'MORGENMAD', slot: day.breakfast),
            const Gap(12),
            _MealCard(type: 'FROKOST', slot: day.lunch),
            const Gap(12),
            _MealCard(type: 'AFTENSMAD', slot: day.dinner),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              const Icon(Icons.shopping_cart_outlined, color: Color(0xFF404943)),
            ],
          ),
          const Gap(16),
          listAsync.when(
            data: (items) {
              final topItems = items.where((i) => !i.isChecked).take(3).toList();
              if (topItems.isEmpty) {
                return const Text('Alt er købt ind! 🎉');
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
                          border: Border.all(color: const Color(0xFFBFC9C1), width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const Gap(12),
                      Text(
                        item.name,
                        style: const TextStyle(fontSize: 16, color: Color(0xFF191C1D)),
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
              child: const Text(
                'Åbn fuld indkøbsliste',
                style: TextStyle(color: Color(0xFF0F5238), fontWeight: FontWeight.bold),
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
            Icon(icon, color: textColor ?? Colors.white, size: 32),
            const Gap(12),
            Text(
              label,
              style: TextStyle(
                color: textColor ?? Colors.white,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEEEF)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              slot.recipe?.imageUrl ?? 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=200',
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: const TextStyle(
                    color: Color(0xFF0F5238),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  slot.recipe?.title ?? slot.directEntry ?? 'Ingen planlagt',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF191C1D),
                  ),
                ),
                if (slot.recipe != null) ...[
                  const Gap(4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Color(0xFF404943)),
                      const Gap(4),
                      Text(slot.recipe!.time, style: const TextStyle(fontSize: 12, color: Color(0xFF404943))),
                      const Gap(12),
                      const Icon(Icons.local_fire_department_outlined, size: 14, color: Color(0xFF404943)),
                      const Gap(4),
                      Text('${slot.recipe!.calories} kcal', style: const TextStyle(fontSize: 12, color: Color(0xFF404943))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
