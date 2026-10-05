import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/app_info.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/profile/change_password_screen.dart';
import 'package:skafferiet/features/profile/help_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/profile/preferences_screen.dart';

class _MockUser extends Mock implements User {}

class _MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _MockAuthNotifier(super.state);
}

class _MockHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _MockHouseholdNotifier(super.state);
}

Future<void> _setSize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  group('Præferencer & Diæt', () {
    late _MockHouseholdNotifier household;

    Future<void> pump(WidgetTester tester) async {
      await _setSize(tester);
      household = _MockHouseholdNotifier(HouseholdState(
        householdId: 'HH',
        householdName: 'Familien',
        adultsCount: 2,
        childrenCount: 1,
        preferences: const ['Budgetvenligt'],
        isLoading: false,
      ));
      await tester.pumpWidget(ProviderScope(
        overrides: [householdProvider.overrideWith((ref) => household)],
        child: const MaterialApp(home: PreferencesScreen()),
      ));
      await tester.pumpAndSettle();
    }

    FilledButton saveButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gem'));

    testWidgets('viser husstandens nuværende valg og at de gælder alle', (tester) async {
      await pump(tester);

      expect(find.text('Gælder for alle i "Familien".'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      // Kun det valgte tema har flueben.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('Gem er slået fra, indtil noget er ændret', (tester) async {
      await pump(tester);
      expect(saveButton(tester).onPressed, isNull);

      await tester.tap(find.bySemanticsLabel('Børn: flere'));
      await tester.pumpAndSettle();
      expect(saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.bySemanticsLabel('Børn: færre'));
      await tester.pumpAndSettle();
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('gemmer antal og temaer i listens rækkefølge', (tester) async {
      await pump(tester);
      when(() => household.updatePreferences(
            adultsCount: any(named: 'adultsCount'),
            childrenCount: any(named: 'childrenCount'),
            preferences: any(named: 'preferences'),
          )).thenAnswer((_) async => null);

      await tester.tap(find.bySemanticsLabel('Voksne: flere'));
      await tester.tap(find.text('Børnevenligt'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Gem'));
      await tester.pumpAndSettle();

      verify(() => household.updatePreferences(
            adultsCount: 3,
            childrenCount: 1,
            preferences: ['Børnevenligt', 'Budgetvenligt'],
          )).called(1);
      expect(find.text('Præferencerne er gemt.'), findsOneWidget);
    });

    testWidgets('man kan ikke vælge 0 personer i alt', (tester) async {
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Børn: færre'));
      await tester.tap(find.bySemanticsLabel('Voksne: færre'));
      await tester.pumpAndSettle();
      // 1 voksen, 0 børn: minus-knapperne er nu slået fra.
      await tester.tap(find.bySemanticsLabel('Voksne: færre'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('fejl ved gem vises', (tester) async {
      await pump(tester);
      when(() => household.updatePreferences(
            adultsCount: any(named: 'adultsCount'),
            childrenCount: any(named: 'childrenCount'),
            preferences: any(named: 'preferences'),
          )).thenAnswer((_) async => 'Kunne ikke gemme.');

      await tester.tap(find.text('Grønt & Sundt'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Gem'));
      await tester.pumpAndSettle();

      expect(find.text('Kunne ikke gemme.'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNotNull);
    });
  });

  group('Hjælp & Support', () {
    Uri? launched;
    late bool launchSucceeds;

    Future<void> pump(WidgetTester tester) async {
      await _setSize(tester);
      launched = null;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '1.2.3 (45)'),
          externalLinkLauncherProvider.overrideWithValue((uri) async {
            launched = uri;
            return launchSucceeds;
          }),
        ],
        child: const MaterialApp(home: HelpScreen()),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() => launchSucceeds = true);

    testWidgets('svar på spørgsmål foldes ud', (tester) async {
      await pump(tester);

      expect(find.textContaining('egen, tomme husstand'), findsNothing);
      await tester.tap(find.text('Hvad sker der, hvis jeg forlader en husstand?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('egen, tomme husstand'), findsOneWidget);
    });

    testWidgets('viser appens version', (tester) async {
      await pump(tester);

      expect(find.text('Skafferiet version 1.2.3 (45)'), findsOneWidget);
    });

    testWidgets('Skriv til os åbner en mail med version i', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Skriv til os'));
      await tester.pumpAndSettle();

      expect(launched?.scheme, 'mailto');
      expect(launched?.path, AppInfo.contactEmail);
      final query = Uri.decodeComponent(launched!.query);
      expect(query, contains('Version: 1.2.3 (45)'));
      // Mellemrum skal være %20 — "+" vises som plus i mail-apps.
      expect(launched!.query, isNot(contains('+')));
    });

    testWidgets('uden mail-app kopieres adressen i stedet', (tester) async {
      launchSucceeds = false;
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
      await pump(tester);

      await tester.tap(find.text('Skriv til os'));
      await tester.pumpAndSettle();

      expect(copied, AppInfo.contactEmail);
      expect(find.textContaining('E-mailadressen er kopieret'), findsOneWidget);
    });
  });

  group('Skift adgangskode', () {
    late _MockAuthNotifier auth;

    Future<void> pump(WidgetTester tester) async {
      await _setSize(tester);
      final user = _MockUser();
      when(() => user.email).thenReturn('me@example.com');
      auth = _MockAuthNotifier(AuthState(user: user));
      await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: const MaterialApp(home: ChangePasswordScreen()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, String current, String next, String repeat) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), current);
      await tester.enterText(fields.at(1), next);
      await tester.enterText(fields.at(2), repeat);
      await tester.tap(find.widgetWithText(FilledButton, 'Skift adgangskode'));
      await tester.pumpAndSettle();
    }

    void stubChange(String? result) {
      when(() => auth.changePassword(
            currentPassword: any(named: 'currentPassword'),
            newPassword: any(named: 'newPassword'),
          )).thenAnswer((_) async => result);
    }

    testWidgets('validerer felterne, før noget sendes', (tester) async {
      await pump(tester);

      await fill(tester, '', 'kort', 'andet');
      expect(find.text('Indtast din nuværende adgangskode'), findsOneWidget);
      expect(find.text('Adgangskoden skal være mindst 6 tegn'), findsOneWidget);
      expect(find.text('Adgangskoderne er ikke ens'), findsOneWidget);

      await fill(tester, 'gammel123', 'gammel123', 'gammel123');
      expect(find.textContaining('skal være en anden'), findsOneWidget);

      verifyNever(() => auth.changePassword(
            currentPassword: any(named: 'currentPassword'),
            newPassword: any(named: 'newPassword'),
          ));
    });

    testWidgets('skifter adgangskoden', (tester) async {
      await pump(tester);
      stubChange(null);

      await fill(tester, 'gammel123', 'ny-kode-456', 'ny-kode-456');

      verify(() => auth.changePassword(
            currentPassword: 'gammel123',
            newPassword: 'ny-kode-456',
          )).called(1);
      expect(find.text('Din adgangskode er skiftet.'), findsOneWidget);
    });

    testWidgets('forkert nuværende adgangskode vises på siden', (tester) async {
      await pump(tester);
      stubChange('Den nuværende adgangskode er forkert.');

      await fill(tester, 'forkert', 'ny-kode-456', 'ny-kode-456');

      expect(find.byKey(const Key('change_password_error')), findsOneWidget);
      expect(find.text('Den nuværende adgangskode er forkert.'), findsOneWidget);
    });

    testWidgets('adgangskoderne er skjult, indtil man vælger at vise dem', (tester) async {
      await pump(tester);

      EditableText field(int i) => tester.widget<EditableText>(find.descendant(
          of: find.byType(TextFormField).at(i), matching: find.byType(EditableText)));
      expect(field(0).obscureText, true);
      expect(field(1).obscureText, true);

      await tester.tap(find.byTooltip('Vis adgangskoder'));
      await tester.pumpAndSettle();
      expect(field(0).obscureText, false);
    });
  });
}
