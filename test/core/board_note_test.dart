import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/board_note.dart';
import 'package:skafferiet/features/board/board_policy.dart';

const _validImage =
    'https://firebasestorage.googleapis.com/v0/b/siet-8630a.appspot.com/o/households%2Fh1%2Fboard%2Fa.jpg?alt=media';

Map<String, dynamic> _base(String type) => {
      'type': type,
      'authorId': 'u1',
      'createdAt': DateTime(2026, 10, 1, 12).millisecondsSinceEpoch,
      'isPinned': false,
    };

void main() {
  group('BoardNote.toMap / fromMap', () {
    test('tekstseddel gemmes og læses uændret', () {
      final note = TextNote(
        id: 'n1',
        authorId: 'u1',
        createdAt: DateTime(2026, 10, 1, 12),
        isPinned: true,
        text: 'Husk tandlæge',
      );
      final read = BoardNote.fromMap(note.toMap(), 'n1');
      expect(read, isA<TextNote>());
      read as TextNote;
      expect(read.text, 'Husk tandlæge');
      expect(read.isPinned, isTrue);
      expect(read.authorId, 'u1');
      expect(read.createdAt, DateTime(2026, 10, 1, 12));
    });

    test('billedseddel gemmes og læses uændret', () {
      final note = PhotoNote(
        id: 'p1',
        authorId: 'u1',
        createdAt: DateTime(2026, 10, 1),
        imageUrl: _validImage,
        caption: 'Ny opskrift',
      );
      final read = BoardNote.fromMap(note.toMap(), 'p1') as PhotoNote;
      expect(read.imageUrl, _validImage);
      expect(read.caption, 'Ny opskrift');
    });

    test('tjekliste gemmer afkrydsede punkter sorteret', () {
      final note = ChecklistNote(
        id: 'c1',
        authorId: 'u1',
        createdAt: DateTime(2026, 10, 1),
        title: 'Weekend',
        items: const ['Kul', 'Pølser', 'Brød'],
        done: const {2, 0},
      );
      final map = note.toMap();
      expect(map['done'], [0, 2]);
      final read = BoardNote.fromMap(map, 'c1') as ChecklistNote;
      expect(read.items, ['Kul', 'Pølser', 'Brød']);
      expect(read.done, {0, 2});
    });

    test('ukendt type eller manglende felter giver null i stedet for at crashe', () {
      expect(BoardNote.fromMap({..._base('poll'), 'text': 'x'}, 'x'), isNull);
      expect(BoardNote.fromMap({'type': 'text', 'text': 'x'}, 'x'), isNull);
      expect(BoardNote.fromMap({..._base('text')}, 'x'), isNull);
      expect(BoardNote.fromMap({..._base('text'), 'text': '   '}, 'x'), isNull);
      expect(BoardNote.fromMap({..._base('text'), 'createdAt': 'i går', 'text': 'x'}, 'x'), isNull);
    });

    test('billeder fra fremmede adresser afvises', () {
      for (final url in [
        'http://firebasestorage.googleapis.com/v0/b/x/o/a.jpg',
        'https://evil.example.com/pixel.gif',
        'https://firebasestorage.googleapis.com.evil.com/a.jpg',
        'javascript:alert(1)',
      ]) {
        expect(BoardNote.fromMap({..._base('photo'), 'imageUrl': url, 'caption': ''}, 'p'), isNull,
            reason: url);
      }
    });

    test('tjekliste: ugyldige punkter og indeks filtreres fra', () {
      final read = BoardNote.fromMap({
        ..._base('checklist'),
        'title': 'Liste',
        'items': ['Mælk', 42, '  ', 'Æg'],
        'done': [1, 7, -1, 'x'],
      }, 'c') as ChecklistNote;
      expect(read.items, ['Mælk', 'Æg']);
      expect(read.done, {1});
    });

    test('tjekliste uden punkter afvises', () {
      expect(
        BoardNote.fromMap({..._base('checklist'), 'title': 'Tom', 'items': [], 'done': []}, 'c'),
        isNull,
      );
    });

    test('for lang tekst fra databasen klippes til grænsen', () {
      final read = BoardNote.fromMap({..._base('text'), 'text': 'a' * 900}, 't') as TextNote;
      expect(read.text.length, BoardNoteLimits.textMax);
    });

    test('ChecklistNote.toggled slår et punkt til og fra', () {
      final note = ChecklistNote(
        id: 'c',
        authorId: 'u',
        createdAt: DateTime(2026),
        title: 't',
        items: const ['a', 'b'],
        done: const {0},
      );
      expect(note.toggled(0), <int>{});
      expect(note.toggled(1), {0, 1});
      expect(note.done, {0}, reason: 'det oprindelige sæt må ikke ændres');
    });
  });

  group('BoardPolicy', () {
    test('validateText', () {
      expect(BoardPolicy.validateText(''), isNotNull);
      expect(BoardPolicy.validateText('   '), isNotNull);
      expect(BoardPolicy.validateText('Hej'), isNull);
      expect(BoardPolicy.validateText('a' * 500), isNull);
      expect(BoardPolicy.validateText('a' * 501), isNotNull);
    });

    test('validateChecklist', () {
      expect(BoardPolicy.validateChecklist('', ['a']), isNotNull);
      expect(BoardPolicy.validateChecklist('Titel', ['', '  ']), isNotNull);
      expect(BoardPolicy.validateChecklist('Titel', ['a', '']), isNull);
      expect(BoardPolicy.validateChecklist('Titel', List.filled(21, 'x')), isNotNull);
      expect(BoardPolicy.validateChecklist('Titel', ['x' * 101]), isNotNull);
      expect(BoardPolicy.validateChecklist('x' * 81, ['a']), isNotNull);
    });

    test('canDelete: forfatter og admin, ingen andre', () {
      final note = TextNote(id: 'n', authorId: 'author', createdAt: DateTime(2026), text: 'x');
      expect(BoardPolicy.canDelete(note, currentUid: 'author', adminUid: 'boss'), isTrue);
      expect(BoardPolicy.canDelete(note, currentUid: 'boss', adminUid: 'boss'), isTrue);
      expect(BoardPolicy.canDelete(note, currentUid: 'other', adminUid: 'boss'), isFalse);
      expect(BoardPolicy.canDelete(note, currentUid: null, adminUid: null), isFalse);
    });

    test('sorted: fastgjorte først, derefter nyeste først', () {
      final old = TextNote(id: 'old', authorId: 'u', createdAt: DateTime(2026, 1, 1), text: 'x');
      final fresh = TextNote(id: 'new', authorId: 'u', createdAt: DateTime(2026, 2, 1), text: 'x');
      final pinnedOld = TextNote(
          id: 'pin', authorId: 'u', createdAt: DateTime(2025, 1, 1), isPinned: true, text: 'x');
      expect(BoardPolicy.sorted([old, pinnedOld, fresh]).map((n) => n.id), ['pin', 'new', 'old']);
    });
  });
}
