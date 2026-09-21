import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/services/profile_image_service.dart';

class MockProfileImageService extends Mock implements ProfileImageService {}

void main() {
  group('ProfileImageAction Enum', () {
    test('contains camera, gallery, and delete values', () {
      expect(ProfileImageAction.values, contains(ProfileImageAction.camera));
      expect(ProfileImageAction.values, contains(ProfileImageAction.gallery));
      expect(ProfileImageAction.values, contains(ProfileImageAction.delete));
    });
  });

  group('FirebaseProfileImageService.showSourceSheet', () {
    testWidgets('displays camera and gallery options', (tester) async {
      ProfileImageAction? selectedAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedAction =
                      await FirebaseProfileImageService.showSourceSheet(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Tag et billede'), findsOneWidget);
      expect(find.text('Vælg fra bibliotek'), findsOneWidget);
      expect(find.text('Fjern profilbillede'), findsNothing);

      await tester.tap(find.text('Tag et billede'));
      await tester.pumpAndSettle();

      expect(selectedAction, ProfileImageAction.camera);
    });

    testWidgets('displays delete option when showDeleteOption is true',
        (tester) async {
      ProfileImageAction? selectedAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedAction =
                      await FirebaseProfileImageService.showSourceSheet(
                    context,
                    showDeleteOption: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Fjern profilbillede'), findsOneWidget);

      await tester.tap(find.text('Fjern profilbillede'));
      await tester.pumpAndSettle();

      expect(selectedAction, ProfileImageAction.delete);
    });
  });
}
