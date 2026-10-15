// #52: rapportering, blokering og skjulning af delte opskrifter i appen -
// menuen på detaljesiden, rapport-formularen, blokering, profilens liste over
// blokerede brugere, Fællesskab-listen og "fjernet af moderator".
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/recipe_report.dart';
import 'package:skafferiet/core/services/moderation_service.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/moderation/blocked_users_screen.dart';
import 'package:skafferiet/features/moderation/moderation_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/community_recipes_provider.dart';
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

class _OwnRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  final List<Recipe> recipes;
  _OwnRecipes(this.recipes);
  @override
  Stream<List<Recipe>> build() => Stream.value(recipes);
}

/// Service hvor skrivninger fejler, til fejltilstanden i rapport-formularen.
class _FailingService extends ModerationService {
  _FailingService(FirebaseFirestore db) : super(firestore: db, uid: 'me');
  @override
  Future<void> reportRecipe({
    required String recipeId,
    required ReportReason reason,
    String comment = '',
  }) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
}

Map<String, dynamic> _doc(String title,
        {String household = 'OTHER',
        String createdBy = 'eva',
        String? author = 'Eva',
        RecipeVisibility visibility = RecipeVisibility.public,
        int day = 2}) =>
    {
      ...recipeToFields(Recipe(
        id: '',
        title: title,
        calories: 400,
        time: '30 min',
        category: RecipeCategory.aftensmad,
        visibility: visibility,
        authorName: author,
      )),
      'householdId': household,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, day)),
    };

void main() {
  late FakeFirebaseFirestore db;
  late ModerationService moderation;

  setUp(() async {
    db = FakeFirebaseFirestore();
    moderation = ModerationService(firestore: db, uid: 'me');
    await db.collection('recipes').doc('orig').set(_doc('Evas lasagne'));
    await db.collection('recipes').doc('orig2').set(_doc('Evas suppe', day: 3));
    await db
        .collection('recipes')
        .doc('per')
        .set(_doc('Pers pizza', createdBy: 'per', author: 'Per', day: 4));
    await db.collection('recipes').doc('mine').set(
        _doc('Vores suppe', household: 'HH', createdBy: 'me', author: 'Mette'));
  });

  void phone(WidgetTester tester, {double w = 360, double h = 900}) {
    tester.view.physicalSize = Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  // Detaljesiden har en uendelig spinner som pladsholder for billedet (kun
  // uden netværk), så pumpAndSettle kan ikke bruges.
  Future<void> pumpFrames(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
  }

  Future<void> pumpDetail(WidgetTester tester, String id,
      {ModerationService? service, List<Recipe> own = const []}) async {
    phone(tester);
    final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser:
            MockUser(uid: 'me', email: 'me@example.com', displayName: 'Mette'));
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
        moderationServiceProvider.overrideWithValue(service ?? moderation),
        recipeByIdProvider.overrideWith((ref, id) async {
          final d = await db.collection('recipes').doc(id).get();
          return d.exists ? recipeFromMap(d.id, d.data()!) : null;
        }),
      ],
      child:
          MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    ));
    router.push('/recipes/$id');
    await pumpFrames(tester);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Flere valg'));
    await pumpFrames(tester);
  }

  group('Menu på detaljesiden', () {
    testWidgets('en andens delte opskrift har menuen med rapportér og blokér',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDetail(tester, 'orig');
      expect(find.byTooltip('Flere valg'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Flere valg')).shortestSide,
          greaterThanOrEqualTo(48));
      await openMenu(tester);
      expect(find.text('Rapportér opskrift'), findsOneWidget);
      expect(find.text('Blokér Eva'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('husstandens egen delte opskrift har ingen menu',
        (tester) async {
      await pumpDetail(tester, 'mine');
      expect(find.byTooltip('Flere valg'), findsNothing);
    });

    testWidgets('en opskrift i husstandens egen liste har ingen menu',
        (tester) async {
      await db.collection('recipes').doc('own2').set(_doc('Privat',
          household: 'HH',
          createdBy: 'me',
          visibility: RecipeVisibility.household,
          author: null));
      await pumpDetail(tester, 'own2');
      expect(find.byTooltip('Flere valg'), findsNothing);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets(
        'en skaber der har forladt husstanden kan ikke rapportere sin egen',
        (tester) async {
      await db.collection('recipes').doc('left').set(_doc('Min gamle',
          household: 'OTHER', createdBy: 'me', author: 'Mette'));
      await pumpDetail(tester, 'left');
      expect(find.text('Stop med at dele'), findsOneWidget);
      expect(find.byTooltip('Flere valg'), findsNothing);
    });
  });

  group('Rapportér opskrift', () {
    Future<void> openSheet(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Rapportér opskrift'));
      await pumpFrames(tester);
    }

    testWidgets(
        'formularen har de fem årsager, en kommentar på højst 500 tegn, og '
        '"Send rapport" er slået fra, til en årsag er valgt', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDetail(tester, 'orig');
      await openSheet(tester);

      for (final label in [
        'Upassende eller stødende indhold',
        'Spam eller reklame',
        'Forkerte oplysninger (ingredienser, mængder, næring)',
        'Kopieret uden tilladelse (tekst eller billede)',
        'Andet',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(RadioListTile<Object?>), findsNothing);
      expect(
          tester
              .widgetList(find.byWidgetPredicate((w) => w is RadioListTile))
              .length,
          5);
      for (final tile in tester
          .widgetList(find.byWidgetPredicate((w) => w is RadioListTile))) {
        expect(tester.getSize(find.byWidget(tile)).height,
            greaterThanOrEqualTo(48));
      }
      final field =
          tester.widget<TextField>(find.byKey(const Key('report-comment')));
      expect(field.maxLength, 500);
      expect(find.text('0/500'), findsOneWidget, reason: 'tegntæller');

      FilledButton send() =>
          tester.widget<FilledButton>(find.byKey(const Key('send-report')));
      expect(send().onPressed, isNull);
      await tester.tap(find.text('Spam eller reklame'));
      await pumpFrames(tester);
      expect(send().onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('rapporten gemmes, der takkes, og opskriften forlades',
        (tester) async {
      await pumpDetail(tester, 'orig');
      await openSheet(tester);
      await tester
          .tap(find.text('Kopieret uden tilladelse (tekst eller billede)'));
      await pumpFrames(tester);
      await tester.enterText(
          find.byKey(const Key('report-comment')), 'Fra en blog');
      await tester.tap(find.byKey(const Key('send-report')));
      await pumpFrames(tester);

      final d = (await db.doc('reports/orig_me').get()).data()!;
      expect(d['reason'], 'copyright');
      expect(d['comment'], 'Fra en blog');
      expect(d['reportedBy'], 'me');
      expect(d['recipeId'], 'orig');
      expect(find.text('Tak – vi kigger på det'), findsOneWidget);
      expect(find.text('start'), findsOneWidget,
          reason: 'tilbage fra opskriften');
    });

    testWidgets(
        'en kommentar med mange emoji er for lang til databasen og siger det '
        'tydeligt i stedet for "Tjek din forbindelse"', (tester) async {
      await pumpDetail(tester, 'orig');
      await openSheet(tester);
      await tester.tap(find.text('Andet'));
      await pumpFrames(tester);
      // 300 emoji = 300 tegn i feltet, men 600 UTF-16-enheder i databasen.
      await tester.enterText(
          find.byKey(const Key('report-comment')), '😀' * 300);
      await tester.tap(find.byKey(const Key('send-report')));
      await pumpFrames(tester);

      expect(find.textContaining('Kommentaren er for lang'), findsOneWidget);
      expect(find.textContaining('Tjek din forbindelse'), findsNothing);
      expect(find.byKey(const Key('send-report')), findsOneWidget);
      expect((await db.doc('reports/orig_me').get()).exists, isFalse);
    });

    testWidgets('en fejl vises i formularen, som bliver åben', (tester) async {
      await pumpDetail(tester, 'orig', service: _FailingService(db));
      await openSheet(tester);
      await tester.tap(find.text('Andet'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('send-report')));
      await pumpFrames(tester);

      expect(
          find.textContaining('Rapporten kunne ikke sendes'), findsOneWidget);
      expect(find.byKey(const Key('send-report')), findsOneWidget);
      expect(find.text('Tak – vi kigger på det'), findsNothing);
      expect(find.text('start'), findsNothing);
      // ... og kan prøves igen.
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('send-report')))
              .onPressed,
          isNotNull);
    });

    testWidgets('360 dp bred og lav skærm uden overflow', (tester) async {
      phone(tester, h: 500);
      await pumpDetail(tester, 'orig');
      phone(tester, h: 500);
      await openSheet(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Blokér forfatter', () {
    testWidgets('dialogen forklarer hvad der sker, og annuller blokerer ingen',
        (tester) async {
      await pumpDetail(tester, 'orig');
      await openMenu(tester);
      await tester.tap(find.text('Blokér Eva'));
      await pumpFrames(tester);

      expect(find.text('Blokér Eva?'), findsOneWidget);
      expect(find.textContaining('Alle opskrifter fra Eva skjules for dig'),
          findsOneWidget);
      expect(find.textContaining('Profil → Blokerede brugere'), findsOneWidget);
      await tester.tap(find.text('Annuller'));
      await pumpFrames(tester);
      expect(
          (await db
                  .collection('users')
                  .doc('me')
                  .collection('blocked_authors')
                  .get())
              .docs,
          isEmpty);
      expect(find.text('Evas lasagne'), findsOneWidget,
          reason: 'stadig på opskriften');
    });

    testWidgets('bekræftet: forfatteren blokeres, snackbar og tilbage',
        (tester) async {
      await pumpDetail(tester, 'orig');
      await openMenu(tester);
      await tester.tap(find.text('Blokér Eva'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('confirm-block-author')));
      await pumpFrames(tester);

      final d = (await db.doc('users/me/blocked_authors/eva').get()).data()!;
      expect(d['name'], 'Eva');
      expect(find.textContaining('Eva er blokeret'), findsOneWidget);
      expect(find.text('start'), findsOneWidget);
      // Husstandens egne opskrifter og kopier røres ikke.
      expect((await db.doc('recipes/mine').get()).exists, isTrue);
    });
  });

  group('Fællesskab skjuler rapporterede opskrifter og blokerede forfattere',
      () {
    Future<void> pumpTab(WidgetTester tester,
        {List<Recipe> own = const []}) async {
      phone(tester);
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
          recipesProvider.overrideWith(() => _OwnRecipes(own)),
          currentUserIdProvider.overrideWithValue('me'),
          moderationServiceProvider.overrideWithValue(moderation),
          communityRecipesProvider
              .overrideWith(() => CommunityRecipesNotifier(firestore: db)),
        ],
        child: MaterialApp.router(
            theme: AppTheme.lightTheme, routerConfig: router),
      ));
      await settle(tester);
      await tester.tap(find.text('Fællesskab'));
      await settle(tester);
    }

    testWidgets(
        'uden rapporter og blokeringer vises alle andres delte opskrifter',
        (tester) async {
      await pumpTab(tester);
      expect(find.text('Evas lasagne'), findsOneWidget);
      expect(find.text('Evas suppe'), findsOneWidget);
      expect(find.text('Pers pizza'), findsOneWidget);
    });

    testWidgets(
        'en rapporteret opskrift er væk - og forbliver væk efter genstart',
        (tester) async {
      await moderation.reportRecipe(
          recipeId: 'orig', reason: ReportReason.spam);
      await pumpTab(tester);
      expect(find.text('Evas lasagne'), findsNothing);
      expect(find.text('Evas suppe'), findsOneWidget);
      expect(find.text('Pers pizza'), findsOneWidget);
    });

    testWidgets(
        'en rapport fra en anden bruger skjuler ikke opskriften for mig',
        (tester) async {
      await db
          .doc('reports/orig_you')
          .set({'recipeId': 'orig', 'reportedBy': 'you'});
      await pumpTab(tester);
      expect(find.text('Evas lasagne'), findsOneWidget);
    });

    testWidgets(
        'en blokeret forfatters opskrifter er væk i listen og i søgningen',
        (tester) async {
      await moderation.blockAuthor(authorUid: 'eva', name: 'Eva');
      await pumpTab(tester);
      expect(find.text('Evas lasagne'), findsNothing);
      expect(find.text('Evas suppe'), findsNothing);
      expect(find.text('Pers pizza'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'evas');
      await settle(tester);
      expect(find.text('Evas lasagne'), findsNothing);
      expect(find.text('Evas suppe'), findsNothing);
      expect(find.text('Ingen opskrifter fundet'), findsOneWidget);
    });

    testWidgets('en blokering skjuler ikke egne gemte kopier under Vores',
        (tester) async {
      await moderation.blockAuthor(authorUid: 'eva', name: 'Eva');
      final copy = Recipe(
        id: 'c1',
        title: 'Evas lasagne',
        calories: 1,
        time: '',
        category: RecipeCategory.aftensmad,
        householdId: 'HH',
        createdBy: 'eva',
        copiedFrom: 'orig',
      );
      await pumpTab(tester, own: [copy]);
      await tester.tap(find.text('Vores'));
      await settle(tester);
      expect(find.text('Evas lasagne'), findsOneWidget);
    });

    testWidgets(
        'fjernes blokeringen, kommer opskrifterne tilbage med det samme',
        (tester) async {
      await moderation.blockAuthor(authorUid: 'eva', name: 'Eva');
      await pumpTab(tester);
      expect(find.text('Evas lasagne'), findsNothing);
      await moderation.unblockAuthor('eva');
      await settle(tester);
      expect(find.text('Evas lasagne'), findsOneWidget);
      expect(find.text('Evas suppe'), findsOneWidget);
    });
  });

  group('Profil → Blokerede brugere', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          moderationServiceProvider.overrideWithValue(moderation),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const BlockedUsersScreen()),
      ));
      await settle(tester);
    }

    testWidgets('tom liste viser en forklaring', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Blokerede brugere'), findsOneWidget);
      expect(find.text('Du har ikke blokeret nogen'), findsOneWidget);
    });

    testWidgets('viser navnene og kan fjerne en blokering (mindst 48 dp)',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await moderation.blockAuthor(authorUid: 'eva', name: 'Eva');
      await moderation.blockAuthor(authorUid: 'per', name: 'Per');
      await pumpScreen(tester);

      expect(find.text('Eva'), findsOneWidget);
      expect(find.text('Per'), findsOneWidget);
      expect(find.text('Fjern blokering'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Fjern blokering af Eva'), findsOneWidget);
      for (final b in tester.widgetList(find.byType(TextButton))) {
        expect(
            tester.getSize(find.byWidget(b)).height, greaterThanOrEqualTo(48));
        expect(
            tester.getSize(find.byWidget(b)).width, greaterThanOrEqualTo(48));
      }

      await tester.tap(find.text('Fjern blokering').first);
      await settle(tester);
      expect(
          (await db
                  .collection('users')
                  .doc('me')
                  .collection('blocked_authors')
                  .get())
              .size,
          1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('sidste blokering fjernet giver tom-tilstanden igen',
        (tester) async {
      await moderation.blockAuthor(authorUid: 'eva', name: 'Eva');
      await pumpScreen(tester);
      await tester.tap(find.text('Fjern blokering'));
      await settle(tester);
      expect(find.text('Du har ikke blokeret nogen'), findsOneWidget);
    });
  });

  group('Fjernet af en moderator (visibility: hidden)', () {
    Recipe hidden() => Recipe(
          id: 'h1',
          title: 'Fjernet ret',
          calories: 100,
          time: '',
          category: RecipeCategory.aftensmad,
          householdId: 'HH',
          createdBy: 'me',
          visibility: RecipeVisibility.hidden,
          authorName: 'Mette',
        );

    testWidgets('detaljesiden viser mærket for husstanden, uden rapportér-menu',
        (tester) async {
      await db.collection('recipes').doc('h1').set(_doc('Fjernet ret',
          household: 'HH',
          createdBy: 'me',
          visibility: RecipeVisibility.hidden,
          author: 'Mette'));
      await pumpDetail(tester, 'h1');
      expect(
          find.text('Fjernet fra Fællesskab af en moderator'), findsOneWidget);
      expect(find.text('Delt'), findsNothing);
      expect(find.byTooltip('Flere valg'), findsNothing);
      expect(find.byIcon(Icons.edit), findsOneWidget,
          reason: 'indholdet kan stadig redigeres');
      expect(tester.takeException(), isNull);
    });

    testWidgets('en almindelig delt opskrift har ikke mærket', (tester) async {
      await pumpDetail(tester, 'mine');
      expect(find.text('Fjernet fra Fællesskab af en moderator'), findsNothing);
      expect(find.text('Delt'), findsOneWidget);
    });

    testWidgets('delingskontakten er slået fra med en forklaring',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserIdProvider.overrideWithValue('me')],
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: EditRecipeScreen(recipe: hidden())),
      ));
      await tester.scrollUntilVisible(
          find.byKey(const Key('share-recipe-switch')), 200,
          scrollable: find.byType(Scrollable).first);
      final sw =
          tester.widget<Switch>(find.byKey(const Key('share-recipe-switch')));
      expect(sw.onChanged, isNull);
      expect(sw.value, isFalse);
      expect(find.textContaining('fjernet fra Fællesskab af en moderator'),
          findsOneWidget);
    });

    testWidgets('en redigering bevarer "hidden" (reglerne tillader ikke andet)',
        (tester) async {
      phone(tester);
      final notifier = _Capturing();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          recipesProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: EditRecipeScreen(recipe: hidden())),
      ));
      await tester.scrollUntilVisible(find.text('Gem ændringer'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Gem ændringer'));
      await pumpFrames(tester);
      expect(notifier.updated!.visibility, RecipeVisibility.hidden);
    });

    testWidgets(
        'et gammelt link til en fjernet opskrift viser "findes ikke længere"',
        (tester) async {
      // En fremmed kan ikke læse opskriften (reglerne): opslaget giver null.
      phone(tester);
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
          recipesProvider.overrideWith(() => _OwnRecipes(const [])),
          currentUserIdProvider.overrideWithValue('me'),
          recipeByIdProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp.router(
            theme: AppTheme.lightTheme, routerConfig: router),
      ));
      router.push('/recipes/h1');
      await pumpFrames(tester);
      expect(find.text('Opskriften findes ikke længere'), findsOneWidget);
    });
  });
}

class _Capturing extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  Recipe? updated;
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
  @override
  Future<void> updateRecipe(Recipe updatedRecipe) async =>
      updated = updatedRecipe;
}
