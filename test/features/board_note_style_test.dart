import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/board_note.dart';
import 'package:skafferiet/core/theme/app_colors.dart';
import 'package:skafferiet/features/board/board_note_style.dart';

void main() {
  late ColorScheme cs;

  setUpAll(() {
    // Samme farver som AppTheme.lightTheme sætter. AppTheme selv bruges ikke,
    // fordi den henter skrifttyper fra nettet, hvilket tests ikke må.
    cs = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primaryFixed: AppColors.primaryFixed,
      onPrimaryFixed: AppColors.onPrimaryFixed,
      secondaryFixed: AppColors.secondaryFixed,
      onSecondaryFixed: AppColors.onSecondaryFixed,
      tertiaryFixed: AppColors.tertiaryFixed,
      onTertiaryFixed: AppColors.onTertiaryFixed,
    ).copyWith(surfaceContainerLowest: AppColors.surfaceContainerLowest);
  });

  TextNote note(String id) => TextNote(id: id, authorId: 'u', createdAt: DateTime(2026), text: 'x');

  test('stableHash er fast – samme id giver altid samme tal', () {
    expect(BoardNoteStyle.stableHash('abc'), 96354);
    expect(BoardNoteStyle.stableHash(''), 0);
  });

  test('samme seddel får altid samme farve og hældning', () {
    final a = BoardNoteStyle.of(note('note-42'), cs);
    final b = BoardNoteStyle.of(note('note-42'), cs);
    expect(a.paper, b.paper);
    expect(a.tilt, b.tilt);
  });

  test('papirfarver kommer fra Kitchen Harmony-temaet', () {
    final allowed = [
      AppColors.secondaryFixed,
      AppColors.primaryFixed,
      AppColors.tertiaryFixed,
      AppColors.surfaceContainerLowest,
    ];
    final used = <Color>{};
    for (var i = 0; i < 200; i++) {
      final paper = BoardNoteStyle.of(note('id$i'), cs).paper;
      expect(allowed.map((c) => c.toARGB32()), contains(paper.toARGB32()));
      used.add(paper);
    }
    expect(used.length, greaterThan(1), reason: 'tavlen skal være farverig');
  });

  test('hældningen er lille (højst 2 grader)', () {
    for (var i = 0; i < 200; i++) {
      final tilt = BoardNoteStyle.of(note('id$i'), cs).tilt.abs();
      expect(tilt, lessThanOrEqualTo(2 * 3.14159 / 180));
    }
  });

  test('billedsedler er hvide som et polaroid', () {
    final photo = PhotoNote(
      id: 'p',
      authorId: 'u',
      createdAt: DateTime(2026),
      imageUrl: 'https://firebasestorage.googleapis.com/x',
    );
    expect(BoardNoteStyle.of(photo, cs).paper, cs.surfaceContainerLowest);
  });
}
