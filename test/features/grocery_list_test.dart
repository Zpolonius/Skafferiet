import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}
class MockFirebaseAuth extends Mock implements FirebaseAuth {}
class MockUser extends Mock implements User {}
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockQuerySnapshot extends Mock implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
}
class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  bool get exists => false;
}
class MockWriteBatch extends Mock implements WriteBatch {}

void main() {
  group('GroceryListNotifier Tests', () {
    late MockFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;

    setUp(() {
      mockFirestore = MockFirestore();
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();

      when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('test-uid');
      when(() => mockUser.email).thenReturn('test@example.com');

      final mockUsersCollection = MockCollectionReference();
      final mockInvitesCollection = MockCollectionReference();
      when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(() => mockFirestore.collection('invitations')).thenReturn(mockInvitesCollection);
      
      final mockUserDocRef = MockDocumentReference();
      when(() => mockUsersCollection.doc(any())).thenReturn(mockUserDocRef);
      when(() => mockUserDocRef.snapshots()).thenAnswer((_) => Stream.value(MockDocumentSnapshot()));

      final mockQuery = MockQuery();
      when(() => mockInvitesCollection.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.snapshots()).thenAnswer((_) => Stream.value(MockQuerySnapshot()));
    });

    test('reorderItems skriver korrekte sortOrder-værdier til Firestore', () async {
      final mockBatch = MockWriteBatch();
      final mockHouseholdsCollection = MockCollectionReference();
      final mockHouseholdDoc = MockDocumentReference();
      final mockGroceryCollection = MockCollectionReference();

      when(() => mockFirestore.collection('households')).thenReturn(mockHouseholdsCollection);
      when(() => mockHouseholdsCollection.doc(any())).thenReturn(mockHouseholdDoc);
      when(() => mockHouseholdDoc.collection('grocery_list')).thenReturn(mockGroceryCollection);

      final mockItemDoc1 = MockDocumentReference();
      final mockItemDoc2 = MockDocumentReference();
      final mockItemDoc3 = MockDocumentReference();
      when(() => mockGroceryCollection.doc('id-1')).thenReturn(mockItemDoc1);
      when(() => mockGroceryCollection.doc('id-2')).thenReturn(mockItemDoc2);
      when(() => mockGroceryCollection.doc('id-3')).thenReturn(mockItemDoc3);

      when(() => mockFirestore.batch()).thenReturn(mockBatch);
      when(() => mockBatch.update(any(), any())).thenReturn(null);
      when(() => mockBatch.commit()).thenAnswer((_) async {});

      // HouseholdProvider med householdId sat
      when(() => mockFirestore.collection('users')).thenReturn(MockCollectionReference());
      when(() => mockFirestore.collection('invitations')).thenReturn(MockCollectionReference());

      final container = ProviderContainer(
        overrides: [
          householdProvider.overrideWith((ref) => HouseholdNotifier(
            firestore: mockFirestore,
            auth: mockAuth,
          )),
          groceryListProvider.overrideWith(() => GroceryListNotifier(
            firestore: mockFirestore,
          )),
        ],
      );

      // Sæt householdId manuelt på state
      container.read(householdProvider.notifier).state =
          HouseholdState(householdId: 'hh-123');

      await container.read(groceryListProvider.notifier).reorderItems(
        ['id-1', 'id-2', 'id-3'],
      );

      verify(() => mockBatch.update(mockItemDoc1, {'sortOrder': 0})).called(1);
      verify(() => mockBatch.update(mockItemDoc2, {'sortOrder': 1})).called(1);
      verify(() => mockBatch.update(mockItemDoc3, {'sortOrder': 2})).called(1);
      verify(() => mockBatch.commit()).called(1);

      container.dispose();
    });

    test('reorderItems gør ingenting når householdId er null', () async {
      final mockBatch = MockWriteBatch();
      when(() => mockFirestore.batch()).thenReturn(mockBatch);

      final mockUsersCollection = MockCollectionReference();
      final mockInvitesCollection = MockCollectionReference();
      when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(() => mockFirestore.collection('invitations')).thenReturn(mockInvitesCollection);

      final mockUserDocRef = MockDocumentReference();
      when(() => mockUsersCollection.doc(any())).thenReturn(mockUserDocRef);
      when(() => mockUserDocRef.snapshots()).thenAnswer((_) => Stream.value(MockDocumentSnapshot()));

      final mockQuery = MockQuery();
      when(() => mockInvitesCollection.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.snapshots()).thenAnswer((_) => Stream.value(MockQuerySnapshot()));

      final container = ProviderContainer(
        overrides: [
          householdProvider.overrideWith((ref) => HouseholdNotifier(
            firestore: mockFirestore,
            auth: mockAuth,
          )),
          groceryListProvider.overrideWith(() => GroceryListNotifier(
            firestore: mockFirestore,
          )),
        ],
      );

      // householdId er null (default state)
      await container.read(groceryListProvider.notifier).reorderItems(['id-1', 'id-2']);

      verifyNever(() => mockBatch.commit());
      container.dispose();
    });

    test('Should return empty list when no householdId', () async {
      final container = ProviderContainer(
        overrides: [
          householdProvider.overrideWith((ref) => HouseholdNotifier(
            firestore: mockFirestore,
            auth: mockAuth,
          )),
          groceryListProvider.overrideWith(() => GroceryListNotifier(
            firestore: mockFirestore,
          )),
        ],
      );

      final items = await container.read(groceryListProvider.future);
      expect(items, isEmpty);
    });
  });
}
