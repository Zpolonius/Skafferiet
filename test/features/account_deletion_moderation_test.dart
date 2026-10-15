// #52: rapporter og blokeringer slettes sammen med kontoen, i alle stier.
// (Sikkerhedsreglerne for de samme forespørgsler testes i rules_test/.)
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/features/profile/account_deletion_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AccountDeletionService service;

  setUp(() async {
    db = FakeFirebaseFirestore();
    final user =
        MockUser(uid: 'me', email: 'me@example.com', displayName: 'Mig');
    service = AccountDeletionService(
      auth: MockFirebaseAuth(mockUser: user, signedIn: true),
      firestore: db,
      storage: MockFirebaseStorage(),
    );
    await db
        .doc('reports/a_me')
        .set({'recipeId': 'a', 'reportedBy': 'me', 'reason': 'spam'});
    await db
        .doc('reports/b_me')
        .set({'recipeId': 'b', 'reportedBy': 'me', 'reason': 'other'});
    await db
        .doc('reports/a_you')
        .set({'recipeId': 'a', 'reportedBy': 'you', 'reason': 'spam'});
    await db.doc('users/me/blocked_authors/eva').set({'name': 'Eva'});
    await db.doc('users/me/blocked_authors/per').set({'name': 'Per'});
    await db.doc('users/you/blocked_authors/eva').set({'name': 'Eva'});
  });

  Future<bool> exists(String path) async => (await db.doc(path).get()).exists;

  Future<void> expectCleaned() async {
    expect(await exists('reports/a_me'), false);
    expect(await exists('reports/b_me'), false);
    expect(await exists('users/me/blocked_authors/eva'), false);
    expect(await exists('users/me/blocked_authors/per'), false);
    expect(await exists('reports/a_you'), true,
        reason: 'andres rapporter røres ikke');
    expect(await exists('users/you/blocked_authors/eva'), true);
  }

  test('uden husstand', () async {
    await db.doc('users/me').set({'displayName': 'Mig'});
    await service.deleteAccount(password: 'x');
    await expectCleaned();
  });

  test('eneste medlem', () async {
    await db.doc('users/me').set({'displayName': 'Mig', 'householdId': 'HH'});
    await db.doc('households/HH').set({
      'name': 'Mit',
      'members': ['me'],
      'admin': 'me'
    });
    await service.deleteAccount(password: 'x');
    await expectCleaned();
  });

  test('med andre i husstanden', () async {
    await db.doc('users/me').set({'displayName': 'Mig', 'householdId': 'HH'});
    await db.doc('households/HH').set({
      'name': 'F',
      'members': ['me', 'p'],
      'admin': 'me'
    });
    await service.deleteAccount(password: 'x');
    await expectCleaned();
  });

  test('husstand brugeren allerede er fjernet fra', () async {
    await db.doc('users/me').set({'displayName': 'Mig', 'householdId': 'HH'});
    await db.doc('households/HH').set({
      'name': 'F',
      'members': ['p'],
      'admin': 'p'
    });
    await service.deleteAccount(password: 'x');
    await expectCleaned();
  });
}
