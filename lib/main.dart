import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'features/grocery/grocery_screen.dart';
import 'features/grocery/recurring/recurring_auto_adder.dart';
import 'features/grocery/recurring/recurring_items_screen.dart';
import 'features/meal_plan/meal_plan_screen.dart';
import 'features/recipes/recipes_screen.dart';
import 'features/recipes/recipe_detail_screen.dart';
import 'features/recipes/create_recipe_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/household_provider.dart';
import 'features/profile/delete_account_screen.dart';
import 'features/legal/privacy_policy_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/auth_provider.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/home/home_screen.dart';
import 'features/board/board_screen.dart';
import 'shared/widgets/offline_banner.dart';
import 'shared/widgets/app_nav_bar.dart';

import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('da_DK', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

// Bridges Riverpod auth state into a ChangeNotifier so GoRouter can
// re-evaluate its redirect without recreating the router object.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(WidgetRef ref) {
    ref.listenManual<AuthState>(authProvider, (_, __) => notifyListeners());
    ref.listenManual<HouseholdState>(householdProvider, (_, __) => notifyListeners());
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  late final _AuthRouterNotifier _notifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _notifier = _AuthRouterNotifier(ref);
    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: _notifier,
      redirect: _redirect,
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
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
                  routes: [
                    GoRoute(
                      path: 'recurring',
                      builder: (context, state) =>
                          const RecurringItemsScreen(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const HomeScreen(),
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
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/board',
                  builder: (context, state) => const BoardScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
          routes: [
            GoRoute(
              path: 'delete-account',
              builder: (context, state) => const DeleteAccountScreen(),
            ),
          ],
        ),
        // Uden for login-kravet: skal kunne læses, før man opretter en konto.
        GoRoute(
          path: '/privacy',
          builder: (context, state) => const PrivacyPolicyScreen(),
        ),
      ],
    );
  }

  String? _redirect(BuildContext context, GoRouterState state) {
    final authState = ref.read(authProvider);
    final isLoggingIn = state.matchedLocation == '/login';
    final isOnboarding = state.matchedLocation == '/onboarding';
    if (state.matchedLocation == '/privacy') return null;

    if (!authState.isAuthenticated && !isLoggingIn) return '/login';
    if (!authState.isAuthenticated) return null;

    final householdState = ref.read(householdProvider);
    if (isLoggingIn) {
      if (!householdState.hasCompletedOnboarding && !householdState.isLoading) {
        return '/onboarding';
      }
      return '/';
    }
    if (!householdState.hasCompletedOnboarding && !householdState.isLoading && !isOnboarding) {
      return '/onboarding';
    }
    if (householdState.hasCompletedOnboarding && isOnboarding) {
      return '/';
    }
    return null;
  }

  @override
  void dispose() {
    _notifier.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Skafferiet',
      theme: AppTheme.lightTheme,
      routerConfig: _router,
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

  // Indeks svarer til rækkefølgen af grenene i StatefulShellRoute ovenfor.
  static const _mealPlan = AppNavDestination(
    icon: Icons.calendar_today_outlined,
    activeIcon: Icons.calendar_today,
    label: 'Madplan',
    branchIndex: 0,
  );
  static const _grocery = AppNavDestination(
    icon: Icons.shopping_basket_outlined,
    activeIcon: Icons.shopping_basket,
    label: 'Indkøb',
    branchIndex: 1,
  );
  static const _home = AppNavDestination(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Hjem',
    branchIndex: 2,
  );
  static const _recipes = AppNavDestination(
    icon: Icons.restaurant_menu_outlined,
    activeIcon: Icons.restaurant_menu,
    label: 'Opskrifter',
    branchIndex: 3,
  );
  static const _board = AppNavDestination(
    icon: Icons.push_pin_outlined,
    activeIcon: Icons.push_pin,
    label: 'Tavle',
    semanticLabel: 'Opslagstavle',
    branchIndex: 4,
  );

  @override
  Widget build(BuildContext context) {
    // Skallen vises kun for en logget ind bruger, så det er her de faste
    // varer lægges på listen.
    return Scaffold(
      body: RecurringAutoAdder(child: navigationShell),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OfflineBanner(),
          AppNavBar(
            leading: const [_mealPlan, _grocery],
            center: _home,
            trailing: const [_recipes, _board],
            currentIndex: navigationShell.currentIndex,
            onSelect: (index) => navigationShell.goBranch(
              index,
              // Tryk på den aktive fane går tilbage til fanens start.
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ],
      ),
    );
  }
}
