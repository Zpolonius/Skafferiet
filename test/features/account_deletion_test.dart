import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/features/profile/account_deletion_service.dart';

/// Bruger der husker, om kontoen blev slettet, og kan simulere fejl.
/// (Sikkerhedsreglerne for de samme trin testes i rules_test/.)
// MockUser har selv felter der kan ændres, så advarslen kan ikke undgås.
// ignore: must_be_immutable
class _TestUser extends MockUser {
  _TestUser() : super(uid: 'me', email: 'me@example.com', displayName: 'Mig');

  bool deleted = false;
  String? reauthErrorCode;
  String? deleteErrorCode;

  @override
  Future<UserCredential> reauthenticateWithCredential(AuthCredential? credential) {
    if (reauthErrorCode != null) {
      throw FirebaseAuthException(code: reauthErrorCode!);
    }
    return super.reauthenticateWithCredential(credential);
  }

  @override
  Future<void> delete() async {
    if (deleteErrorCode != null) {
      throw FirebaseAuthException(code: deleteErrorCode!);
    }
    deleted = true;
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseStorage storage;
  late _TestUser user;
  late AccountDeletionService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    user = _TestUser();
    service = AccountDeletionService(
      auth: MockFirebaseAuth(mockUser: user, signedIn: true),
      firestore: db,
      storage: storage,
    );
  });

  Future<bool> exists(String path) async => (await db.doc(path).get()).exists;

  Future<void> seedProfile({String? householdId}) async {
    await db.doc('users/me').set({
      'displayName': 'Mig',
      'email': 'me@example.com',
      if (householdId != null) 'householdId': householdId,
    });
    await storage.ref('users/me/avatar.jpg').putString('billede');
    await db.collection('invitations').doc('toMe').set({
      'fromHouseholdId': 'HH_OTHER', 'toUserEmail': 'me@example.com', 'status': 'declined',
    });
    await db.collection('invitations').doc('toSomeoneElse').set({
      'fromHouseholdId': 'HH_OTHER', 'toUserEmail': 'else@example.com', 'status': 'pending',
    });
  }

  group('eneste medlem og ejer', () {
    setUp(() async {
      await seedProfile(householdId: 'HH');
      await db.doc('households/HH').set({'name': 'Mit', 'members': ['me'], 'admin': 'me'});
      await db.doc('households/HH/grocery_list/g1').set({'name': 'Mælk'});
      await db.doc('households/HH/meal_plans/w1').set({'days': {}});
      await db.doc('recipes/mine').set({'householdId': 'HH', 'createdBy': 'me'});
      await db.doc('recipes/byFormerMember').set({'householdId': 'HH', 'createdBy': 'zed'});
      await db.doc('recipes/otherHousehold').set({'householdId': 'HH_OTHER', 'createdBy': 'x'});
      await db.doc('invitations/fromMyHousehold').set({
        'fromHouseholdId': 'HH', 'fromUid': 'me', 'toUserEmail': 'y@example.com', 'status': 'pending',
      });
      await storage.ref('households/HH/recipes/r.jpg').putString('billede');
      await db.doc('join_codes/AAAAAAAAAA').set({'householdId': 'HH', 'createdBy': 'me'});
      await db.doc('join_codes/OTHERHHHHH').set({'householdId': 'HH_OTHER', 'createdBy': 'x'});
    });

    test('sletter hele husstanden, profilen og login-kontoen', () async {
      await service.deleteAccount(password: 'hemmelig');

      expect(await exists('households/HH'), false);
      expect(await exists('households/HH/grocery_list/g1'), false);
      expect(await exists('households/HH/meal_plans/w1'), false);
      expect(await exists('recipes/mine'), false);
      expect(await exists('recipes/byFormerMember'), false);
      expect(await exists('invitations/fromMyHousehold'), false);
      expect(await exists('invitations/toMe'), false);
      expect(await exists('join_codes/AAAAAAAAAA'), false);
      expect(await exists('users/me'), false);
      expect(storage.storedDataMap.containsKey('users/me/avatar.jpg'), false);
      expect(storage.storedDataMap.containsKey('households/HH/recipes/r.jpg'), false);
      expect(user.deleted, true);
    });

    test('rører ikke andres data', () async {
      await service.deleteAccount(password: 'hemmelig');

      expect(await exists('recipes/otherHousehold'), true);
      expect(await exists('invitations/toSomeoneElse'), true);
      expect(await exists('join_codes/OTHERHHHHH'), true);
    });

    test('sletter mere end ét batch (over 400 varer)', () async {
      final batch = db.batch();
      for (var i = 0; i < 450; i++) {
        batch.set(db.doc('households/HH/grocery_list/item$i'), {'name': 'Vare $i'});
      }
      await batch.commit();

      await service.deleteAccount(password: 'hemmelig');

      expect((await db.collection('households/HH/grocery_list').get()).docs, isEmpty);
    });
  });

  group('husstand med andre medlemmer', () {
    setUp(() async {
      await seedProfile(householdId: 'HH');
      await db.doc('households/HH').set({
        'name': 'Fælles', 'members': ['me', 'partner'], 'admin': 'me',
      });
      await db.doc('households/HH/grocery_list/g1').set({'name': 'Mælk'});
      await db.doc('recipes/mine').set({'householdId': 'HH', 'createdBy': 'me'});
      await db.doc('invitations/sentByMe').set({
        'fromHouseholdId': 'HH', 'fromUid': 'me', 'toUserEmail': 'y@example.com', 'status': 'pending',
      });
      await db.doc('invitations/sentByPartner').set({
        'fromHouseholdId': 'HH', 'fromUid': 'partner', 'toUserEmail': 'z@example.com', 'status': 'pending',
      });
    });

    test('melder sig ud og giver ejerskabet videre', () async {
      await service.deleteAccount(password: 'hemmelig');

      final household = (await db.doc('households/HH').get()).data()!;
      expect(household['members'], ['partner']);
      expect(household['admin'], 'partner');
      expect(await exists('users/me'), false);
      expect(user.deleted, true);
    });

    test('husstandens indhold og opskrifter bliver til de andre', () async {
      await service.deleteAccount(password: 'hemmelig');

      expect(await exists('households/HH/grocery_list/g1'), true);
      expect(await exists('recipes/mine'), true);
    });

    test('sletter kun de invitationskoder brugeren selv har lavet', () async {
      await db.doc('join_codes/MINEMINEMI').set({'householdId': 'HH', 'createdBy': 'me'});
      await db.doc('join_codes/PARTNERPAR').set({'householdId': 'HH', 'createdBy': 'partner'});

      await service.deleteAccount(password: 'hemmelig');

      expect(await exists('join_codes/MINEMINEMI'), false);
      expect(await exists('join_codes/PARTNERPAR'), true);
    });

    test('sletter kun de invitationer brugeren selv har sendt', () async {
      await service.deleteAccount(password: 'hemmelig');

      expect(await exists('invitations/sentByMe'), false);
      expect(await exists('invitations/sentByPartner'), true);
    });
  });

  test('eneste medlem uden ejerrettigheder sletter kun egne opskrifter', () async {
    // Ældre husstande har intet 'admin'-felt; reglerne tillader så kun at
    // slette egne opskrifter, og husstanden kan ikke slettes.
    await seedProfile(householdId: 'OLD');
    await db.doc('households/OLD').set({'name': 'Gammel', 'members': ['me']});
    await db.doc('recipes/mine').set({'householdId': 'OLD', 'createdBy': 'me'});
    await db.doc('recipes/theirs').set({'householdId': 'OLD', 'createdBy': 'zed'});

    await service.deleteAccount(password: 'hemmelig');

    expect(await exists('recipes/mine'), false);
    expect(await exists('recipes/theirs'), true);
    expect((await db.doc('households/OLD').get()).data()!['members'], isEmpty);
    expect(user.deleted, true);
  });

  test('bruger uden husstand kan stadig slette sin konto', () async {
    await seedProfile();

    await service.deleteAccount(password: 'hemmelig');

    expect(await exists('users/me'), false);
    expect(user.deleted, true);
  });

  test('husstand brugeren allerede er fjernet fra springes over', () async {
    await seedProfile(householdId: 'HH');
    await db.doc('households/HH').set({'name': 'X', 'members': ['partner'], 'admin': 'partner'});
    await db.doc('recipes/theirs').set({'householdId': 'HH', 'createdBy': 'partner'});

    await service.deleteAccount(password: 'hemmelig');

    expect(await exists('households/HH'), true);
    expect(await exists('recipes/theirs'), true);
    expect(user.deleted, true);
  });

  group('fejl', () {
    test('forkert adgangskode sletter intet', () async {
      await seedProfile(householdId: 'HH');
      await db.doc('households/HH').set({'name': 'Mit', 'members': ['me'], 'admin': 'me'});
      user.reauthErrorCode = 'invalid-credential';

      await expectLater(
        service.deleteAccount(password: 'forkert'),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.message, 'message', 'Forkert adgangskode.')),
      );
      expect(await exists('households/HH'), true);
      expect(await exists('users/me'), true);
      expect(user.deleted, false);
    });

    test('for mange forsøg giver en forståelig besked', () async {
      await seedProfile();
      user.reauthErrorCode = 'too-many-requests';

      await expectLater(
        service.deleteAccount(password: 'x'),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.message, 'message', contains('For mange forsøg'))),
      );
    });

    test('fejl ved sletning af login-kontoen vises som besked', () async {
      await seedProfile();
      user.deleteErrorCode = 'network-request-failed';

      await expectLater(
        service.deleteAccount(password: 'hemmelig'),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.message, 'message', contains('Ingen forbindelse'))),
      );
    });

    test('ikke logget ind', () async {
      final loggedOut = AccountDeletionService(
        auth: MockFirebaseAuth(signedIn: false),
        firestore: db,
        storage: storage,
      );

      await expectLater(
        loggedOut.deleteAccount(password: 'x'),
        throwsA(isA<AccountDeletionException>()),
      );
    });
  });
}
