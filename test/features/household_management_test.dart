// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart' as auth_mocks;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/profile/invitation_service.dart';

// Testene kører mod en falsk Firestore i hukommelsen og kontrollerer, hvad
// der faktisk ender i databasen. Sikkerhedsreglerne for de samme skrivninger
// testes i rules_test/ (afsnittet "husstand & deling").

/// Venter til [condition] er sand — lyttere i den falske database svarer
/// asynkront.
Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), true, reason: 'tilstanden blev aldrig nået');
}

void main() {
  late FakeFirebaseFirestore db;
  late HouseholdNotifier notifier;

  Future<Map<String, dynamic>?> read(String path) async => (await db.doc(path).get()).data();

  Future<HouseholdNotifier> start({
    String uid = 'me',
    List<String> members = const ['me', 'partner'],
    String admin = 'me',
  }) async {
    await db.doc('users/me').set({
      'displayName': 'Mig',
      'email': 'me@example.com',
      'householdId': 'HH',
      'hasCompletedOnboarding': true,
    });
    await db.doc('users/partner').set({'displayName': 'Partner', 'householdId': 'HH'});
    await db.doc('households/HH').set({
      'name': 'Familien',
      'members': members,
      'admin': admin,
      'adultsCount': 2,
      'childrenCount': 2,
      'preferences': <String>[],
    });
    final auth = auth_mocks.MockFirebaseAuth(
      signedIn: true,
      mockUser: auth_mocks.MockUser(uid: uid, email: '$uid@example.com', displayName: 'Mig'),
    );
    final n = HouseholdNotifier(firestore: db, auth: auth);
    await eventually(() => n.state.householdId == 'HH' && n.state.memberNames.isNotEmpty);
    return n;
  }

  setUp(() => db = FakeFirebaseFirestore());
  tearDown(() => notifier.dispose());

  group('forlad husstand', () {
    test('melder sig ud, giver ejerskabet videre og får en ny husstand', () async {
      notifier = await start();

      expect(await notifier.leaveHousehold(), isNull);

      final old = (await read('households/HH'))!;
      expect(old['members'], ['partner']);
      expect(old['admin'], 'partner');

      final newId = (await read('users/me'))!['householdId'] as String;
      expect(newId, startsWith('SK-'));
      final fresh = (await read('households/$newId'))!;
      expect(fresh['members'], ['me']);
      expect(fresh['admin'], 'me');

      // Appen følger den nye husstand — og sender ikke brugeren i onboarding.
      await eventually(() => notifier.state.householdId == newId);
      expect(notifier.state.hasCompletedOnboarding, true);
      expect(notifier.state.members, ['me']);
    });

    test('eneste medlem kan ikke forlade — intet skrives', () async {
      notifier = await start(members: ['me']);

      expect(await notifier.leaveHousehold(), contains('eneste medlem'));
      expect((await read('households/HH'))!['members'], ['me']);
      expect((await read('users/me'))!['householdId'], 'HH');
    });
  });

  group('fjern medlem', () {
    setUp(() async {
      for (final code in ['AAAAAAAAAA', 'BBBBBBBBBB']) {
        await db.doc('join_codes/$code').set({'householdId': 'HH', 'createdBy': 'partner'});
      }
      await db.doc('join_codes/CCCCCCCCCC').set({'householdId': 'ANDET', 'createdBy': 'x'});
    });

    test('ejeren fjerner et medlem, og husstandens koder slettes', () async {
      notifier = await start();

      expect(await notifier.removeMember('partner'), isNull);

      expect((await read('households/HH'))!['members'], ['me']);
      expect(await read('join_codes/AAAAAAAAAA'), isNull);
      expect(await read('join_codes/BBBBBBBBBB'), isNull);
      // Andre husstandes koder røres ikke.
      expect(await read('join_codes/CCCCCCCCCC'), isNotNull);
    });

    test('et almindeligt medlem kan ikke fjerne nogen', () async {
      notifier = await start(admin: 'partner');

      expect(await notifier.removeMember('partner'), 'Kun ejeren kan fjerne medlemmer.');
      expect((await read('households/HH'))!['members'], ['me', 'partner']);
      expect(await read('join_codes/AAAAAAAAAA'), isNotNull);
    });

    test('ejeren kan ikke fjerne sig selv eller en fremmed', () async {
      notifier = await start();

      expect(await notifier.removeMember('me'), isNotNull);
      expect(await notifier.removeMember('stranger'), isNotNull);
      expect((await read('households/HH'))!['members'], ['me', 'partner']);
    });
  });

  group('invitationer (InvitationService)', () {
    late InvitationService invitations;

    setUp(() async {
      notifier = await start();
      invitations = InvitationService(
        firestore: db,
        auth: auth_mocks.MockFirebaseAuth(
          signedIn: true,
          mockUser: auth_mocks.MockUser(uid: 'me', email: 'me@example.com', displayName: 'Mig'),
        ),
      );
    });

    Future<String?> send(String email) =>
        invitations.send(householdId: 'HH', householdName: 'Familien', email: email);

    test('gemmes med lille e-mail og afsender', () async {
      expect(await send(' Ven@Example.COM '), isNull);

      final data = (await db.collection('invitations').get()).docs.single.data();
      expect(data['toUserEmail'], 'ven@example.com');
      expect(data['fromHouseholdId'], 'HH');
      expect(data['fromHouseholdName'], 'Familien');
      expect(data['fromUid'], 'me');
      expect(data['status'], 'pending');
    });

    test('samme e-mail kan ikke inviteres to gange', () async {
      await send('ven@example.com');

      expect(await send('VEN@example.com'), 'ven@example.com er allerede inviteret.');
      expect((await db.collection('invitations').get()).docs, hasLength(1));
    });

    test('man kan ikke invitere sig selv', () async {
      expect(await send('ME@example.com'), 'Du kan ikke invitere dig selv.');
      expect((await db.collection('invitations').get()).docs, isEmpty);
    });

    test('ventende invitationer kan ses og annulleres', () async {
      await send('a@example.com');
      await db.collection('invitations').add({
        'fromHouseholdId': 'HH',
        'toUserEmail': 'svaret@example.com',
        'status': 'declined',
      });
      await db.collection('invitations').add({
        'fromHouseholdId': 'ANDET',
        'toUserEmail': 'b@example.com',
        'status': 'pending',
      });

      final pending = await invitations.watchPending('HH').first;
      expect(pending.map((i) => i.email), ['a@example.com']);

      expect(await invitations.cancel(pending.single.id), isNull);
      expect(await invitations.watchPending('HH').first, isEmpty);
    });
  });

  test('præferencer gemmes på husstanden', () async {
    notifier = await start();

    expect(
      await notifier
          .updatePreferences(adultsCount: 1, childrenCount: 3, preferences: ['Budgetvenligt']),
      isNull,
    );

    final data = (await read('households/HH'))!;
    expect(data['adultsCount'], 1);
    expect(data['childrenCount'], 3);
    expect(data['preferences'], ['Budgetvenligt']);
  });

  test('nyt navn vises med det samme i medlemslisten', () async {
    notifier = await start();
    expect(notifier.state.memberNames['me'], 'Mig');

    await db.doc('users/me').update({'displayName': 'Nyt Navn', 'photoURL': 'https://x/y.jpg'});

    await eventually(() => notifier.state.memberNames['me'] == 'Nyt Navn');
    expect(notifier.state.memberPhotos['me'], 'https://x/y.jpg');
    expect(notifier.state.memberNames['partner'], 'Partner');
  });

  group('fjernet fra husstanden', () {
    // Den falske database kender ikke sikkerhedsreglerne, så "ingen adgang"
    // simuleres med en stream, der fejler som Firestore gør.
    late _MockFirestore firestore;
    late _MockWriteBatch batch;
    late StreamController<DocumentSnapshot<Map<String, dynamic>>> userStream;
    late StreamController<DocumentSnapshot<Map<String, dynamic>>> householdStream;
    late _MockDocRef userRef;
    late _MockDocRef oldRef;
    late _MockDocRef newRef;
    late _MockCollection households;

    setUpAll(() {
      registerFallbackValue(_FakeDocRef());
      registerFallbackValue(SetOptions(merge: true));
    });

    setUp(() {
      firestore = _MockFirestore();
      batch = _MockWriteBatch();
      userStream = StreamController.broadcast();
      householdStream = StreamController.broadcast();
      final users = _MockCollection();
      households = _MockCollection();
      final invitations = _MockCollection();
      final query = _MockQuery();
      userRef = _MockDocRef();
      oldRef = _MockDocRef();
      newRef = _MockDocRef();

      when(() => firestore.collection('users')).thenReturn(users);
      when(() => firestore.collection('households')).thenReturn(households);
      when(() => firestore.collection('invitations')).thenReturn(invitations);
      when(() => firestore.batch()).thenReturn(batch);
      when(() => users.doc('me')).thenReturn(userRef);
      when(() => userRef.snapshots()).thenAnswer((_) => userStream.stream);
      when(() => households.doc('HH')).thenReturn(oldRef);
      when(() => oldRef.snapshots()).thenAnswer((_) => householdStream.stream);
      when(() => households.doc(any(that: startsWith('SK-')))).thenReturn(newRef);
      when(() => newRef.snapshots()).thenAnswer((_) => const Stream.empty());
      when(() => invitations.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(query);
      when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(query);
      when(() => query.snapshots()).thenAnswer((_) => const Stream.empty());
    });

    Future<HouseholdNotifier> startMocked() async {
      final user = auth_mocks.MockUser(uid: 'me', email: 'me@example.com', displayName: 'Mig');
      final n = HouseholdNotifier(
        firestore: firestore,
        auth: auth_mocks.MockFirebaseAuth(signedIn: true, mockUser: user),
      );
      await eventually(() => userStream.hasListener);
      userStream.add(_Snap({'householdId': 'HH', 'hasCompletedOnboarding': true}));
      await eventually(() => householdStream.hasListener);
      householdStream.add(_Snap({
        'name': 'Familien',
        'members': ['me']
      }));
      await eventually(() => n.state.householdName == 'Familien');
      return n;
    }

    final denied = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

    test('får en ny husstand og en forklaring', () async {
      when(() => batch.commit()).thenAnswer((_) async {});
      notifier = await startMocked();

      householdStream.addError(denied);
      await eventually(() => notifier.state.notice != null);

      expect(notifier.state.notice, contains('Du er ikke længere medlem af "Familien"'));
      final created = verify(() => batch.set<Map<String, dynamic>>(newRef, captureAny()))
          .captured
          .single as Map;
      expect(created['members'], ['me']);
      expect(created['admin'], 'me');
      verify(() => batch.set<Map<String, dynamic>>(
          userRef, any(that: containsPair('householdId', startsWith('SK-'))), any())).called(1);
      // Den gamle husstand forsøges ikke ændret — vi har ikke adgang.
      verifyNever(() => batch.update(oldRef, any()));
      // Og vi lytter nu på den nye.
      verify(() => newRef.snapshots()).called(1);

      notifier.clearNotice();
      expect(notifier.state.notice, isNull);
    });

    test('fejler det, prøves der ikke igen og igen', () async {
      when(() => batch.commit()).thenThrow(denied);
      notifier = await startMocked();

      householdStream.addError(denied);
      await eventually(() => notifier.state.error != null);
      // Efter fejlen lytter appen på den gamle husstand igen og får "ingen
      // adgang" igen — det må ikke starte et nyt forsøg.
      householdStream.addError(denied);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      verify(() => batch.commit()).called(1);
      expect(notifier.state.error, 'Du er ikke længere medlem af husstanden');
      expect(notifier.state.isLoading, false);
    });
  });
}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockWriteBatch extends Mock implements WriteBatch {}

class _MockCollection extends Mock implements CollectionReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockDocRef extends Mock implements DocumentReference<Map<String, dynamic>> {}

class _FakeDocRef extends Fake implements DocumentReference<Map<String, dynamic>> {}

class _Snap extends Mock implements DocumentSnapshot<Map<String, dynamic>> {
  _Snap(this._data);
  final Map<String, dynamic>? _data;
  @override
  bool get exists => _data != null;
  @override
  Map<String, dynamic>? data() => _data;
}
