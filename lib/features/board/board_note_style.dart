import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/models/board_note.dart';

/// Hvordan en seddel ser ud på tavlen: papirfarve og hældning.
///
/// Begge dele udledes af sedlens id, så den samme seddel altid ser ens ud –
/// også hos de andre i husstanden – uden at gemme noget ekstra i databasen.
class BoardNoteStyle {
  final Color paper;
  final Color onPaper;

  /// Hældning i radianer.
  final double tilt;

  const BoardNoteStyle({required this.paper, required this.onPaper, required this.tilt});

  static const _tiltsDegrees = [-1.6, -0.8, 0.6, 1.4];

  factory BoardNoteStyle.of(BoardNote note, ColorScheme cs) {
    final hash = stableHash(note.id);
    final tilt = _tiltsDegrees[hash % _tiltsDegrees.length] * math.pi / 180;

    // Billeder vises som polaroid på hvidt papir.
    if (note is PhotoNote) {
      return BoardNoteStyle(paper: cs.surfaceContainerLowest, onPaper: cs.onSurface, tilt: tilt);
    }

    // Pastelfarver fra Kitchen Harmony-temaet.
    final papers = [
      (cs.secondaryFixed, cs.onSecondaryFixed),
      (cs.primaryFixed, cs.onPrimaryFixed),
      (cs.tertiaryFixed, cs.onTertiaryFixed),
      (cs.surfaceContainerLowest, cs.onSurface),
    ];
    final (paper, onPaper) = papers[(hash ~/ 7) % papers.length];
    return BoardNoteStyle(paper: paper, onPaper: onPaper, tilt: tilt);
  }

  /// Samme tal for samme tekst på alle enheder og ved hver kørsel
  /// (`String.hashCode` garanterer ikke det).
  static int stableHash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }
}
