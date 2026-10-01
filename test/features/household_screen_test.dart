import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/profile/household_screen.dart';
import 'package:skafferiet/features/profile/invitation_service.dart';
import 'package:skafferiet/features/profile/invite_member_card.dart';
import 'package:skafferiet/features/profile/profile_screen.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:go_router/go_router.dart';

class _MockUser extends Mock implements User {}

class _MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _MockAuthNotifier(super.state);
}

class _MockInvitationService extends Mock implements InvitationService {}

class _MockHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _MockHouseholdNotifier(super.state);
}

/// Tekstfeltet i den åbne dialog (siden har også sit eget e-mailfelt).
Finder _dialogField() =>
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

HouseholdState _household({
  String admin = 'me',
  List<String> members = const ['me', 'partner'],
}) =>
    HouseholdState(
      householdId: 'HH',
      householdName: 'Familien',
      adminUid: admin,
      members: members,
      memberNames: {
        for (final m in members) m: m == 'me' ? 'Mig' : (m == 'partner' ? 'Partner' : m),
      },
      isLoading: false,
    );

void main() {
  late _MockHouseholdNotifier notifier;
  late _MockInvitationService invitations;

  setUp(() => invitations = _MockInvitationService());

  void stubSend(String? result) {
    when(() => invitations.send(
          householdId: any(named: 'householdId'),
          householdName: any(named: 'householdName'),
          email: any(named: 'email'),
        )).thenAnswer((_) async => result);
  }

  Future<void> pump(
    WidgetTester tester,
    HouseholdState state, {
    List<SentInvitation> sent = const [],
  }) async {
    final user = _MockUser();
    when(() => user.uid).thenReturn('me');
    when(() => user.email).thenReturn('me@example.com');
    notifier = _MockHouseholdNotifier(state);

    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _MockAuthNotifier(AuthState(user: user))),
        householdProvider.overrideWith((ref) => notifier),
        sentInvitationsProvider.overrideWith((ref) => Stream.value(sent)),
        invitationServiceProvider.overrideWithValue(invitations),
      ],
      child: const MaterialApp(home: HouseholdScreen()),
    ));
    await tester.pumpAndSettle();
  }

  group('medlemmer', () {
    testWidgets('viser ejer, medlemmer og hvem man selv er', (tester) async {
      await pump(tester, _household());

      expect(find.text('Mig (dig)'), findsOneWidget);
      expect(find.text('Partner'), findsOneWidget);
      expect(find.text('Ejer'), findsOneWidget);
      expect(find.text('Kan redigere'), findsOneWidget);
      expect(find.text('2 medlemmer'), findsOneWidget);
    });

    testWidgets('ejeren kan fjerne andre, men ikke sig selv', (tester) async {
      await pump(tester, _household());

      expect(find.byTooltip('Fjern Partner'), findsOneWidget);
      expect(find.byTooltip('Fjern Mig'), findsNothing);
    });

    testWidgets('almindelige medlemmer kan ikke fjerne nogen', (tester) async {
      await pump(tester, _household(admin: 'partner'));

      expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
    });

    testWidgets('fjern spørger først og fortæller at koderne ugyldiggøres', (tester) async {
      await pump(tester, _household());
      when(() => notifier.removeMember(any())).thenAnswer((_) async => null);

      await tester.tap(find.byTooltip('Fjern Partner'));
      await tester.pumpAndSettle();
      expect(find.text('Fjern Partner?'), findsOneWidget);
      expect(find.textContaining('invitationskoder holder op med at virke'), findsOneWidget);

      await tester.tap(find.text('Annuller'));
      await tester.pumpAndSettle();
      verifyNever(() => notifier.removeMember(any()));

      await tester.tap(find.byTooltip('Fjern Partner'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Fjern'));
      await tester.pumpAndSettle();

      verify(() => notifier.removeMember('partner')).called(1);
      expect(find.text('Partner er fjernet fra husstanden.'), findsOneWidget);
    });

    testWidgets('fejl ved fjernelse vises', (tester) async {
      await pump(tester, _household());
      when(() => notifier.removeMember(any()))
          .thenAnswer((_) async => 'Kunne ikke fjerne medlemmet.');

      await tester.tap(find.byTooltip('Fjern Partner'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Fjern'));
      await tester.pumpAndSettle();

      expect(find.text('Kunne ikke fjerne medlemmet.'), findsOneWidget);
    });
  });

  group('forlad husstand', () {
    testWidgets('er slået fra for eneste medlem — med forklaring', (tester) async {
      await pump(tester, _household(members: ['me']));

      final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text('Forlad husstand'), matching: find.byType(ListTile)));
      expect(tile.enabled, false);
      expect(find.text('Ikke muligt, når du er eneste medlem'), findsOneWidget);
    });

    testWidgets('ejeren får at vide, hvem der bliver ny ejer', (tester) async {
      await pump(tester, _household());
      when(() => notifier.leaveHousehold()).thenAnswer((_) async => null);

      await tester.tap(find.text('Forlad husstand'));
      await tester.pumpAndSettle();

      expect(find.text('Forlad "Familien"?'), findsOneWidget);
      expect(find.textContaining('Partner bliver ny ejer'), findsOneWidget);
      expect(find.textContaining('egen, tomme husstand'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Forlad husstand'));
      await tester.pumpAndSettle();

      verify(() => notifier.leaveHousehold()).called(1);
      expect(find.text('Du har forladt "Familien".'), findsOneWidget);
    });

    testWidgets('fortryd forlader ikke', (tester) async {
      await pump(tester, _household(admin: 'partner'));

      await tester.tap(find.text('Forlad husstand'));
      await tester.pumpAndSettle();
      expect(find.textContaining('bliver ny ejer'), findsNothing);
      await tester.tap(find.text('Annuller'));
      await tester.pumpAndSettle();

      verifyNever(() => notifier.leaveHousehold());
    });
  });

  group('invitationer', () {
    Finder emailField() =>
        find.descendant(of: find.byType(InviteMemberCard), matching: find.byType(TextFormField));

    testWidgets('e-mail valideres, før der sendes', (tester) async {
      await pump(tester, _household());

      await tester.enterText(emailField(), 'ikke-en-mail');
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();

      expect(find.text('Ugyldig e-mail'), findsOneWidget);
      verifyNever(() => invitations.send(
            householdId: any(named: 'householdId'),
            householdName: any(named: 'householdName'),
            email: any(named: 'email'),
          ));
    });

    testWidgets('"inviteret" vises først, når invitationen er gemt', (tester) async {
      await pump(tester, _household());
      stubSend(null);
      // Kortet siger ærligt, at der ikke sendes en mail.
      expect(find.textContaining('Der sendes ikke en mail'), findsOneWidget);

      await tester.enterText(emailField(), ' Ven@Example.com ');
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();

      verify(() => invitations.send(
            householdId: 'HH',
            householdName: 'Familien',
            email: 'ven@example.com',
          )).called(1);
      expect(find.textContaining('ven@example.com er inviteret'), findsOneWidget);
      // Feltet tømmes, så man kan invitere den næste.
      expect(
          tester
              .widget<EditableText>(
                  find.descendant(of: emailField(), matching: find.byType(EditableText)))
              .controller
              .text,
          isEmpty);
    });

    testWidgets('fejl vises ved feltet, og e-mailen bliver stående', (tester) async {
      await pump(tester, _household());
      stubSend('ven@example.com er allerede inviteret.');

      await tester.enterText(emailField(), 'ven@example.com');
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invite_error')), findsOneWidget);
      expect(find.textContaining('er inviteret. De ser'), findsNothing);
      expect(find.text('ven@example.com'), findsOneWidget);
    });

    testWidgets('ventende invitationer vises under medlemmerne og kan annulleres', (tester) async {
      await pump(tester, _household(), sent: const [
        SentInvitation(id: 'inv1', email: 'ven@example.com', fromUserName: 'Mig'),
      ]);
      when(() => invitations.cancel(any())).thenAnswer((_) async => null);

      expect(find.text('Afventer svar …'), findsOneWidget);
      expect(find.text('ven@example.com'), findsOneWidget);

      await tester.tap(find.byTooltip('Annullér invitationen til ven@example.com'));
      await tester.pumpAndSettle();

      verify(() => invitations.cancel('inv1')).called(1);
      expect(find.text('Invitationen til ven@example.com er annulleret.'), findsOneWidget);
    });

    testWidgets('ingen ventende invitationer: ingen "Afventer svar"', (tester) async {
      await pump(tester, _household());

      expect(find.text('Afventer svar …'), findsNothing);
      expect(find.text('Medlemmer (2)'), findsOneWidget);
    });
  });

  group('invitationskode', () {
    testWidgets('Del invitationskode viser den nye kode formateret', (tester) async {
      await pump(tester, _household());
      when(() => notifier.createJoinCode()).thenAnswer((_) async => 'ABCDEFGHJK');

      await tester.tap(find.text('Del invitationskode'));
      await tester.pumpAndSettle();

      expect(find.text('ABCDE-FGHJK'), findsOneWidget);
      expect(find.text('Koden virker i 7 dage.'), findsOneWidget);
      verify(() => notifier.createJoinCode()).called(1);
    });

    testWidgets('Kopiér kode lægger koden i udklipsholderen', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(tester, _household());
      when(() => notifier.createJoinCode()).thenAnswer((_) async => 'ABCDEFGHJK');

      await tester.tap(find.text('Del invitationskode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kopiér kode'));
      await tester.pumpAndSettle();

      expect(copied, 'ABCDE-FGHJK');
      expect(find.text('Kopieret'), findsOneWidget);
    });

    testWidgets('fejl ved oprettelse giver en forståelig besked', (tester) async {
      await pump(tester, _household());
      when(() => notifier.createJoinCode()).thenAnswer((_) async => null);

      await tester.tap(find.text('Del invitationskode'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Koden kunne ikke laves'), findsOneWidget);
    });

    testWidgets('Deltag i en anden husstand advarer og sender koden videre', (tester) async {
      await pump(tester, _household());
      when(() => notifier.joinHousehold(any())).thenAnswer((_) async {});

      await tester.tap(find.text('Deltag i en anden husstand'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Du forlader "Familien"'), findsOneWidget);

      await tester.enterText(_dialogField(), 'abcde-fghjk');
      await tester.tap(find.text('Deltag'));
      await tester.pumpAndSettle();

      verify(() => notifier.joinHousehold('abcde-fghjk')).called(1);
    });
  });

  group('omdøb', () {
    testWidgets('omdøb gemmer navnet og begrænser det til 60 tegn', (tester) async {
      await pump(tester, _household());
      when(() => notifier.renameHousehold(any())).thenAnswer((_) async {});

      await tester.tap(find.byTooltip('Omdøb husstand'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_dialogField()).maxLength, 60);

      await tester.enterText(_dialogField(), 'Nyt Navn');
      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      verify(() => notifier.renameHousehold('Nyt Navn')).called(1);
    });
  });

  testWidgets('fejl fra husstanden (fx udløbet kode) vises', (tester) async {
    await pump(tester, _household());

    // ignore: invalid_use_of_protected_member
    notifier.state = notifier.state.copyWith(error: 'Koden er ugyldig eller udløbet');
    await tester.pumpAndSettle();

    expect(find.text('Koden er ugyldig eller udløbet'), findsOneWidget);
  });

  testWidgets('en fejl vises kun én gang, selvom profilen ligger nedenunder', (tester) async {
    final user = _MockUser();
    when(() => user.uid).thenReturn('me');
    when(() => user.email).thenReturn('me@example.com');
    when(() => user.displayName).thenReturn('Mig');
    when(() => user.photoURL).thenReturn(null);
    notifier = _MockHouseholdNotifier(_household());
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
        routes: [GoRoute(path: 'household', builder: (_, __) => const HouseholdScreen())],
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _MockAuthNotifier(AuthState(user: user))),
        householdProvider.overrideWith((ref) => notifier),
        sentInvitationsProvider.overrideWith((ref) => Stream.value(const [])),
        invitationServiceProvider.overrideWithValue(invitations),
        recipesProvider.overrideWith(() => _EmptyRecipes()),
        groceryListProvider.overrideWith(() => _EmptyGrocery()),
        mealPlanProvider.overrideWith(() => _EmptyMealPlan()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    router.push('/profile/household');
    await tester.pumpAndSettle();

    // ignore: invalid_use_of_protected_member
    notifier.state = notifier.state.copyWith(error: 'Koden er ugyldig eller udløbet');
    await tester.pumpAndSettle();
    expect(find.text('Koden er ugyldig eller udløbet'), findsOneWidget);

    // Lad den første besked udløbe. En kopi i køen ville dukke op nu.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Koden er ugyldig eller udløbet'), findsNothing);
  });
}

class _EmptyRecipes extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => const Stream.empty();
}

class _EmptyGrocery extends StreamNotifier<List<GroceryItem>>
    with Mock
    implements GroceryListNotifier {
  @override
  Stream<List<GroceryItem>> build() => const Stream.empty();
}

class _EmptyMealPlan extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async =>
      WeeklyMealPlan(id: 'empty', weekStart: DateTime(2026, 5, 4), days: {});
}
