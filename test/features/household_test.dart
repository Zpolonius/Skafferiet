import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    test('code generation uses 6 digits', () async {
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
      expect(code.length, 9); // SK-XXXXXX = 3 + 6 = 9
    });
  });
}
