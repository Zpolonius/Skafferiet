// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/onboarding/onboarding_screen.dart';
import 'package:skafferiet/features/onboarding/starter_recipes.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}
class MockFirebaseAuth extends Mock implements FirebaseAuth {}
class MockUser extends Mock implements User {}
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockWriteBatch extends Mock implements WriteBatch {}
class FakeDocumentReference<T extends Object?> extends Fake implements DocumentReference<T> {}

class MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  MockAuthNotifier(super.state);
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeDocumentReference<Object?>());
    registerFallbackValue(FakeDocumentReference<Map<String, dynamic>>());
    registerFallbackValue(SetOptions(merge: true));
  });

  group('Onboarding & completeOnboarding Tests', () {
    late MockFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockCollectionReference mockUsersCollection;
    late MockDocumentReference mockUserDoc;
    late MockCollectionReference mockHouseholdsCollection;
    late MockDocumentReference mockHouseholdDoc;
    late MockCollectionReference mockRecipesCollection;
    late MockDocumentReference mockRecipeDoc;
    late MockCollectionReference mockMealPlansCollection;
    late MockDocumentReference mockMealPlanDoc;
    late MockCollectionReference mockGroceryCollection;
    late MockDocumentReference mockGroceryDoc;
    late MockWriteBatch mockBatch;

    setUp(() {
      mockFirestore = MockFirestore();
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockUsersCollection = MockCollectionReference();
      mockUserDoc = MockDocumentReference();
      mockHouseholdsCollection = MockCollectionReference();
      mockHouseholdDoc = MockDocumentReference();
      mockRecipesCollection = MockCollectionReference();
      mockRecipeDoc = MockDocumentReference();
      mockMealPlansCollection = MockCollectionReference();
      mockMealPlanDoc = MockDocumentReference();
      mockGroceryCollection = MockCollectionReference();
      mockGroceryDoc = MockDocumentReference();
      mockBatch = MockWriteBatch();

      when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('user-123');
      when(() => mockUser.email).thenReturn('familie@eksempel.dk');
      when(() => mockUser.displayName).thenReturn('Jens Jensen');

      when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(() => mockUsersCollection.doc(any())).thenReturn(mockUserDoc);
      when(() => mockUserDoc.set(any(), any())).thenAnswer((_) async => {});
      when(() => mockUserDoc.snapshots()).thenAnswer((_) => const Stream.empty());

      when(() => mockFirestore.collection('households')).thenReturn(mockHouseholdsCollection);
      when(() => mockHouseholdsCollection.doc(any())).thenReturn(mockHouseholdDoc);
      when(() => mockHouseholdDoc.set(any(), any())).thenAnswer((_) async => {});
      when(() => mockHouseholdDoc.set(any())).thenAnswer((_) async => {});
      when(() => mockHouseholdDoc.snapshots()).thenAnswer((_) => const Stream.empty());

      when(() => mockFirestore.collection('recipes')).thenReturn(mockRecipesCollection);
      when(() => mockRecipesCollection.add(any())).thenAnswer((_) async => mockRecipeDoc);
      when(() => mockRecipeDoc.id).thenReturn('recipe-123');

      when(() => mockHouseholdDoc.collection('meal_plans')).thenReturn(mockMealPlansCollection);
      when(() => mockMealPlansCollection.doc(any())).thenReturn(mockMealPlanDoc);
      when(() => mockMealPlanDoc.set(any(), any())).thenAnswer((_) async => {});

      when(() => mockHouseholdDoc.collection('grocery_list')).thenReturn(mockGroceryCollection);
      when(() => mockGroceryCollection.doc(any())).thenReturn(mockGroceryDoc);
      when(() => mockGroceryCollection.doc()).thenReturn(mockGroceryDoc);
      when(() => mockGroceryCollection.add(any())).thenAnswer((_) async => mockGroceryDoc);

      when(() => mockFirestore.batch()).thenReturn(mockBatch);
      when(() => mockBatch.set(any(), any())).thenReturn(null);
      when(() => mockBatch.commit()).thenAnswer((_) async => {});

      final mockInvitationsCollection = MockCollectionReference();
      final mockInvitationsQuery = MockQuery();
      when(() => mockFirestore.collection('invitations')).thenReturn(mockInvitationsCollection);
      when(() => mockInvitationsCollection.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockInvitationsQuery);
      when(() => mockInvitationsQuery.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockInvitationsQuery);
      when(() => mockInvitationsQuery.snapshots()).thenAnswer((_) => const Stream.empty());
    });

    test('completeOnboarding saves household data, meal and marks onboarding completed', () async {
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);

      await notifier.completeOnboarding(
        householdName: 'Familien Jensens Skafferi',
        adultsCount: 2,
        childrenCount: 3,
        preferences: ['Børnevenligt', 'Hurtigt & nemt (<30 min)'],
        starterRecipe: starterRecipes.first,
      );

      // Verificer at user-dokumentet opdateres med hasCompletedOnboarding
      verify(() => mockUserDoc.set(
            any(that: containsPair('hasCompletedOnboarding', true)),
            any(),
          )).called(1);

      // Verificer at opskriften tilføjes til Firestore
      verify(() => mockRecipesCollection.add(any())).called(1);

      // Verificer at batch commit køres for indkøb
      verify(() => mockBatch.commit()).called(1);
    });

    testWidgets('OnboardingScreen navigates through 3 steps', (tester) async {
      final notifier = HouseholdNotifier(firestore: mockFirestore, auth: mockAuth);
      final authNotifier = MockAuthNotifier(AuthState(user: mockUser, isLoading: false));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            householdProvider.overrideWith((ref) => notifier),
            authProvider.overrideWith((ref) => authNotifier),
          ],
          child: const MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );

      // Trin 1: Hvem spiser med?
      expect(find.text('Hvem spiser med?'), findsOneWidget);
      expect(find.text('Trin 1 af 3'), findsOneWidget);
      expect(find.text('Voksne'), findsOneWidget);
      expect(find.text('Børn'), findsOneWidget);

      // Gå til Trin 2
      await tester.tap(find.text('Næste'));
      await tester.pumpAndSettle();

      // Trin 2: Familiens madstil
      expect(find.text('Familiens madstil'), findsOneWidget);
      expect(find.text('Trin 2 af 3'), findsOneWidget);
      expect(find.text('Børnevenligt'), findsOneWidget);

      // Gå til Trin 3
      await tester.tap(find.text('Næste'));
      await tester.pumpAndSettle();

      // Trin 3: Aftensmad til i aften
      expect(find.text('Hvad skal I have i aften?'), findsOneWidget);
      expect(find.text('Trin 3 af 3'), findsOneWidget);
      expect(find.text('Færdiggør og åbn Skafferiet'), findsOneWidget);
    });
  });
}
