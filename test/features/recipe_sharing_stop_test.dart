// "Stop med at dele" (#51) på detaljesiden for en opskrift, jeg selv har delt,
// men som ligger i en husstand, jeg har forladt.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/community_recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipe_detail_screen.dart';
import 'package:skafferiet/features/recipes/recipe_mapping.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'NEW'));
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('recipes').doc('mine').set({
      ...recipeToFields(Recipe(
        id: '',
        title: 'Min gamle lasagne',
        imageUrl: null,
        calories: 400,
        time: '30 min',
        category: RecipeCategory.aftensmad,
        ingredients: const [],
        instructions: const ['Lav maden'],
        visibility: RecipeVisibility.public,
        authorName: 'Mette',
      )),
      'householdId': 'OLD',
      'createdBy': 'me',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  });

  Future<void> frames(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> pump(WidgetTester tester, {required String uid}) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: '$uid@example.com', displayName: 'Mette'),
    );
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, __) => const Scaffold(body: Text('start'))),
        GoRoute(
            path: '/recipes/:id',
            builder: (_, s) => RecipeDetailScreen(recipeId: s.pathParameters['id']!)),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        householdProvider.overrideWith((ref) => _Household()),
        currentUserIdProvider.overrideWithValue(uid),
        recipesProvider.overrideWith(() => RecipesNotifier(firestore: db, auth: auth)),
        recipeByIdProvider.overrideWith((ref, id) async {
          final d = await db.collection('recipes').doc(id).get();
          return d.exists ? recipeFromMap(d.id, d.data()!) : null;
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/recipes/mine');
    await frames(tester);
  }

  testWidgets('skaberen i en anden husstand ser "Stop med at dele" og kan stoppe', (tester) async {
    await pump(tester, uid: 'me');

    expect(find.text('Min gamle lasagne'), findsOneWidget);
    expect(find.text('Gem i vores opskrifter'), findsNothing);
    final stop = find.byKey(const Key('stop-sharing-recipe'));
    expect(stop, findsOneWidget);
    expect(tester.getSize(stop).height, greaterThanOrEqualTo(48));

    await tester.ensureVisible(stop);
    await tester.tap(stop);
    await frames(tester);
    // Annuller ændrer intet.
    await tester.tap(find.text('Annuller'));
    await frames(tester);
    expect((await db.doc('recipes/mine').get()).data()!['visibility'], 'public');

    await tester.tap(stop);
    await frames(tester);
    await tester.tap(find.byKey(const Key('confirm-stop-sharing')));
    await frames(tester);

    final data = (await db.doc('recipes/mine').get()).data()!;
    expect(data['visibility'], 'household');
    expect(data.containsKey('authorName'), isFalse);
    expect(data['title'], 'Min gamle lasagne', reason: 'intet andet ændres');
    expect(find.text('Opskriften deles ikke længere'), findsOneWidget);
  });

  testWidgets('en anden bruger ser "Gem i vores opskrifter", ikke "Stop med at dele"', (tester) async {
    await pump(tester, uid: 'someoneElse');
    expect(find.text('Gem i vores opskrifter'), findsOneWidget);
    expect(find.text('Stop med at dele'), findsNothing);
  });
}
