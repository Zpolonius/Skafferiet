// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}
class MockFirebaseAuth extends Mock implements FirebaseAuth {}
class MockUser extends Mock implements User {}
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
}

class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  bool get exists => false;
}

class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockWriteBatch extends Mock implements WriteBatch {}
class FakeDocumentReference extends Fake implements DocumentReference<Map<String, dynamic>> {}

/// Snapshot med valgfri data — null betyder at dokumentet ikke findes.
class DataSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {
  DataSnapshot(this._data);
  final Map<String, dynamic>? _data;
  @override
  bool get exists => _data != null;
  @override
  Map<String, dynamic>? data() => _data;
}

void main() {
  group('HouseholdNotifier Tests', () {
    late MockFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockCollectionReference mockInvitesCollection;
    late MockCollectionReference mockUsersCollection;
    late MockCollectionReference mockHouseholdsCollection;

    setUp(() {
      mockFirestore = MockFirestore();
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockInvitesCollection = MockCollectionReference();
      mockUsersCollection = MockCollectionReference();
      mockHouseholdsCollection = MockCollectionReference();

      registerFallbackValue(SetOptions(merge: true));

      when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('test-uid');
      when(() => mockUser.email).thenReturn('test@example.com');
      when(() => mockUser.displayName).thenReturn('Test User');

      when(() => mockFirestore.collection('invitations')).thenReturn(mockInvitesCollection);
      when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(() => mockFirestore.collection('households')).thenReturn(mockHouseholdsCollection);
      
      final mockUserDocRef = MockDocumentReference();
      when(() => mockUsersCollection.doc(any())).thenReturn(mockUserDocRef);
      when(() => mockUserDocRef.snapshots()).thenAnswer((_) => Stream.value(MockDocumentSnapshot()));
      when(() => mockUserDocRef.set(any(), any())).thenAnswer((_) async => {});
      
      final mockQuery = MockQuery();
      when(() => mockInvitesCollection.where('toUserEmail', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.where('status', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.snapshots()).thenAnswer((_) => Stream.value(MockQuerySnapshot()));
    });

    test('Initial state reflects loading and then listeners setup', () async {
      final container = ProviderContainer(
        overrides: [
          householdProvider.overrideWith((ref) => HouseholdNotifier(
            firestore: mockFirestore,
            auth: mockAuth,
          )),
        ],
      );

      expect(container.read(householdProvider).isLoading, true);
      
      await Future.delayed(Duration.zero);
      
      verify(() => mockAuth.authStateChanges()).called(1);
    });

    test('household ID is SK- plus a secure random code', () async {
      final container = ProviderContainer(
        overrides: [
          householdProvider.overrideWith((ref) => HouseholdNotifier(
            firestore: mockFirestore,
            auth: mockAuth,
          )),
        ],
      );

      final notifier = container.read(householdProvider.notifier);
      
      final mockDocRef = MockDocumentReference();
      when(() => mockHouseholdsCollection.doc(any(that: startsWith('SK-')))).thenReturn(mockDocRef);
      when(() => mockDocRef.set(any())).thenAnswer((_) async => {});
      
      await notifier.createHousehold('Test Home');
      
      final captured = verify(() => mockHouseholdsCollection.doc(captureAny())).captured;
      final code = captured.first as String;
      expect(code, matches(RegExp(r'^SK-[A-HJ-NP-Z2-9]{10}$')));
    });
  });

  group('HouseholdState.adminUid', () {
    test('defaults to null', () {
      expect(HouseholdState().adminUid, isNull);
    });

    test('copyWith preserves adminUid', () {
      final s = HouseholdState(adminUid: 'owner-uid', householdId: 'hh-1');
      expect(s.copyWith(householdName: 'Nyt Navn').adminUid, 'owner-uid');
    });

    test('copyWith can update adminUid', () {
      final s = HouseholdState(adminUid: 'old-uid');
      expect(s.copyWith(adminUid: 'new-uid').adminUid, 'new-uid');
    });
  });

  group('renameHousehold', () {
    late MockFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockCollectionReference mockUsersCollection;
    late MockCollectionReference mockHouseholdsCollection;
    late MockCollectionReference mockInvitesCollection;

    setUp(() {
      mockFirestore = MockFirestore();
      mockAuth = MockFirebaseAuth();
      mockUsersCollection = MockCollectionReference();
      mockHouseholdsCollection = MockCollectionReference();
      mockInvitesCollection = MockCollectionReference();

      registerFallbackValue(SetOptions(merge: true));

      // Use Stream.empty() so _init() never fires and state stays pristine
      when(() => mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
      when(() => mockAuth.currentUser).thenReturn(null);

      when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(() => mockFirestore.collection('households')).thenReturn(mockHouseholdsCollection);
      when(() => mockFirestore.collection('invitations')).thenReturn(mockInvitesCollection);
    });

    ProviderContainer makeContainer() => ProviderContainer(
      overrides: [
        householdProvider.overrideWith((ref) => HouseholdNotifier(
          firestore: mockFirestore,
          auth: mockAuth,
        )),
      ],
    );

    test('calls Firestore update with new name', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(householdProvider.notifier);
      // ignore: invalid_use_of_protected_member
      notifier.state = HouseholdState(householdId: 'SK-123456', isLoading: false);

      final mockDocRef = MockDocumentReference();
      when(() => mockHouseholdsCollection.doc('SK-123456')).thenReturn(mockDocRef);
      when(() => mockDocRef.update(any())).thenAnswer((_) async {});

      await notifier.renameHousehold('Nyt Navn');

      verify(() => mockDocRef.update({'name': 'Nyt Navn'})).called(1);
    });

    test('sets error state when Firestore throws', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(householdProvider.notifier);
      // ignore: invalid_use_of_protected_member
      notifier.state = HouseholdState(householdId: 'SK-123456', isLoading: false);

      final mockDocRef = MockDocumentReference();
      when(() => mockHouseholdsCollection.doc('SK-123456')).thenReturn(mockDocRef);
      when(() => mockDocRef.update(any())).thenThrow(Exception('Netværksfejl'));

      await notifier.renameHousehold('Nyt Navn');

      expect(container.read(householdProvider).error, 'Kunne ikke omdøbe husstanden');
    });

    test('does nothing when householdId is null', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(householdProvider.notifier);
      // ignore: invalid_use_of_protected_member
      notifier.state = HouseholdState(householdId: null, isLoading: false);

      await notifier.renameHousehold('Nyt Navn');

      verifyNever(() => mockHouseholdsCollection.doc(any()));
    });
  });

  group('invitationskoder', () {
    test('generateSecureCode matcher formatet i firestore.rules', () {
      for (var i = 0; i < 200; i++) {
        expect(generateSecureCode(joinCodeLength), matches(RegExp(r'^[A-HJ-NP-Z2-9]{10}$')));
      }
    });

    test('normalizeJoinCode tåler små bogstaver, bindestreg og mellemrum', () {
      expect(normalizeJoinCode(' abcde-fghjk '), 'ABCDEFGHJK');
    });

    test('formatJoinCode deler koden i to', () {
      expect(formatJoinCode('ABCDEFGHJK'), 'ABCDE-FGHJK');
      expect(formatJoinCode('KORT'), 'KORT');
    });
  });

  group('skift og forlad husstand', () {
    late MockFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockCollectionReference users;
    late MockCollectionReference households;
    late MockCollectionReference invitations;
    late MockCollectionReference joinCodes;
    late MockWriteBatch batch;
    final docs = <String, MockDocumentReference>{};

    MockDocumentReference docRef(MockCollectionReference col, String name, String id) {
      return docs.putIfAbsent('$name/$id', () {
        final ref = MockDocumentReference();
        when(() => col.doc(id)).thenReturn(ref);
        when(() => ref.id).thenReturn(id);
        return ref;
      });
    }

    setUpAll(() {
      registerFallbackValue(FakeDocumentReference());
      registerFallbackValue(SetOptions(merge: true));
    });

    setUp(() {
      docs.clear();
      mockFirestore = MockFirestore();
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      users = MockCollectionReference();
      households = MockCollectionReference();
      invitations = MockCollectionReference();
      joinCodes = MockCollectionReference();
      batch = MockWriteBatch();

      when(() => mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('me');
      when(() => mockUser.email).thenReturn('me@example.com');

      when(() => mockFirestore.collection('users')).thenReturn(users);
      when(() => mockFirestore.collection('households')).thenReturn(households);
      when(() => mockFirestore.collection('invitations')).thenReturn(invitations);
      when(() => mockFirestore.collection('join_codes')).thenReturn(joinCodes);
      when(() => mockFirestore.batch()).thenReturn(batch);
      when(() => batch.commit()).thenAnswer((_) async {});
    });

    HouseholdNotifier makeNotifier(HouseholdState initial) {
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);
      // ignore: invalid_use_of_protected_member
      notifier.state = initial;
      return notifier;
    }

    final inOldHousehold = HouseholdState(
      householdId: 'SK-OLD',
      adminUid: 'me',
      members: const ['me', 'partner'],
      isLoading: false,
    );

    test('ugyldig kode giver fejl og skriver intet', () async {
      final codeRef = docRef(joinCodes, 'join_codes', 'QQQQQQQQQQ');
      when(() => codeRef.get()).thenAnswer((_) async => DataSnapshot(null));
      final notifier = makeNotifier(inOldHousehold);

      await notifier.joinHousehold('qqqqq-qqqqq');

      expect(notifier.state.error, 'Koden er ugyldig eller udløbet');
      expect(notifier.state.isLoading, false);
      verifyNever(() => batch.commit());
    });

    test('for kort kode slås ikke engang op', () async {
      final notifier = makeNotifier(inOldHousehold);

      await notifier.joinHousehold('SK-123456');

      expect(notifier.state.error, 'Koden er ugyldig eller udløbet');
      verifyNever(() => joinCodes.doc(any()));
    });

    test('udløbet kode afvises', () async {
      final codeRef = docRef(joinCodes, 'join_codes', 'ABCDEFGHJK');
      when(() => codeRef.get()).thenAnswer((_) async => DataSnapshot({
            'householdId': 'SK-NEW',
            'expiresAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))),
          }));
      final notifier = makeNotifier(inOldHousehold);

      await notifier.joinHousehold('ABCDE-FGHJK');

      expect(notifier.state.error, 'Koden er ugyldig eller udløbet');
      verifyNever(() => batch.commit());
    });

    test('gyldig kode: forlader gammel husstand, giver ejerskab videre og melder sig ind i ét batch', () async {
      final codeRef = docRef(joinCodes, 'join_codes', 'ABCDEFGHJK');
      when(() => codeRef.get()).thenAnswer((_) async => DataSnapshot({
            'householdId': 'SK-NEW',
            'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
          }));
      final oldRef = docRef(households, 'households', 'SK-OLD');
      final newRef = docRef(households, 'households', 'SK-NEW');
      final userRef = docRef(users, 'users', 'me');
      final notifier = makeNotifier(inOldHousehold);

      await notifier.joinHousehold('abcde-fghjk');

      final oldUpdate = verify(() => batch.update(oldRef, captureAny())).captured.single as Map;
      expect(oldUpdate['members'], isA<FieldValue>());
      expect(oldUpdate['admin'], 'partner');

      final newUpdate = verify(() => batch.update(newRef, captureAny())).captured.single as Map;
      expect(newUpdate['members'], isA<FieldValue>());
      expect(newUpdate['joinedWith'], {'type': 'code', 'id': 'ABCDEFGHJK'});

      verify(() => batch.set(userRef, {'householdId': 'SK-NEW'}, any())).called(1);
      verify(() => batch.commit()).called(1);
      expect(notifier.state.error, isNull);
    });

    test('accept af invitation sker i samme batch som indmeldelsen', () async {
      final inviteRef = docRef(invitations, 'invitations', 'inv1');
      when(() => inviteRef.get()).thenAnswer((_) async => DataSnapshot({
            'fromHouseholdId': 'SK-NEW',
            'toUserEmail': 'me@example.com',
            'status': 'pending',
          }));
      final newRef = docRef(households, 'households', 'SK-NEW');
      docRef(households, 'households', 'SK-OLD');
      docRef(users, 'users', 'me');
      final notifier = makeNotifier(inOldHousehold);

      await notifier.acceptInvitation('inv1');

      final newUpdate = verify(() => batch.update(newRef, captureAny())).captured.single as Map;
      expect(newUpdate['joinedWith'], {'type': 'invite', 'id': 'inv1'});
      verify(() => batch.update(inviteRef, {'status': 'accepted'})).called(1);
      verify(() => batch.commit()).called(1);
      verifyNever(() => inviteRef.update(any()));
    });

    test('invitation til en anden e-mail afvises', () async {
      final inviteRef = docRef(invitations, 'invitations', 'inv1');
      when(() => inviteRef.get()).thenAnswer((_) async => DataSnapshot({
            'fromHouseholdId': 'SK-NEW',
            'toUserEmail': 'someone-else@example.com',
            'status': 'pending',
          }));
      final notifier = makeNotifier(inOldHousehold);

      await notifier.acceptInvitation('inv1');

      expect(notifier.state.error, 'Kunne ikke acceptere invitation');
      verifyNever(() => batch.commit());
    });

    test('slettet invitation stopper loading og viser fejl', () async {
      final inviteRef = docRef(invitations, 'invitations', 'gone');
      when(() => inviteRef.get()).thenAnswer((_) async => DataSnapshot(null));
      final notifier = makeNotifier(inOldHousehold);

      await notifier.acceptInvitation('gone');

      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, 'Invitationen findes ikke længere');
    });

    test('forlad husstand som eneste medlem: intet ejerskab at give videre', () async {
      final oldRef = docRef(households, 'households', 'SK-OLD');
      final userRef = docRef(users, 'users', 'me');
      final notifier = makeNotifier(HouseholdState(
        householdId: 'SK-OLD',
        adminUid: 'me',
        members: const ['me'],
        isLoading: false,
      ));

      await notifier.leaveHousehold();

      final update = verify(() => batch.update(oldRef, captureAny())).captured.single as Map;
      expect(update.containsKey('admin'), false);
      verify(() => batch.update(userRef, any())).called(1);
      verify(() => batch.commit()).called(1);
      expect(notifier.state.householdId, isNull);
    });

    test('createJoinCode gemmer en kode der udløber om 7 dage', () async {
      final codeRef = MockDocumentReference();
      when(() => joinCodes.doc(any())).thenReturn(codeRef);
      when(() => codeRef.set(any())).thenAnswer((_) async {});
      final notifier = makeNotifier(inOldHousehold);

      final code = await notifier.createJoinCode();

      expect(code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{10}$')));
      verify(() => joinCodes.doc(code)).called(1);
      final data = verify(() => codeRef.set(captureAny())).captured.single as Map;
      expect(data['householdId'], 'SK-OLD');
      expect(data['createdBy'], 'me');
      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
      expect(expiresAt.difference(DateTime.now()).inHours, closeTo(7 * 24, 1));
    });

    test('createJoinCode returnerer null og viser fejl hvis skrivningen fejler', () async {
      final codeRef = MockDocumentReference();
      when(() => joinCodes.doc(any())).thenReturn(codeRef);
      when(() => codeRef.set(any())).thenThrow(Exception('offline'));
      final notifier = makeNotifier(inOldHousehold);

      expect(await notifier.createJoinCode(), isNull);
      expect(notifier.state.error, 'Kunne ikke lave en invitationskode');
    });
  });

  group('log ud', () {
    test('lukker den forrige brugers Firestore-lyttere', () async {
      final mockFirestore = MockFirestore();
      final mockAuth = MockFirebaseAuth();
      final mockUser = MockUser();
      final users = MockCollectionReference();
      final households = MockCollectionReference();
      final invitations = MockCollectionReference();
      final userRef = MockDocumentReference();
      final householdRef = MockDocumentReference();
      final query = MockQuery();

      final authEvents = StreamController<User?>();
      var userStreamCancelled = false;
      var householdStreamCancelled = false;
      var invitationStreamCancelled = false;
      final userStream = StreamController<DocumentSnapshot<Map<String, dynamic>>>(
          onCancel: () => userStreamCancelled = true);
      final householdStream = StreamController<DocumentSnapshot<Map<String, dynamic>>>(
          onCancel: () => householdStreamCancelled = true);
      final invitationStream = StreamController<QuerySnapshot<Map<String, dynamic>>>(
          onCancel: () => invitationStreamCancelled = true);

      when(() => mockAuth.authStateChanges()).thenAnswer((_) => authEvents.stream);
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('me');
      when(() => mockUser.email).thenReturn('me@example.com');
      when(() => mockFirestore.collection('users')).thenReturn(users);
      when(() => mockFirestore.collection('households')).thenReturn(households);
      when(() => mockFirestore.collection('invitations')).thenReturn(invitations);
      when(() => users.doc('me')).thenReturn(userRef);
      when(() => userRef.snapshots()).thenAnswer((_) => userStream.stream);
      when(() => households.doc('SK-A')).thenReturn(householdRef);
      when(() => householdRef.snapshots()).thenAnswer((_) => householdStream.stream);
      when(() => invitations.where('toUserEmail', isEqualTo: any(named: 'isEqualTo'))).thenReturn(query);
      when(() => query.where('status', isEqualTo: any(named: 'isEqualTo'))).thenReturn(query);
      when(() => query.snapshots()).thenAnswer((_) => invitationStream.stream);

      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);
      authEvents.add(mockUser);
      await Future<void>.delayed(Duration.zero);
      userStream.add(DataSnapshot({'householdId': 'SK-A'}));
      await Future<void>.delayed(Duration.zero);
      verify(() => householdRef.snapshots()).called(1);

      authEvents.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(userStreamCancelled, true);
      expect(householdStreamCancelled, true);
      expect(invitationStreamCancelled, true);
      expect(notifier.state.householdId, isNull);

      notifier.dispose();
      await authEvents.close();
    });

    test('profilændring i samme husstand starter ikke en ny lytter', () async {
      final mockFirestore = MockFirestore();
      final mockAuth = MockFirebaseAuth();
      final mockUser = MockUser();
      final users = MockCollectionReference();
      final households = MockCollectionReference();
      final userRef = MockDocumentReference();
      final householdRef = MockDocumentReference();
      final userStream = StreamController<DocumentSnapshot<Map<String, dynamic>>>();

      when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('me');
      when(() => mockUser.email).thenReturn(null);
      when(() => mockFirestore.collection('users')).thenReturn(users);
      when(() => mockFirestore.collection('households')).thenReturn(households);
      when(() => users.doc('me')).thenReturn(userRef);
      when(() => userRef.snapshots()).thenAnswer((_) => userStream.stream);
      when(() => households.doc('SK-A')).thenReturn(householdRef);
      when(() => householdRef.snapshots()).thenAnswer((_) => const Stream.empty());

      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);
      await Future<void>.delayed(Duration.zero);
      userStream.add(DataSnapshot({'householdId': 'SK-A'}));
      await Future<void>.delayed(Duration.zero);
      userStream.add(DataSnapshot({'householdId': 'SK-A', 'photoURL': 'https://x/y.jpg'}));
      await Future<void>.delayed(Duration.zero);

      verify(() => householdRef.snapshots()).called(1);

      notifier.dispose();
      await userStream.close();
    });
  });

  group('mine måltider', () {
    late MockFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockDocumentReference userRef;
    late MockDocumentReference householdRef;
    late StreamController<DocumentSnapshot<Map<String, dynamic>>> userStream;
    late StreamController<DocumentSnapshot<Map<String, dynamic>>> householdStream;

    setUp(() {
      mockFirestore = MockFirestore();
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      userRef = MockDocumentReference();
      householdRef = MockDocumentReference();
      userStream = StreamController();
      householdStream = StreamController();
      final users = MockCollectionReference();
      final households = MockCollectionReference();
      registerFallbackValue(SetOptions(merge: true));

      when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('me');
      when(() => mockUser.email).thenReturn(null);
      when(() => mockFirestore.collection('users')).thenReturn(users);
      when(() => mockFirestore.collection('households')).thenReturn(households);
      when(() => users.doc('me')).thenReturn(userRef);
      when(() => userRef.snapshots()).thenAnswer((_) => userStream.stream);
      when(() => households.doc('SK-A')).thenReturn(householdRef);
      when(() => householdRef.snapshots()).thenAnswer((_) => householdStream.stream);
    });

    // Ikke await: close() venter på en lytter, og nogle tests lytter aldrig.
    tearDown(() {
      userStream.close();
      householdStream.close();
    });

    test('læses fra brugerprofilen og overlever husstandens snapshot', () async {
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);
      await Future<void>.delayed(Duration.zero);
      userStream.add(DataSnapshot({'householdId': 'SK-A', 'mealTypes': ['dinner', 'breakfast']}));
      await Future<void>.delayed(Duration.zero);
      householdStream.add(DataSnapshot({'name': 'Hjem', 'members': <String>[]}));
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.householdId, 'SK-A');
      expect(notifier.state.mealTypes, [MealType.breakfast, MealType.dinner]);

      // Ændres valget på profilen, følger state med uden ny husstandslytter.
      userStream.add(DataSnapshot({'householdId': 'SK-A', 'mealTypes': ['snack']}));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.mealTypes, [MealType.snack]);
      verify(() => householdRef.snapshots()).called(1);

      notifier.dispose();
    });

    test('uden felt på profilen vises alle måltider', () async {
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);
      await Future<void>.delayed(Duration.zero);
      userStream.add(DataSnapshot({'householdId': 'SK-A'}));
      await Future<void>.delayed(Duration.zero);
      householdStream.add(DataSnapshot({'name': 'Hjem', 'members': <String>[]}));
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.mealTypes, MealType.values);
      notifier.dispose();
    });

    test('setMealTypes gemmer nøglerne i fast rækkefølge på profilen', () async {
      when(() => userRef.set(any(), any())).thenAnswer((_) async {});
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);

      await notifier.setMealTypes({MealType.snack, MealType.breakfast});

      final written = verify(() => userRef.set(captureAny(), any())).captured.single;
      expect(written, {'mealTypes': ['breakfast', 'snack']});
      expect(notifier.state.mealTypes, [MealType.breakfast, MealType.snack]);
      notifier.dispose();
    });

    test('setMealTypes ignorerer et tomt valg', () async {
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);
      await notifier.setMealTypes({});
      verifyNever(() => userRef.set(any(), any()));
      expect(notifier.state.mealTypes, MealType.values);
      notifier.dispose();
    });

    test('setMealTypes ruller tilbage og viser fejl hvis skrivningen fejler', () async {
      when(() => userRef.set(any(), any())).thenThrow(Exception('offline'));
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);

      await notifier.setMealTypes({MealType.dinner});

      expect(notifier.state.mealTypes, MealType.values);
      expect(notifier.state.error, 'Kunne ikke gemme dine måltider');
      notifier.dispose();
    });
  });

  test('HouseholdState.copyWith bevarer mealTypes', () {
    final state = HouseholdState(mealTypes: [MealType.dinner]);
    expect(state.copyWith(householdId: 'x').mealTypes, [MealType.dinner]);
  });
}
