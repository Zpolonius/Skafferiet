// #51: deling af opskrifter i appen - delings-valget, filteret Vores /
// Fællesskab (søgning, "Vis flere"), kort og detaljer samt "Gem i vores
// opskrifter" og "Til madplan" fra en andens opskrift.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/community_recipes_provider.dart';
import 'package:skafferiet/features/recipes/create_recipe_screen.dart';
import 'package:skafferiet/features/recipes/edit_recipe_screen.dart';
import 'package:skafferiet/features/recipes/recipe_detail_screen.dart';
import 'package:skafferiet/features/recipes/recipe_mapping.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipes_screen.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'HH'));
}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _CapturingRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  final List<Recipe> recipes;
  Recipe? added;
  Recipe? updated;
  _CapturingRecipes([this.recipes = const []]);

  @override
  Stream<List<Recipe>> build() => Stream.value(recipes);

  @override
  Future<void> addRecipe(Recipe recipe) async => added = recipe;

  @override
  Future<void> updateRecipe(Recipe updatedRecipe) async =>
      updated = updatedRecipe;
}

class _MealPlan extends MealPlanNotifier {
  _MealPlan() : super(firestore: _MockFirestore());
  Recipe? capturedRecipe;

  @override
  Stream<WeeklyMealPlan> build() => Stream.value(
      WeeklyMealPlan(id: 't', weekStart: DateTime.now(), days: {}));

  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry}) async {
    capturedRecipe = recipe;
  }
}

class _Grocery extends StreamNotifier<List<GroceryItem>>
    with Mock
    implements GroceryListNotifier {
  final added = <GroceryItem>[];
  @override
  Stream<List<GroceryItem>> build() => Stream.value(const []);
  @override
  Future<void> addItem(GroceryItem item) async => added.add(item);
}

/// En Firestore der aldrig svarer, til fejltilstanden.
class _FailingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
}

Map<String, dynamic> _doc(
  String title, {
  String household = 'OTHER',
  String createdBy = 'eva',
  bool public = true,
  String? author = 'Eva',
  int day = 1,
  List<String> ingredients = const ['Pasta'],
}) =>
    {
      ...recipeToFields(Recipe(
        id: '',
        title: title,
        imageUrl: null,
        calories: 400,
        time: '30 min',
        category: RecipeCategory.aftensmad,
        ingredients: [
          for (final i in ingredients)
            Ingredient(name: i, quantity: 2, unit: 'stk', category: 'Andet'),
        ],
        instructions: const ['Lav maden'],
        visibility:
            public ? RecipeVisibility.public : RecipeVisibility.household,
        authorName: public ? author : null,
      )),
      'householdId': household,
      'createdBy': createdBy,
      'createdAt':
          Timestamp.fromDate(DateTime(2026, 1, 1).add(Duration(days: day))),
    };

void main() {
  void phone(WidgetTester tester, {double w = 360, double h = 800}) {
    tester.view.physicalSize = Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // Detaljesiden har en uendelig spinner som pladsholder for billedet (kun
  // uden netværk), så pumpAndSettle kan ikke bruges her.
  Future<void> pumpFrames(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> tapD(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await pumpFrames(tester);
    await tester.tap(finder);
    await pumpFrames(tester);
  }

  group('Delings-valget', () {
    testWidgets(
        'Opret: slået fra som standard, med forklaring; gemmer som husstand',
        (tester) async {
      phone(tester);
      final notifier = _CapturingRecipes();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          recipesProvider.overrideWith(() => notifier),
          currentUserIdProvider.overrideWithValue('me'),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const CreateRecipeScreen()),
      ));

      await tester.scrollUntilVisible(find.text('Del med alle brugere'), 200,
          scrollable: find.byType(Scrollable).first);
      final sw =
          tester.widget<Switch>(find.byKey(const Key('share-recipe-switch')));
      expect(sw.value, isFalse);
      expect(find.textContaining('kun din husstand kan se opskriften'),
          findsOneWidget);

      await tapVisible(tester, find.text('Opret opskrift'));
      expect(notifier.added!.visibility, RecipeVisibility.household);
    });

    testWidgets(
        'Opret: slået til gemmer som delt, og forklaringen nævner det vigtige',
        (tester) async {
      phone(tester);
      final notifier = _CapturingRecipes();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          recipesProvider.overrideWith(() => notifier),
          currentUserIdProvider.overrideWithValue('me'),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const CreateRecipeScreen()),
      ));

      await tapVisible(tester, find.byKey(const Key('share-recipe-switch')));
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((t) => t.contains('Alle brugere af appen kan se'));
      for (final word in [
        'titel',
        'billede',
        'ingredienser',
        'fremgangsmåde',
        'næring',
        'fornavn',
        'slå deling fra igen',
        'billedlink',
      ]) {
        expect(text, contains(word), reason: 'forklaringen skal nævne "$word"');
      }

      await tapVisible(tester, find.text('Opret opskrift'));
      expect(notifier.added!.visibility, RecipeVisibility.public);
    });

    testWidgets('Rediger: viser den gemte værdi, og kan slås fra igen',
        (tester) async {
      phone(tester);
      final notifier = _CapturingRecipes();
      final recipe = Recipe(
        id: 'r1',
        title: 'Gryde',
        calories: 300,
        time: '',
        category: RecipeCategory.aftensmad,
        householdId: 'HH',
        createdBy: 'me',
        visibility: RecipeVisibility.public,
        authorName: 'Mette',
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          recipesProvider.overrideWith(() => notifier),
          currentUserIdProvider.overrideWithValue('me'),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: EditRecipeScreen(recipe: recipe)),
      ));

      await tester.scrollUntilVisible(
          find.byKey(const Key('share-recipe-switch')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester
              .widget<Switch>(find.byKey(const Key('share-recipe-switch')))
              .value,
          isTrue);

      await tapVisible(tester, find.byKey(const Key('share-recipe-switch')));
      await tapVisible(tester, find.text('Gem ændringer'));
      expect(notifier.updated!.visibility, RecipeVisibility.household);
    });

    testWidgets(
        'Rediger en privat opskrift: slået fra, og bevares hvis man ikke rører den',
        (tester) async {
      phone(tester);
      final notifier = _CapturingRecipes();
      final recipe = Recipe(
        id: 'r1',
        title: 'Gryde',
        calories: 300,
        time: '',
        category: RecipeCategory.aftensmad,
        householdId: 'HH',
        createdBy: 'me',
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          recipesProvider.overrideWith(() => notifier),
          currentUserIdProvider.overrideWithValue('me'),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: EditRecipeScreen(recipe: recipe)),
      ));
      await tester.scrollUntilVisible(
          find.byKey(const Key('share-recipe-switch')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester
              .widget<Switch>(find.byKey(const Key('share-recipe-switch')))
              .value,
          isFalse);
      await tapVisible(tester, find.text('Gem ændringer'));
      expect(notifier.updated!.visibility, RecipeVisibility.household);
    });
  });

  group('Kun skaberen kan dele', () {
    Future<void> pumpEdit(
        WidgetTester tester, Recipe recipe, _CapturingRecipes n) async {
      phone(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('partner'),
          recipesProvider.overrideWith(() => n),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: EditRecipeScreen(recipe: recipe)),
      ));
      await tester.scrollUntilVisible(
          find.byKey(const Key('share-recipe-switch')), 200,
          scrollable: find.byType(Scrollable).first);
    }

    Recipe made(RecipeVisibility v) => Recipe(
          id: 'r1',
          title: 'Gryde',
          calories: 300,
          time: '',
          category: RecipeCategory.aftensmad,
          householdId: 'HH',
          createdBy: 'me',
          visibility: v,
          authorName: v == RecipeVisibility.public ? 'Mette' : null,
        );

    testWidgets('et andet medlem kan ikke dele en andens private opskrift',
        (tester) async {
      await pumpEdit(
          tester, made(RecipeVisibility.household), _CapturingRecipes());
      final sw =
          tester.widget<Switch>(find.byKey(const Key('share-recipe-switch')));
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNull, reason: 'slået fra og låst');
      expect(
          find.text('Kun den, der har lavet opskriften, kan dele den med alle'),
          findsOneWidget);
    });

    testWidgets(
        'et andet medlem kan slå deling fra på en delt opskrift (og beholder navnet intakt)',
        (tester) async {
      final n = _CapturingRecipes();
      await pumpEdit(tester, made(RecipeVisibility.public), n);
      final sw =
          tester.widget<Switch>(find.byKey(const Key('share-recipe-switch')));
      expect(sw.value, isTrue);
      expect(sw.onChanged, isNotNull);
      await tapVisible(tester, find.byKey(const Key('share-recipe-switch')));
      // Nu slået fra: kan ikke slås til igen af ikke-skaberen.
      expect(
          tester
              .widget<Switch>(find.byKey(const Key('share-recipe-switch')))
              .onChanged,
          isNull);
      await tapVisible(tester, find.text('Gem ændringer'));
      expect(n.updated!.visibility, RecipeVisibility.household);
    });

    testWidgets('skaberen kan dele', (tester) async {
      phone(tester);
      final n = _CapturingRecipes();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          recipesProvider.overrideWith(() => n),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: EditRecipeScreen(recipe: made(RecipeVisibility.household))),
      ));
      await tester.scrollUntilVisible(
          find.byKey(const Key('share-recipe-switch')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester
              .widget<Switch>(find.byKey(const Key('share-recipe-switch')))
              .onChanged,
          isNotNull);
    });
  });

  group('Opskrifter-fanen: Vores / Fællesskab', () {
    late FakeFirebaseFirestore db;

    setUp(() => db = FakeFirebaseFirestore());

    Future<void> pumpTab(WidgetTester tester,
        {List<Recipe> own = const [], FirebaseFirestore? community}) async {
      phone(tester, h: 900);
      final user = _User();
      when(() => user.displayName).thenReturn('Mette');
      when(() => user.photoURL).thenReturn(null);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const RecipesScreen()),
        GoRoute(
            path: '/recipes/:id',
            builder: (_, s) =>
                Scaffold(body: Text('detalje ${s.pathParameters['id']}'))),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
          householdProvider.overrideWith((ref) => _Household()),
          recipesProvider.overrideWith(() => _CapturingRecipes(own)),
          communityRecipesProvider.overrideWith(
              () => CommunityRecipesNotifier(firestore: community ?? db)),
        ],
        child: MaterialApp.router(
            theme: AppTheme.lightTheme, routerConfig: router),
      ));
      await settle(tester);
    }

    Future<void> openCommunity(WidgetTester tester) async {
      await tester.tap(find.text('Fællesskab'));
      await settle(tester);
    }

    final ownShared = Recipe(
      id: 'o1',
      title: 'Vores delte',
      calories: 1,
      time: '',
      category: RecipeCategory.aftensmad,
      householdId: 'HH',
      createdBy: 'me',
      visibility: RecipeVisibility.public,
      authorName: 'Mette',
    );
    final ownPrivate = Recipe(
      id: 'o2',
      title: 'Vores private',
      calories: 1,
      time: '',
      category: RecipeCategory.aftensmad,
      householdId: 'HH',
      createdBy: 'me',
    );

    testWidgets(
        'Vores er standard og viser "Delt"-mærke kun på egne delte opskrifter',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await db.collection('recipes').doc('x').set(_doc('Evas lasagne'));
      await pumpTab(tester, own: [ownShared, ownPrivate]);

      expect(find.text('Vores delte'), findsOneWidget);
      expect(find.text('Vores private'), findsOneWidget);
      expect(find.text('Evas lasagne'), findsNothing);
      expect(find.text('Delt'), findsOneWidget,
          reason: 'kun den delte har mærket');
      expect(find.bySemanticsLabel(RegExp('Delt med alle brugere')),
          findsOneWidget);
      expect(find.text('Opret opskrift'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
        'Fællesskab viser andre husstandes delte opskrifter med forfatter',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await db
          .collection('recipes')
          .doc('a')
          .set(_doc('Evas lasagne', author: 'Eva'));
      await db
          .collection('recipes')
          .doc('b')
          .set(_doc('Pers suppe', author: 'Per', day: 2));
      await db.collection('recipes').doc('mine').set(_doc('Vores delte',
          household: 'HH', createdBy: 'me', author: 'Mette', day: 3));
      await db
          .collection('recipes')
          .doc('priv')
          .set(_doc('Evas hemmelige', public: false, day: 4));
      await pumpTab(tester, own: [ownShared]);
      await openCommunity(tester);

      expect(find.text('Evas lasagne'), findsOneWidget);
      expect(find.text('af Eva'), findsOneWidget);
      expect(find.text('Pers suppe'), findsOneWidget);
      expect(find.text('af Per'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Delt af Eva')), findsOneWidget);
      expect(find.text('Vores delte'), findsNothing,
          reason: 'egen husstand vises under Vores');
      expect(find.text('Evas hemmelige'), findsNothing);
      expect(find.text('Delt'), findsNothing);

      await tester.tap(find.text('Vores'));
      await settle(tester);
      expect(find.text('Vores delte'), findsOneWidget);
      expect(find.text('Evas lasagne'), findsNothing);
      semantics.dispose();
    });

    testWidgets('nyeste først, og kort uden forfatter viser "af Ukendt"',
        (tester) async {
      await db.collection('recipes').doc('a').set(_doc('Ældst', day: 1));
      await db
          .collection('recipes')
          .doc('b')
          .set(_doc('Nyest', day: 9, author: null));
      await pumpTab(tester);
      await openCommunity(tester);

      final titles = ['Nyest', 'Ældst'];
      final dy = titles.map((t) => tester.getTopLeft(find.text(t)).dy).toList();
      expect(dy[0] <= dy[1], isTrue);
      expect(find.text('af Ukendt'), findsOneWidget);
    });

    testWidgets('tom Fællesskab viser "Ingen delte opskrifter endnu"',
        (tester) async {
      await pumpTab(tester, own: [ownShared]);
      await openCommunity(tester);
      expect(find.text('Ingen delte opskrifter endnu'), findsOneWidget);
    });

    testWidgets('fejl viser en dansk besked og "Prøv igen" henter igen',
        (tester) async {
      await pumpTab(tester, community: _FailingFirestore());
      await openCommunity(tester);
      expect(find.text('Kunne ikke hente delte opskrifter'), findsOneWidget);
      expect(find.text('Prøv igen'), findsOneWidget);
    });

    testWidgets('indlæsning vises, mens første side hentes', (tester) async {
      await db.collection('recipes').doc('a').set(_doc('Evas lasagne'));
      await pumpTab(tester);
      await tester.tap(find.text('Fællesskab'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await settle(tester);
      expect(find.text('Evas lasagne'), findsOneWidget);
    });

    testWidgets('henter 20 ad gangen og "Vis flere" henter resten',
        (tester) async {
      for (var i = 1; i <= 25; i++) {
        await db.collection('recipes').doc('r$i').set(_doc('Ret $i', day: i));
      }
      await pumpTab(tester);
      await openCommunity(tester);

      Finder card(int i) => find.text('Ret $i');
      // Den nyeste (25) er først. Lazy grid: scroll for at tælle.
      expect(card(25), findsOneWidget);
      expect(card(5), findsNothing, reason: 'side 2 er ikke hentet endnu');
      final snapshotBefore = (await db.collection('recipes').get()).docs.length;
      expect(snapshotBefore, 25);

      await tester.dragUntilVisible(
          find.byKey(const Key('community-load-more')),
          find.byType(CustomScrollView),
          const Offset(0, -300));
      await tester.tap(find.byKey(const Key('community-load-more')));
      await settle(tester);

      expect(find.byKey(const Key('community-load-more')), findsNothing,
          reason: 'alle er hentet');
      for (var i = 0; i < 20 && card(1).evaluate().isEmpty; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pump();
      }
      expect(card(1), findsOneWidget);
    });

    testWidgets(
        'søgning i Fællesskab: titel-præfiks fra serveren + ingrediens i hentede',
        (tester) async {
      await db.collection('recipes').doc('a').set(_doc('Lasagne', day: 1));
      await db
          .collection('recipes')
          .doc('b')
          .set(_doc('Tomatsuppe', day: 2, ingredients: ['Tomat']));
      await db
          .collection('recipes')
          .doc('c')
          .set(_doc('Pizza', day: 3, ingredients: ['Tomat', 'Ost']));
      await pumpTab(tester);
      await openCommunity(tester);
      expect(find.text('Lasagne'), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'las');
      await settle(tester);
      expect(find.text('Lasagne'), findsOneWidget);
      expect(find.text('Tomatsuppe'), findsNothing);
      expect(find.text('Pizza'), findsNothing);

      // Ingrediens-søgning (#35) virker på de hentede opskrifter.
      await tester.enterText(find.byType(TextField), 'tomat');
      await settle(tester);
      expect(find.text('Tomatsuppe'), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);
      expect(find.text('Lasagne'), findsNothing);

      await tester.enterText(find.byType(TextField), 'findes ikke');
      await settle(tester);
      expect(find.text('Ingen opskrifter fundet'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await settle(tester);
      expect(find.text('Lasagne'), findsOneWidget);
    });

    testWidgets('et søgetræf hvis titel ikke passer til søgenøglen vises ikke',
        (tester) async {
      await db.collection('recipes').doc('a').set(_doc('Lasagne', day: 1));
      await db.collection('recipes').doc('spam').set({
        ..._doc('Køb billige piller', day: 2, author: 'Eve'),
        'titleLower': 'lasagne spam',
      });
      await pumpTab(tester);
      await openCommunity(tester);
      await tester.enterText(find.byType(TextField), 'lasagne');
      await settle(tester);
      expect(find.text('Lasagne'), findsOneWidget);
      expect(find.text('Køb billige piller'), findsNothing);
    });

    testWidgets('søgningen følger med, når man skifter til Fællesskab',
        (tester) async {
      await db.collection('recipes').doc('a').set(_doc('Lasagne', day: 1));
      await db.collection('recipes').doc('b').set(_doc('Tomatsuppe', day: 2));
      await pumpTab(tester);
      await tester.enterText(find.byType(TextField), 'tomat');
      await settle(tester);
      await openCommunity(tester);
      expect(find.text('Tomatsuppe'), findsOneWidget);
      expect(find.text('Lasagne'), findsNothing);
    });

    testWidgets('kort i Fællesskab åbner opskriften', (tester) async {
      await db.collection('recipes').doc('a').set(_doc('Lasagne'));
      await pumpTab(tester);
      await openCommunity(tester);
      await tester.tap(find.text('Lasagne'));
      await settle(tester);
      expect(find.text('detalje a'), findsOneWidget);
    });

    testWidgets(
        '360 dp: filter, søg og kort uden overflow, og knapper er mindst 48 dp høje',
        (tester) async {
      await db.collection('recipes').doc('a').set(_doc(
          'En ret med et meget langt navn der fylder',
          author: 'Anne-Marie'));
      await pumpTab(tester, own: [ownShared]);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('recipe-scope'))).height,
          greaterThanOrEqualTo(48));
      await openCommunity(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('af Anne-Marie'), findsOneWidget);
    });
  });

  group('Detaljer for en delt opskrift', () {
    late FakeFirebaseFirestore db;
    late _MealPlan mealPlan;
    late _Grocery grocery;

    setUp(() async {
      db = FakeFirebaseFirestore();
      mealPlan = _MealPlan();
      grocery = _Grocery();
      await db
          .collection('recipes')
          .doc('orig')
          .set(_doc('Evas lasagne', ingredients: ['Pasta', 'Ost']));
    });

    Future<void> pumpDetail(WidgetTester tester, String id) async {
      phone(tester, h: 900);
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser:
            MockUser(uid: 'me', email: 'me@example.com', displayName: 'Mette'),
      );
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
              path: '/start',
              builder: (_, __) => const Scaffold(body: Text('start'))),
          GoRoute(
              path: '/recipes/:id',
              builder: (_, s) =>
                  RecipeDetailScreen(recipeId: s.pathParameters['id']!)),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          householdProvider.overrideWith((ref) => _Household()),
          recipesProvider
              .overrideWith(() => RecipesNotifier(firestore: db, auth: auth)),
          currentUserIdProvider.overrideWithValue('me'),
          recipeByIdProvider.overrideWith((ref, id) async {
            final d = await db.collection('recipes').doc(id).get();
            return d.exists ? recipeFromMap(d.id, d.data()!) : null;
          }),
          mealPlanProvider.overrideWith(() => mealPlan),
          groceryListProvider.overrideWith(() => grocery),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      router.push('/recipes/$id');
      await pumpFrames(tester);
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> copies() async =>
        (await db
                .collection('recipes')
                .where('copiedFrom', isEqualTo: 'orig')
                .get())
            .docs;

    testWidgets(
        'en andens opskrift: forfatter, ingen redigér-knap, "Gem i vores opskrifter"',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDetail(tester, 'orig');

      expect(find.text('Evas lasagne'), findsOneWidget);
      expect(find.text('af Eva'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Delt af Eva')), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byTooltip('Rediger opskrift'), findsNothing);
      expect(find.text('Gem i vores opskrifter'), findsOneWidget);
      expect(find.text('Tilføj til indkøb'), findsOneWidget);
      expect(find.text('Til madplan'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('save-shared-recipe'))).height,
          greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('"Gem i vores opskrifter" laver en kopi og viser "Åbn"',
        (tester) async {
      await pumpDetail(tester, 'orig');
      await tapD(tester, find.byKey(const Key('save-shared-recipe')));

      final docs = await copies();
      expect(docs, hasLength(1));
      final copy = docs.single.data();
      expect(copy['householdId'], 'HH');
      expect(copy['createdBy'], 'me');
      expect(copy['visibility'], 'household');
      expect(copy['title'], 'Evas lasagne');
      expect(copy.containsKey('authorName'), isFalse);
      expect(find.text('Gemt i jeres opskrifter'), findsOneWidget);

      await tester.tap(find.text('Åbn'));
      await pumpFrames(tester);
      // Kopien er husstandens egen: redigér-knap, ingen "Gem"-knap.
      expect(find.byKey(const Key('save-shared-recipe')), findsNothing);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.text('Evas lasagne'), findsOneWidget);
    });

    testWidgets('gem to gange giver ingen dublet', (tester) async {
      await pumpDetail(tester, 'orig');
      await tapD(tester, find.byKey(const Key('save-shared-recipe')));
      await tester.pump(const Duration(seconds: 5));
      await pumpFrames(tester);
      await tapD(tester, find.byKey(const Key('save-shared-recipe')));

      expect(await copies(), hasLength(1));
      expect(find.text('Opskriften er allerede gemt i jeres opskrifter'),
          findsOneWidget);
    });

    testWidgets('"Til madplan" gemmer først en kopi og bruger KOPIENS id',
        (tester) async {
      await pumpDetail(tester, 'orig');
      expect(await copies(), isEmpty);

      await tapD(tester, find.text('Til madplan'));
      await tapD(tester, find.text('Mandag'));
      await tapD(tester, find.text('Aftensmad'));
      await tapD(tester, find.text('Bekræft'));

      final docs = await copies();
      expect(docs, hasLength(1));
      expect(mealPlan.capturedRecipe, isNotNull);
      expect(mealPlan.capturedRecipe!.id, docs.single.id);
      expect(mealPlan.capturedRecipe!.id, isNot('orig'));
      expect(mealPlan.capturedRecipe!.householdId, 'HH');
    });

    testWidgets('"Til madplan" genbruger en eksisterende kopi', (tester) async {
      await pumpDetail(tester, 'orig');
      await tapD(tester, find.byKey(const Key('save-shared-recipe')));
      final existing = (await copies()).single.id;
      await tester.pump(const Duration(seconds: 5));
      await pumpFrames(tester);

      await tapD(tester, find.text('Til madplan'));
      await tapD(tester, find.text('Mandag'));
      await tapD(tester, find.text('Aftensmad'));
      await tapD(tester, find.text('Bekræft'));

      expect(await copies(), hasLength(1));
      expect(mealPlan.capturedRecipe!.id, existing);
    });

    testWidgets('annulleret "Til madplan" laver ingen kopi', (tester) async {
      await pumpDetail(tester, 'orig');
      await tapD(tester, find.text('Til madplan'));
      await tapD(tester, find.byIcon(Icons.close));
      expect(await copies(), isEmpty);
    });

    testWidgets('"Tilføj til indkøb" tilføjer ingredienserne uden at kopiere',
        (tester) async {
      await pumpDetail(tester, 'orig');
      await tapD(tester, find.text('Tilføj til indkøb'));

      expect(grocery.added.map((g) => g.name), ['Pasta', 'Ost']);
      expect(grocery.added.every((g) => g.source == 'recipe'), isTrue);
      expect(await copies(), isEmpty);
    });

    testWidgets(
        'en slettet opskrift viser en besked i stedet for at gå i stykker',
        (tester) async {
      await pumpDetail(tester, 'findes-ikke');
      expect(find.text('Opskriften findes ikke længere'), findsOneWidget);
    });

    testWidgets(
        'egen delt opskrift: "Delt"-mærke og redigér-knap, ingen forfatter/gem',
        (tester) async {
      await db.collection('recipes').doc('mine').set(_doc('Vores gryde',
          household: 'HH', createdBy: 'me', author: 'Mette'));
      await pumpDetail(tester, 'mine');

      expect(find.text('Delt'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.text('af Mette'), findsNothing);
      expect(find.byKey(const Key('save-shared-recipe')), findsNothing);
    });
  });
}
