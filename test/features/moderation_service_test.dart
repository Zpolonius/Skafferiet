// #52: ModerationService (rapporter og blokeringer) og filtreringen af
// Fællesskab. Reglerne for de samme dokumenter testes i rules_test/.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/recipe_report.dart';
import 'package:skafferiet/core/services/moderation_service.dart';
import 'package:skafferiet/features/moderation/moderation_provider.dart';

Recipe _r(String id, String? by) => Recipe(
    id: id,
    title: id,
    calories: 0,
    time: '',
    category: RecipeCategory.aftensmad,
    createdBy: by);

void main() {
  late FakeFirebaseFirestore db;
  late ModerationService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = ModerationService(firestore: db, uid: 'me');
  });

  group('rapporter', () {
    test('gemmes i reports/{recipeId}_{uid} med de aftalte felter', () async {
      await service.reportRecipe(
          recipeId: 'r1',
          reason: ReportReason.wrongInfo,
          comment: '  Forkert mængde  ');
      final doc = await db.doc('reports/r1_me').get();
      final d = doc.data()!;
      expect(d.keys.toSet(),
          {'recipeId', 'reportedBy', 'reason', 'comment', 'createdAt'});
      expect(d['recipeId'], 'r1');
      expect(d['reportedBy'], 'me');
      expect(d['reason'], 'wrong_info');
      expect(d['comment'], 'Forkert mængde');
      expect(d['createdAt'], isA<Timestamp>());
    });

    test('en ny rapport overskriver den gamle (ét dokument)', () async {
      await service.reportRecipe(
          recipeId: 'r1', reason: ReportReason.spam, comment: 'a');
      await service.reportRecipe(
          recipeId: 'r1', reason: ReportReason.copyright);
      final all = await db.collection('reports').get();
      expect(all.docs, hasLength(1));
      expect(all.docs.single.data()['reason'], 'copyright');
      expect(all.docs.single.data()['comment'], '');
    });

    test('årsagerne har de nøgler reglerne forventer', () {
      expect(ReportReason.values.map((r) => r.key),
          ['offensive', 'spam', 'wrong_info', 'copyright', 'other']);
    });

    test('en kommentar over 500 tegn afvises, før den sendes', () async {
      expect(
          () => service.reportRecipe(
              recipeId: 'r1',
              reason: ReportReason.other,
              comment: 'x' * (maxReportCommentLength + 1)),
          throwsArgumentError);
      expect((await db.collection('reports').get()).docs, isEmpty);
    });

    test('uden login kan man ikke rapportere', () {
      final anon = ModerationService(firestore: db, uid: null);
      expect(() => anon.reportRecipe(recipeId: 'r1', reason: ReportReason.spam),
          throwsStateError);
    });

    test('kun egne rapporter lyttes til', () async {
      await db.doc('reports/r1_me').set({'recipeId': 'r1', 'reportedBy': 'me'});
      await db
          .doc('reports/r2_you')
          .set({'recipeId': 'r2', 'reportedBy': 'you'});
      expect(await service.watchReportedRecipeIds().first, {'r1'});
    });
  });

  group('blokering', () {
    test('gemmes i undersamlingen hos brugeren selv, med fornavn', () async {
      await service.blockAuthor(authorUid: 'eva', name: 'Eva Hansen');
      final d = (await db.doc('users/me/blocked_authors/eva').get()).data()!;
      expect(d.keys.toSet(), {'name', 'blockedAt'});
      expect(d['name'], 'Eva');
      expect((await db.doc('users/me').get()).exists, false,
          reason: 'profilen røres ikke');
    });

    test('kan hentes og fjernes igen', () async {
      await service.blockAuthor(authorUid: 'eva', name: 'Eva');
      await service.blockAuthor(authorUid: 'per', name: 'Per');
      final list = await service.watchBlockedAuthors().first;
      expect(list.map((b) => b.uid).toSet(), {'eva', 'per'});
      await service.unblockAuthor('eva');
      expect((await service.watchBlockedAuthors().first).map((b) => b.uid),
          ['per']);
    });

    test('et ukendt eller ugyldigt navn bliver til "Ukendt"', () async {
      await service.blockAuthor(authorUid: 'x', name: null);
      expect((await db.doc('users/me/blocked_authors/x').get()).data()!['name'],
          'Ukendt');
    });
  });

  group('filtrering af Fællesskab', () {
    final recipes = [
      _r('a', 'eva'),
      _r('b', 'per'),
      _r('c', 'eva'),
      _r('d', null)
    ];

    test('uden rapporter eller blokeringer vises alt', () {
      expect(
          withoutModerated(recipes, reportedIds: {}, blockedAuthorIds: {})
              .map((r) => r.id),
          ['a', 'b', 'c', 'd']);
    });

    test('rapporterede opskrifter skjules', () {
      expect(
          withoutModerated(recipes, reportedIds: {'b'}, blockedAuthorIds: {})
              .map((r) => r.id),
          ['a', 'c', 'd']);
    });

    test('alle opskrifter fra en blokeret forfatter skjules', () {
      expect(
          withoutModerated(recipes, reportedIds: {}, blockedAuthorIds: {'eva'})
              .map((r) => r.id),
          ['b', 'd']);
    });

    test('begge dele kan kombineres, og en opskrift uden forfatter bliver', () {
      expect(
          withoutModerated(recipes,
              reportedIds: {'b'}, blockedAuthorIds: {'eva'}).map((r) => r.id),
          ['d']);
    });
  });

  group('providere', () {
    ProviderContainer container() => ProviderContainer(overrides: [
          moderationServiceProvider.overrideWithValue(service),
        ]);

    test('rapporterede ID\'er og blokerede forfattere følger databasen',
        () async {
      final c = container();
      addTearDown(c.dispose);
      final reported = c.listen(reportedRecipeIdsProvider, (_, __) {});
      final blocked = c.listen(blockedAuthorIdsProvider, (_, __) {});
      c.listen(blockedAuthorsProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(reported.read().valueOrNull ?? <String>{}, isEmpty);

      await service.reportRecipe(
          recipeId: 'r9', reason: ReportReason.offensive);
      await service.blockAuthor(authorUid: 'eva', name: 'Eva');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reported.read().value, {'r9'});
      expect(blocked.read(), {'eva'});

      await service.unblockAuthor('eva');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(blocked.read(), isEmpty);
    });
  });

  group('fjernet opskrift', () {
    test('visibility "hidden" læses som fjernet, og er ikke delt', () {
      expect(RecipeVisibility.parse('hidden'), RecipeVisibility.hidden);
      final r = Recipe(
          id: 'x',
          title: 't',
          calories: 0,
          time: '',
          category: RecipeCategory.aftensmad,
          visibility: RecipeVisibility.hidden);
      expect(r.isHidden, isTrue);
      expect(r.isShared, isFalse);
      expect(RecipeVisibility.hidden.key, 'hidden');
    });
  });
}
