import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_theme.dart';
import 'features/grocery/grocery_screen.dart';
import 'features/meal_plan/meal_plan_screen.dart';
import 'features/recipes/recipes_screen.dart';
import 'features/recipes/recipe_detail_screen.dart';
import 'features/recipes/create_recipe_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/auth_provider.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final router = GoRouter(
      initialLocation: '/meal-plan',
      redirect: (context, state) {
        final isLoggingIn = state.matchedLocation == '/login';
        if (!authState.isAuthenticated && !isLoggingIn) {
          return '/login';
        }
        if (authState.isAuthenticated && isLoggingIn) {
          return '/meal-plan';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return ScaffoldWithNavBar(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/meal-plan',
                  builder: (context, state) => const MealPlanScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/grocery',
                  builder: (context, state) => const GroceryScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/recipes',
                  builder: (context, state) => const RecipesScreen(),
                  routes: [
                    GoRoute(
                      path: 'create',
                      builder: (context, state) => const CreateRecipeScreen(),
                    ),
                    GoRoute(
                      path: ':id',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return RecipeDetailScreen(recipeId: id);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Skafferiet',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    required this.navigationShell,
    Key? key,
  }) : super(key: key ?? const ValueKey<String>('ScaffoldWithNavBar'));

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavBarItem(
                  icon: Icons.calendar_today,
                  label: 'Madplan',
                  isActive: navigationShell.currentIndex == 0,
                  onTap: () => navigationShell.goBranch(0),
                ),
                _NavBarItem(
                  icon: Icons.shopping_basket,
                  label: 'Indkøb',
                  isActive: navigationShell.currentIndex == 1,
                  onTap: () => navigationShell.goBranch(1),
                ),
                _NavBarItem(
                  icon: Icons.restaurant_menu,
                  label: 'Opskrifter',
                  isActive: navigationShell.currentIndex == 2,
                  onTap: () => navigationShell.goBranch(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF0F5238) : Colors.grey[400];
    final bgColor = isActive ? const Color(0xFFE7F3ED) : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
