import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/grocery_screen.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/grocery/quick_add_field.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth() : super(AuthState());
}

void main() {
  testWidgets(
      'indkøbslisten har hurtig-tilføj i stedet for det døde søgefelt, og '
      'knappen "Tilføj vare" er bevaret', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _Auth()),
        householdProvider.overrideWith((ref) => _Household()),
        groceryListProvider
            .overrideWith(() => GroceryListNotifier(firestore: fs)),
        itemHistoryRepositoryProvider
            .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
        recurringItemsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child:
          MaterialApp(theme: AppTheme.lightTheme, home: const GroceryScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddField), findsOneWidget);
    expect(find.text('Tilføj vare…'), findsOneWidget);
    expect(find.text('Søg i din indkøbsliste...'), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.widgetWithText(FloatingActionButton, 'Tilføj vare'),
        findsOneWidget);

    // Hurtig-tilføj virker og feltet er stadig der bagefter (tom liste -> liste).
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '2 l mælk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Mælk'), findsOneWidget);
    expect(find.byType(QuickAddField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
