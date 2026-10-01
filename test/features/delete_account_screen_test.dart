import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/features/profile/account_deletion_service.dart';
import 'package:skafferiet/features/profile/delete_account_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class _MockHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _MockHouseholdNotifier(super.state);
}

class _MockDeletionService extends Mock implements AccountDeletionService {}

void main() {
  late _MockHouseholdNotifier household;
  late _MockDeletionService service;

  HouseholdState state({List<String> members = const ['me']}) => HouseholdState(
        householdId: 'HH',
        householdName: 'Familien',
        adminUid: 'me',
        members: members,
        isLoading: false,
      );

  Future<void> pumpScreen(WidgetTester tester, HouseholdState initial) async {
    household = _MockHouseholdNotifier(initial);
    when(() => household.pauseForAccountDeletion()).thenReturn(null);
    when(() => household.resumeAfterFailedAccountDeletion()).thenReturn(null);
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        householdProvider.overrideWith((ref) => household),
        accountDeletionServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: DeleteAccountScreen()),
    ));
  }

  setUp(() => service = _MockDeletionService());

  testWidgets('eneste medlem får at vide, at hele husstanden slettes', (tester) async {
    await pumpScreen(tester, state());

    expect(find.textContaining('Hele "Familien"'), findsOneWidget);
    expect(find.textContaining('meldes ud'), findsNothing);
  });

  testWidgets('med andre medlemmer meldes man ud, og opskrifterne bliver', (tester) async {
    await pumpScreen(tester, state(members: ['me', 'partner']));

    expect(find.textContaining('Du meldes ud af "Familien"'), findsOneWidget);
    expect(find.textContaining('Opskrifter du har lavet bliver'), findsOneWidget);
    expect(find.textContaining('Hele "Familien"'), findsNothing);
  });

  testWidgets('uden husstand nævnes ingen husstand', (tester) async {
    await pumpScreen(tester, HouseholdState(isLoading: false));

    expect(find.textContaining('Hele "'), findsNothing);
    expect(find.textContaining('meldes ud'), findsNothing);
    expect(find.textContaining('Din profil'), findsOneWidget);
  });

  testWidgets('kræver adgangskode før noget slettes', (tester) async {
    await pumpScreen(tester, state());

    await tester.tap(find.text('Slet min konto permanent'));
    await tester.pumpAndSettle();

    expect(find.text('Indtast din adgangskode'), findsOneWidget);
    verifyNever(() => service.deleteAccount(password: any(named: 'password')));
    verifyNever(() => household.pauseForAccountDeletion());
  });

  testWidgets('sletter med adgangskoden og stopper husstandens lyttere først', (tester) async {
    when(() => service.deleteAccount(password: any(named: 'password')))
        .thenAnswer((_) async {});
    await pumpScreen(tester, state());

    await tester.enterText(find.byType(TextFormField), 'hemmelig');
    await tester.tap(find.text('Slet min konto permanent'));
    // Ikke pumpAndSettle: spinneren kører, indtil routeren (ikke med i
    // testen) sender brugeren til login.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    verifyInOrder([
      () => household.pauseForAccountDeletion(),
      () => service.deleteAccount(password: 'hemmelig'),
    ]);
    verifyNever(() => household.resumeAfterFailedAccountDeletion());
    expect(find.text('Din konto og dine data er slettet.'), findsOneWidget);
  });

  testWidgets('forkert adgangskode: viser fejlen og starter appen igen', (tester) async {
    when(() => service.deleteAccount(password: any(named: 'password')))
        .thenThrow(const AccountDeletionException('Forkert adgangskode.'));
    await pumpScreen(tester, state());

    await tester.enterText(find.byType(TextFormField), 'forkert');
    await tester.tap(find.text('Slet min konto permanent'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete_account_error')), findsOneWidget);
    expect(find.text('Forkert adgangskode.'), findsOneWidget);
    verify(() => household.resumeAfterFailedAccountDeletion()).called(1);
    // Knappen kan bruges igen.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('teksten skifter ikke, mens husstanden nulstilles under sletningen', (tester) async {
    when(() => service.deleteAccount(password: any(named: 'password')))
        .thenAnswer((_) => Future.delayed(const Duration(seconds: 1)));
    await pumpScreen(tester, state(members: ['me', 'partner']));
    when(() => household.pauseForAccountDeletion()).thenAnswer((_) {
      // ignore: invalid_use_of_protected_member
      household.state = HouseholdState(isLoading: true);
    });

    await tester.enterText(find.byType(TextFormField), 'hemmelig');
    await tester.tap(find.text('Slet min konto permanent'));
    await tester.pump();

    expect(find.textContaining('Du meldes ud af "Familien"'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
