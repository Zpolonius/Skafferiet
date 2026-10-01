import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/profile/profile_screen.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/meal_plan.dart';

// ── Mock classes ───────────────────────────────────────────────────────────────

class _MockUser extends Mock implements User {}

class _MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _MockAuthNotifier(super.state);
}

class _MockHouseholdNotifier extends StateNotifier<HouseholdState> with Mock implements HouseholdNotifier {
  _MockHouseholdNotifier(super.state);
}

class _EmptyRecipesNotifier extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => const Stream.empty();
}

class _LoadedRecipesNotifier extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(List.generate(
    3,
    (i) => Recipe(
      id: 'r$i',
      title: 'Opskrift $i',
      calories: 400,
      time: '20 min',
      category: RecipeCategory.aftensmad,
      ingredients: [],
      instructions: [],
    ),
  ));
}

class _EmptyGroceryNotifier extends StreamNotifier<List<GroceryItem>> with Mock implements GroceryListNotifier {
  @override
  Stream<List<GroceryItem>> build() => const Stream.empty();
}

class _LoadedGroceryNotifier extends StreamNotifier<List<GroceryItem>> with Mock implements GroceryListNotifier {
  @override
  Stream<List<GroceryItem>> build() => Stream.value(List.generate(
    5,
    (i) => GroceryItem(
      id: 'g$i',
      name: 'Vare $i',
      category: 'Mejeri',
      quantity: '1',
      isChecked: false,
      source: 'manual',
      createdAt: DateTime(2026, 5, 1),
      sortOrder: i,
    ),
  ));
}

class _EmptyMealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async => WeeklyMealPlan(id: 'empty', weekStart: DateTime(2026, 5, 5), days: {});
}

class _LoadedMealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async => WeeklyMealPlan(
    id: 'week1',
    weekStart: DateTime(2026, 5, 5),
    days: {
      'monday': DailyPlan(
        breakfast: MealSlot(),
        lunch: MealSlot(),
        dinner: MealSlot(directEntry: 'Pasta'),
        snack: MealSlot(),
      ),
      'tuesday': DailyPlan(
        breakfast: MealSlot(),
        lunch: MealSlot(directEntry: 'Salat'),
        dinner: MealSlot(),
        snack: MealSlot(),
      ),
      // En dag uden måltider må ikke tælle som planlagt.
      'wednesday': DailyPlan(
        breakfast: MealSlot(),
        lunch: MealSlot(),
        dinner: MealSlot(),
        snack: MealSlot(),
      ),
    },
  );
}

// ── Helper ─────────────────────────────────────────────────────────────────────

Widget _buildProfileScreen({
  required HouseholdState householdState,
  required _MockHouseholdNotifier householdNotifier,
  RecipesNotifier Function()? recipesFactory,
  GroceryListNotifier Function()? groceryFactory,
  MealPlanNotifier Function()? mealPlanFactory,
  AuthState? authState,
  GoRouter? router,
  _MockAuthNotifier Function(User user)? authNotifier,
}) {
  final mockUser = _MockUser();
  when(() => mockUser.displayName).thenReturn('Test Bruger');
  when(() => mockUser.email).thenReturn('test@example.com');
  when(() => mockUser.photoURL).thenReturn(null);
  when(() => mockUser.uid).thenReturn('test-uid');

  return ProviderScope(
    overrides: [
      authProvider.overrideWith(
        (ref) => authNotifier?.call(mockUser) ??
            _MockAuthNotifier(authState ?? AuthState(user: mockUser)),
      ),
      householdProvider.overrideWith((ref) => householdNotifier),
      recipesProvider.overrideWith(recipesFactory ?? () => _EmptyRecipesNotifier()),
      groceryListProvider.overrideWith(groceryFactory ?? () => _EmptyGroceryNotifier()),
      mealPlanProvider.overrideWith(mealPlanFactory ?? () => _EmptyMealPlanNotifier()),
    ],
    child: router != null
        ? MaterialApp.router(routerConfig: router)
        : const MaterialApp(home: ProfileScreen()),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(const AsyncValue<List<Recipe>>.loading());
    registerFallbackValue(const AsyncValue<List<GroceryItem>>.loading());
  });

  group('Stats row', () {
    testWidgets('shows dash when providers are loading', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: HouseholdState(householdId: 'hh-1', isLoading: false),
        householdNotifier: notifier,
        // All providers return Stream.empty() → AsyncLoading → value == null → '–'
      ));
      await tester.pumpAndSettle();

      expect(find.text('–'), findsWidgets);
    });

    testWidgets('shows counts when all providers have data', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: HouseholdState(householdId: 'hh-1', isLoading: false),
        householdNotifier: notifier,
        recipesFactory: () => _LoadedRecipesNotifier(),
        groceryFactory: () => _LoadedGroceryNotifier(),
        mealPlanFactory: () => _LoadedMealPlanNotifier(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget); // 3 recipes
      expect(find.text('5'), findsOneWidget); // 5 grocery items
      expect(find.text('2'), findsOneWidget); // 2 planlagte dage (onsdag er tom)
      expect(find.text('PLANLAGTE DAGE'), findsOneWidget);
    });
  });

  group('Husstandskort', () {
    testWidgets('viser navn, antal medlemmer og om man er ejer', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(
          householdId: 'hh-1',
          householdName: 'Familie Skafferi',
          adminUid: 'test-uid',
          members: ['test-uid', 'member-uid'],
          memberNames: {'test-uid': 'Test Bruger', 'member-uid': 'Alm. Bruger'},
          isLoading: false,
        ),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Familie Skafferi'), findsOneWidget);
      expect(find.text('2 medlemmer · Du er ejer'), findsOneWidget);
      // "Aktiv" var hårdkodet og sagde intet.
      expect(find.text('Aktiv'), findsNothing);
    });

    testWidgets('almindeligt medlem får ikke at vide, at de er ejer', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(
          householdId: 'hh-1',
          householdName: 'Vores Skafferi',
          adminUid: 'admin-uid',
          members: ['admin-uid', 'test-uid', 'c', 'd', 'e'],
          isLoading: false,
        ),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.text('5 medlemmer'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget); // 4 avatarer + "+1"
    });
  });

  group('Modtaget invitation', () {
    HouseholdState withInvite({List<String> members = const ['test-uid', 'partner']}) =>
        HouseholdState(
          householdId: 'hh-1',
          householdName: 'Gammelt Hjem',
          adminUid: 'test-uid',
          members: members,
          isLoading: false,
          invitations: const [
            {'id': 'inv1', 'fromUserName': 'Ole', 'fromHouseholdName': 'Oles Hus'},
          ],
        );

    Future<void> pump(WidgetTester tester, _MockHouseholdNotifier notifier) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('advarer om at den nuværende husstand forlades — fortryd accepterer ikke',
        (tester) async {
      final notifier = _MockHouseholdNotifier(withInvite());
      await pump(tester, notifier);

      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();

      expect(find.text('Deltag i "Oles Hus"?'), findsOneWidget);
      expect(find.textContaining('Du forlader "Gammelt Hjem"'), findsOneWidget);
      expect(find.textContaining('De andre medlemmer beholder'), findsOneWidget);

      await tester.tap(find.text('Annuller'));
      await tester.pumpAndSettle();
      verifyNever(() => notifier.acceptInvitation(any()));
    });

    testWidgets('eneste medlem får at vide, at data ikke kan hentes igen', (tester) async {
      final notifier = _MockHouseholdNotifier(withInvite(members: ['test-uid']));
      when(() => notifier.acceptInvitation(any())).thenAnswer((_) async {});
      await pump(tester, notifier);

      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kan ikke hentes igen'), findsOneWidget);

      await tester.tap(find.text('Deltag'));
      await tester.pumpAndSettle();
      verify(() => notifier.acceptInvitation('inv1')).called(1);
    });
  });

  group('Konto', () {
    GoRouter testRouter() => GoRouter(
          initialLocation: '/profile',
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, __) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'delete-account',
                  builder: (_, __) => const Text('SLET-KONTO-SKÆRM'),
                ),
                GoRoute(path: 'household', builder: (_, __) => const Text('HUSSTAND-SKÆRM')),
                GoRoute(path: 'preferences', builder: (_, __) => const Text('PRÆFERENCE-SKÆRM')),
                GoRoute(path: 'help', builder: (_, __) => const Text('HJÆLP-SKÆRM')),
                GoRoute(
                  path: 'change-password',
                  builder: (_, __) => const Text('ADGANGSKODE-SKÆRM'),
                ),
              ],
            ),
            GoRoute(path: '/privacy', builder: (_, __) => const Text('PRIVATLIV-SKÆRM')),
          ],
        );

    Future<void> pumpWithRouter(WidgetTester tester, {HouseholdState? household}) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = _MockHouseholdNotifier(
        household ?? HouseholdState(householdId: 'hh-1', householdName: 'Hjem', isLoading: false),
      );
      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
        router: testRouter(),
      ));
      await tester.pumpAndSettle();
    }

    for (final (tile, screen) in [
      ('Husstand & deling', 'HUSSTAND-SKÆRM'),
      ('Præferencer & Diæt', 'PRÆFERENCE-SKÆRM'),
      ('Hjælp & Support', 'HJÆLP-SKÆRM'),
      ('Skift adgangskode', 'ADGANGSKODE-SKÆRM'),
    ]) {
      testWidgets('$tile åbner sin side', (tester) async {
        await pumpWithRouter(tester);

        await tester.ensureVisible(find.text(tile));
        await tester.tap(find.text(tile));
        await tester.pumpAndSettle();

        expect(find.text(screen), findsOneWidget);
      });
    }

    testWidgets('husstandskortet åbner Husstand & deling', (tester) async {
      await pumpWithRouter(tester);

      await tester.tap(find.text('Hjem'));
      await tester.pumpAndSettle();

      expect(find.text('HUSSTAND-SKÆRM'), findsOneWidget);
    });

    testWidgets('uden husstand er husstandens menupunkter slået fra', (tester) async {
      await pumpWithRouter(tester, household: HouseholdState(isLoading: false));

      final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text('Præferencer & Diæt'), matching: find.byType(ListTile)));
      expect(tile.enabled, false);
    });

    testWidgets('Slet konto åbner slet-konto-skærmen', (tester) async {
      await pumpWithRouter(tester);

      await tester.ensureVisible(find.text('Slet konto'));
      await tester.tap(find.text('Slet konto'));
      await tester.pumpAndSettle();

      expect(find.text('SLET-KONTO-SKÆRM'), findsOneWidget);
    });

    testWidgets('Privatlivspolitik åbner politikken', (tester) async {
      await pumpWithRouter(tester);

      await tester.ensureVisible(find.text('Privatlivspolitik'));
      await tester.tap(find.text('Privatlivspolitik'));
      await tester.pumpAndSettle();

      expect(find.text('PRIVATLIV-SKÆRM'), findsOneWidget);
    });
  });

  group('Menu', () {
    testWidgets('viser de færdige menupunkter — ingen "kommer snart"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mine opskrifter'), findsOneWidget);
      expect(find.text('Faste varer & indkøbsdag'), findsOneWidget);
      expect(find.text('Husstand & deling'), findsOneWidget);
      expect(find.text('Præferencer & Diæt'), findsOneWidget);
      expect(find.text('Hjælp & Support'), findsOneWidget);
      expect(find.text('Skift navn'), findsOneWidget);
      expect(find.text('Skift adgangskode'), findsOneWidget);
      // Apple afviser apps med pladsholdere.
      expect(find.text('Notifikationer'), findsNothing);
      expect(find.text('Delte lister'), findsNothing);
    });
  });

  group('Skift navn og log ud', () {
    late _MockAuthNotifier auth;

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );
      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
        authNotifier: (user) => auth = _MockAuthNotifier(AuthState(user: user)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('Skift navn gemmer det nye navn', (tester) async {
      await pump(tester);
      when(() => auth.updateDisplayName(any())).thenAnswer((_) async => null);

      await tester.tap(find.text('Skift navn'));
      await tester.pumpAndSettle();
      final field = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
      expect(tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
          .controller.text, 'Test Bruger');

      await tester.enterText(field, 'Nyt Navn');
      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      verify(() => auth.updateDisplayName('Nyt Navn')).called(1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Dit navn er opdateret.'), findsOneWidget);
    });

    testWidgets('Skift navn: tomt navn afvises, og fejl vises i dialogen', (tester) async {
      await pump(tester);
      when(() => auth.updateDisplayName(any()))
          .thenAnswer((_) async => 'Navnet kunne ikke gemmes.');

      await tester.tap(find.text('Skift navn'));
      await tester.pumpAndSettle();
      final field = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));

      await tester.enterText(field, '   ');
      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();
      expect(find.text('Indtast dit navn'), findsOneWidget);
      verifyNever(() => auth.updateDisplayName(any()));

      await tester.enterText(field, 'Nyt Navn');
      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();
      expect(find.text('Navnet kunne ikke gemmes.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Log ud spørger først — fortryd logger ikke ud', (tester) async {
      await pump(tester);
      when(() => auth.logout()).thenAnswer((_) async {});

      // OutlinedButton.icon er en underklasse, så vi finder knappen på teksten.
      await tester.ensureVisible(find.text('Log ud'));
      await tester.tap(find.text('Log ud'));
      await tester.pumpAndSettle();
      expect(find.text('Log ud?'), findsOneWidget);

      await tester.tap(find.text('Annuller'));
      await tester.pumpAndSettle();
      verifyNever(() => auth.logout());

      await tester.tap(find.text('Log ud'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log ud'));
      await tester.pumpAndSettle();
      verify(() => auth.logout()).called(1);
    });
  });

  group('Profile Avatar', () {
    testWidgets('shows camera badge and user initial', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.text('T'), findsOneWidget); // Test Bruger -> 'T'
    });

    testWidgets('renders CachedNetworkImage when user has photoURL', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockUser = _MockUser();
      when(() => mockUser.displayName).thenReturn('Anna');
      when(() => mockUser.email).thenReturn('anna@example.com');
      when(() => mockUser.photoURL).thenReturn('https://example.com/anna.jpg');
      when(() => mockUser.uid).thenReturn('anna-uid');

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
        authState: AuthState(user: mockUser),
      ));

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });
}
