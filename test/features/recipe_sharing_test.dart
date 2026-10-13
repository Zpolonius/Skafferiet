// #51: deling af opskrifter - datamodel, første-navn og RecipesNotifier
// (opret/ret/kopiér) mod en falsk Firestore.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/services/recipe_sharing.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipe_mapping.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household(super.state);
}

Recipe _recipe({
  String id = 'new',
  String title = 'Lasagne',
  RecipeVisibility visibility = RecipeVisibility.household,
  String? authorName,
  String? copiedFrom,
}) =>
    Recipe(
      id: id,
      title: title,
      imageUrl: 'https://img/1.jpg',
      calories: 500,
      time: '45 min',
      category: RecipeCategory.aftensmad,
      ingredients: [
        Ingredient(
          name: 'Pasta',
          quantity: 250,
          unit: 'g',
          category: 'Kolonial',
          nutritionPer100:
              const Nutrition(kcal: 350, protein: 12, carbs: 70, fat: 1.5),
        ),
      ],
      instructions: const ['Kog pasta', 'Server'],
      servings: 4,
      protein: 20,
      carbs: 50,
      fat: 10,
      nutritionFromIngredients: true,
      visibility: visibility,
      authorName: authorName,
      copiedFrom: copiedFrom,
    );

void main() {
  group('authorFirstName', () {
    test('første ord i navnet', () {
      expect(authorFirstName('Mette Hansen'), 'Mette');
      expect(authorFirstName('  Anne-Marie   Sørensen '), 'Anne-Marie');
      expect(authorFirstName('Mette'), 'Mette');
    });

    test('tomt eller manglende navn bliver "Ukendt"', () {
      expect(authorFirstName(null), 'Ukendt');
      expect(authorFirstName(''), 'Ukendt');
      expect(authorFirstName('   '), 'Ukendt');
    });

    test('en e-mail (profilens reserve-navn) afsløres aldrig', () {
      expect(authorFirstName('mette@example.com'), 'Ukendt');
      expect(authorFirstName('Mette m@example.com'), 'Ukendt');
    });

    test('højst 40 UTF-16-enheder (grænsen i firestore.rules)', () {
      expect(authorFirstName('x' * 80).length, 40);
      expect(authorFirstName('æ' * 41), 'æ' * 40);
    });

    test('et surrogatpar splittes aldrig', () {
      // 20 emoji = 40 enheder: uændret. 21 emoji klippes til 20 hele emoji.
      expect(authorFirstName('😀' * 20), '😀' * 20);
      expect(authorFirstName('😀' * 21), '😀' * 20);
      // Grænsen falder midt i et par: den halve emoji droppes (39 enheder).
      final r = authorFirstName('a${'😀' * 30}');
      expect(r.length, 39);
      expect(r.runes.last, 0x1F600);
    });

    test('navne der kan udgive sig for appen bliver "Ukendt"', () {
      for (final n in [
        'Skafferiet',
        'Support',
        'ADMIN',
        'Administrator',
        'Moderator',
        'MrAdmin'
      ]) {
        expect(authorFirstName(n), 'Ukendt', reason: n);
      }
      expect(authorFirstName('Admin Hansen'), 'Ukendt');
      expect(authorFirstName('Anne Support'), 'Anne');
    });
  });

  group('mapping', () {
    test('manglende felter = husstand, ingen forfatter, ingen kopi', () {
      final r = recipeFromMap('a', {'title': 'Suppe'});
      expect(r.visibility, RecipeVisibility.household);
      expect(r.isShared, isFalse);
      expect(r.authorName, isNull);
      expect(r.copiedFrom, isNull);
    });

    test('ukendt visibility regnes som husstand', () {
      expect(recipeFromMap('a', {'visibility': 'secret'}).visibility,
          RecipeVisibility.household);
      expect(recipeFromMap('a', {'visibility': null}).isShared, isFalse);
    });

    test('delt opskrift læses med forfatter og kopi-henvisning', () {
      final r = recipeFromMap('a', {
        'title': 'Suppe',
        'visibility': 'public',
        'authorName': 'Mette',
        'copiedFrom': 'orig',
      });
      expect(r.isShared, isTrue);
      expect(r.authorName, 'Mette');
      expect(r.copiedFrom, 'orig');
    });

    test('tom authorName/copiedFrom læses som null', () {
      final r = recipeFromMap('a', {'authorName': '', 'copiedFrom': ''});
      expect(r.authorName, isNull);
      expect(r.copiedFrom, isNull);
    });

    test(
        'recipeToFields: visibility og titleLower altid; forfatter kun når delt',
        () {
      final priv =
          recipeToFields(_recipe(title: 'Æblekage', authorName: 'Mette'));
      expect(priv['visibility'], 'household');
      expect(priv['titleLower'], 'æblekage');
      expect(priv.containsKey('authorName'), isFalse,
          reason: 'fornavnet gemmes ikke på private opskrifter');
      expect(priv.containsKey('copiedFrom'), isFalse);

      final shared = recipeToFields(_recipe(
          visibility: RecipeVisibility.public,
          authorName: 'Mette',
          copiedFrom: 'o'));
      expect(shared['visibility'], 'public');
      expect(shared['authorName'], 'Mette');
      expect(shared['copiedFrom'], 'o');
    });

    test('titleLower stemmer med reglerne for æ/ø/å', () {
      for (final (title, lower) in [
        ('Æblegrød', 'æblegrød'),
        ('ØLLEBRØD', 'øllebrød'),
        ('Åkande', 'åkande'),
        ('Pasta Carbonara', 'pasta carbonara'),
      ]) {
        expect(recipeToFields(_recipe(title: title))['titleLower'], lower);
      }
    });

    test('rundtur bevarer indholdet', () {
      final original =
          _recipe(visibility: RecipeVisibility.public, authorName: 'Mette');
      final back = recipeFromMap('x', recipeToFields(original));
      expect(back.title, original.title);
      expect(back.ingredients.single.nutritionPer100!.kcal, 350);
      expect(back.instructions, original.instructions);
      expect(back.servings, 4);
      expect(back.visibility, RecipeVisibility.public);
    });
  });

  group('RecipesNotifier', () {
    late FakeFirebaseFirestore db;
    late ProviderContainer container;
    late RecipesNotifier notifier;

    setUp(() async {
      db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'me', email: 'me@example.com', displayName: 'Mette Hansen'),
      );
      container = ProviderContainer(overrides: [
        householdProvider.overrideWith((ref) => _Household(HouseholdState(
              householdId: 'HH',
              memberNames: const {
                'me': 'Mette Hansen',
                'partner': 'Peter Jensen'
              },
            ))),
        recipesProvider
            .overrideWith(() => RecipesNotifier(firestore: db, auth: auth)),
      ]);
      addTearDown(container.dispose);
      notifier = container.read(recipesProvider.notifier);
    });

    Future<Map<String, dynamic>> doc(String id) async =>
        (await db.collection('recipes').doc(id).get()).data()!;

    Future<String> onlyId() async =>
        (await db.collection('recipes').get()).docs.single.id;

    test('ny privat opskrift: visibility household, ingen forfatter', () async {
      await notifier.addRecipe(_recipe());
      final data = await doc(await onlyId());
      expect(data['visibility'], 'household');
      expect(data['householdId'], 'HH');
      expect(data['createdBy'], 'me');
      expect(data['titleLower'], 'lasagne');
      expect(data.containsKey('authorName'), isFalse);
    });

    test('ny delt opskrift får skaberens fornavn', () async {
      await notifier.addRecipe(_recipe(visibility: RecipeVisibility.public));
      final data = await doc(await onlyId());
      expect(data['visibility'], 'public');
      expect(data['authorName'], 'Mette');
    });

    test('at dele sin egen opskrift via redigering gemmer eget fornavn',
        () async {
      await db.collection('recipes').doc('m1').set({
        'title': 'Min suppe',
        'householdId': 'HH',
        'createdBy': 'me',
        'visibility': 'household',
        'category': 'RecipeCategory.aftensmad',
      });
      await notifier.updateRecipe(Recipe(
        id: 'm1',
        title: 'Min suppe',
        calories: 0,
        time: '',
        category: RecipeCategory.aftensmad,
        householdId: 'HH',
        createdBy: 'me',
        visibility: RecipeVisibility.public,
      ));
      final data = await doc('m1');
      expect(data['visibility'], 'public');
      expect(data['authorName'], 'Mette');
    });

    test('stopSharing: visibility household og fornavnet fjernet, intet andet',
        () async {
      await db.collection('recipes').doc('s1').set({
        'title': 'Delt',
        'titleLower': 'delt',
        'householdId': 'OLD',
        'createdBy': 'me',
        'visibility': 'public',
        'authorName': 'Mette',
      });
      await notifier.stopSharing('s1');
      final data = await doc('s1');
      expect(data['visibility'], 'household');
      expect(data.containsKey('authorName'), isFalse);
      expect(data['title'], 'Delt');
      expect(data['householdId'], 'OLD');
    });

    test('et eksisterende fornavn bevares ved redigering', () async {
      await db.collection('recipes').doc('r').set({
        'title': 'X',
        'householdId': 'HH',
        'createdBy': 'me',
        'visibility': 'public',
        'authorName': 'Gammelt',
      });
      await notifier.updateRecipe(_recipe(
          id: 'r', visibility: RecipeVisibility.public, authorName: 'Gammelt'));
      expect((await doc('r'))['authorName'], 'Gammelt');
    });

    test('at slå deling fra igen fjerner fornavnet og sætter household',
        () async {
      await db.collection('recipes').doc('r').set({
        'title': 'X',
        'householdId': 'HH',
        'createdBy': 'me',
        'visibility': 'public',
        'authorName': 'Mette',
      });
      await notifier.updateRecipe(_recipe(id: 'r'));
      final data = await doc('r');
      expect(data['visibility'], 'household');
      expect(data.containsKey('authorName'), isFalse);
    });

    test('profil med e-mail som navn giver "Ukendt", ikke e-mailen', () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'me', email: 'me@example.com', displayName: 'me@example.com'),
      );
      final c = ProviderContainer(overrides: [
        householdProvider.overrideWith(
            (ref) => _Household(HouseholdState(householdId: 'HH'))),
        recipesProvider
            .overrideWith(() => RecipesNotifier(firestore: db, auth: auth)),
      ]);
      addTearDown(c.dispose);
      await c
          .read(recipesProvider.notifier)
          .addRecipe(_recipe(visibility: RecipeVisibility.public));
      expect((await doc(await onlyId()))['authorName'], 'Ukendt');
    });

    test(
        '"Vores"-strømmen (også madplanens vælger) ser aldrig andre husstandes delte opskrifter',
        () async {
      await db
          .collection('recipes')
          .doc('mine')
          .set({'title': 'Min', 'householdId': 'HH'});
      await db
          .collection('recipes')
          .doc('global')
          .set({'title': 'Global', 'householdId': null});
      await db.collection('recipes').doc('theirPublic').set({
        'title': 'Deres',
        'householdId': 'OTHER',
        'visibility': 'public',
        'authorName': 'Eva',
      });
      final list = await container.read(recipesProvider.future);
      expect(list.map((r) => r.id).toSet(), {'mine', 'global'});
    });

    group('copyToHousehold', () {
      Future<void> seedOriginal() => db.collection('recipes').doc('orig').set({
            ...recipeToFields(_recipe(
                id: 'orig',
                visibility: RecipeVisibility.public,
                authorName: 'Eva')),
            'householdId': 'OTHER',
            'createdBy': 'eva',
            'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          });

      test('laver en privat kopi i egen husstand med samme indhold og billede',
          () async {
        await seedOriginal();
        final source = recipeFromMap('orig', await doc('orig'));

        final copy = await notifier.copyToHousehold(source);

        expect(copy.id, isNot('orig'));
        final data = await doc(copy.id);
        expect(data['householdId'], 'HH');
        expect(data['createdBy'], 'me');
        expect(data['visibility'], 'household');
        expect(data['copiedFrom'], 'orig');
        expect(data.containsKey('authorName'), isFalse);
        expect(data['imageUrl'], 'https://img/1.jpg',
            reason: 'billed-URL genbruges');
        expect(data['title'], 'Lasagne');
        expect(data['instructions'], ['Kog pasta', 'Server']);
        expect(data['servings'], 4);
        expect(data['calories'], 500);
        expect((data['ingredients'] as List).single['nutrition']['kcal'], 350);
        expect(copy.householdId, 'HH');
        expect(copy.visibility, RecipeVisibility.household);
      });

      test('originalen røres ikke', () async {
        await seedOriginal();
        final before = await doc('orig');
        await notifier.copyToHousehold(recipeFromMap('orig', before));
        expect(await doc('orig'), before);
      });

      test('kopiering to gange giver den samme kopi, ingen dublet', () async {
        await seedOriginal();
        final source = recipeFromMap('orig', await doc('orig'));

        final first = await notifier.copyToHousehold(source);
        final second = await notifier.copyToHousehold(source);

        expect(second.id, first.id);
        final mine = await db
            .collection('recipes')
            .where('householdId', isEqualTo: 'HH')
            .get();
        expect(mine.docs, hasLength(1));
      });

      test('en kopi i en anden husstand tæller ikke som min kopi', () async {
        await seedOriginal();
        await db.collection('recipes').doc('theirCopy').set({
          'title': 'Lasagne',
          'householdId': 'THIRD',
          'createdBy': 'z',
          'copiedFrom': 'orig',
        });
        final copy = await notifier
            .copyToHousehold(recipeFromMap('orig', await doc('orig')));
        expect(copy.id, isNot('theirCopy'));
      });
    });
  });
}
