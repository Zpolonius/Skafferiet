import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../../core/models/recipe_report.dart';
import '../../core/services/moderation_service.dart';
import '../recipes/recipes_provider.dart';

final moderationServiceProvider = Provider<ModerationService>((ref) {
  return ModerationService(
    firestore: FirebaseFirestore.instance,
    uid: ref.watch(currentUserIdProvider),
  );
});

/// ID på de opskrifter brugeren selv har rapporteret. Huskes i Firestore, så
/// opskrifterne også er skjult efter genstart.
final reportedRecipeIdsProvider =
    StreamProvider.autoDispose<Set<String>>((ref) {
  return _safeStream(
      () => ref.watch(moderationServiceProvider).watchReportedRecipeIds());
});

/// De forfattere brugeren har blokeret.
final blockedAuthorsProvider =
    StreamProvider.autoDispose<List<BlockedAuthor>>((ref) {
  return _safeStream(
      () => ref.watch(moderationServiceProvider).watchBlockedAuthors());
});

/// Bruger-ID på de blokerede forfattere (tom, mens listen hentes).
final blockedAuthorIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final blocked = ref.watch(blockedAuthorsProvider).valueOrNull ?? const [];
  return {for (final b in blocked) b.uid};
});

/// Uden Firebase (fx i en test uden login) er der intet at skjule.
Stream<T> _safeStream<T>(Stream<T> Function() open) {
  try {
    return open();
  } catch (_) {
    return const Stream.empty();
  }
}

/// [recipes] uden dem brugeren har rapporteret og uden blokerede forfatteres.
/// Kun til visning i Fællesskab og søgning: kopier i brugerens egen husstand
/// berøres ikke.
List<Recipe> withoutModerated(
  Iterable<Recipe> recipes, {
  required Set<String> reportedIds,
  required Set<String> blockedAuthorIds,
}) {
  if (reportedIds.isEmpty && blockedAuthorIds.isEmpty) return recipes.toList();
  return [
    for (final r in recipes)
      if (!reportedIds.contains(r.id) &&
          !(r.createdBy != null && blockedAuthorIds.contains(r.createdBy)))
        r,
  ];
}
