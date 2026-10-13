import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../profile/household_provider.dart';
import 'recipe_mapping.dart';

/// Hvor mange delte opskrifter der hentes ad gangen i Fællesskab.
const communityPageSize = 20;

/// Hvor længe der ventes efter sidste tastetryk, før der søges på serveren.
const communitySearchDebounce = Duration(milliseconds: 350);

/// Hvor mange sider der højst hentes i ét hug, når en side kun indeholder
/// husstandens egne opskrifter (de skjules i Fællesskab).
const _maxAutoPages = 3;

/// Tilstand for fanen Fællesskab: delte opskrifter fra andre husstande.
class CommunityState {
  /// Opskrifter hentet uden søgning (nyeste først), side for side.
  final List<Recipe> browse;

  /// Træffere på titel-præfikset for [query] (hentet fra serveren).
  final List<Recipe> searchHits;

  /// Den søgning [searchHits] hører til (trimmet, små bogstaver).
  final String query;
  final bool isLoading;
  final bool isLoadingMore;

  /// Om der kan være flere sider for den aktuelle visning (søgning eller ej).
  final bool hasMore;
  final Object? error;

  const CommunityState({
    this.browse = const [],
    this.searchHits = const [],
    this.query = '',
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
  });

  CommunityState copyWith({
    List<Recipe>? browse,
    List<Recipe>? searchHits,
    String? query,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      CommunityState(
        browse: browse ?? this.browse,
        searchHits: searchHits ?? this.searchHits,
        query: query ?? this.query,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Henter delte (`visibility == 'public'`) opskrifter side for side, uden at
/// hente dem alle på én gang. Husstandens egne skjules, da de vises under
/// "Vores".
class CommunityRecipesNotifier extends AutoDisposeNotifier<CommunityState> {
  final FirebaseFirestore _firestore;

  CommunityRecipesNotifier({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentSnapshot<Map<String, dynamic>>? _browseCursor;
  DocumentSnapshot<Map<String, dynamic>>? _searchCursor;
  Timer? _debounce;
  bool _browseHasMore = false;

  /// Øges ved hver ny søgning/genindlæsning, så et sent svar til en gammel
  /// søgning kasseres.
  int _generation = 0;

  String? get _ownHouseholdId => ref.read(householdProvider).householdId;

  @override
  CommunityState build() {
    ref.onDispose(() => _debounce?.cancel());
    // Start den første side uden for build.
    Future.microtask(_loadFirstPage);
    return const CommunityState();
  }

  CollectionReference<Map<String, dynamic>> get _recipes =>
      _firestore.collection('recipes');

  Query<Map<String, dynamic>> _browseQuery() => _recipes
      .where('visibility', isEqualTo: 'public')
      .orderBy('createdAt', descending: true);

  Query<Map<String, dynamic>> _searchQuery(String q) => _recipes
      .where('visibility', isEqualTo: 'public')
      .orderBy('titleLower')
      .startAt([q]).endAt(['$q\uf8ff']);

  /// De hentede opskrifter, uden husstandens egne. [titlePrefix] (små
  /// bogstaver) filtrerer søgetræf, så en opskrift hvis søgenøgle ikke passer
  /// til titlen aldrig vises.
  List<Recipe> _visible(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    String? titlePrefix,
  }) {
    final own = _ownHouseholdId;
    final result = <Recipe>[];
    for (final d in docs) {
      if (d.data()['householdId'] == own) continue;
      final r = recipeFromMap(d.id, d.data());
      final matches = titlePrefix == null ||
          r.title.toLowerCase().startsWith(titlePrefix);
      if (matches) result.add(r);
    }
    return result;
  }

  /// Henter/gen-henter første side (og nulstiller søgningen).
  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _browseCursor = null;
    _searchCursor = null;
    state = state.copyWith(
        browse: const [],
        searchHits: const [],
        query: '',
        isLoading: true,
        clearError: true);
    try {
      final r = await _fetchPages(_browseQuery(), null, generation);
      if (generation != _generation) return;
      _browseCursor = r.cursor;
      _browseHasMore = r.hasMore;
      state = state.copyWith(
          browse: r.recipes,
          isLoading: false,
          hasMore: r.hasMore,
          clearError: true);
    } catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> reload() => _loadFirstPage();

  /// Henter op til [_maxAutoPages] sider, indtil der er noget at vise.
  Future<
      ({
        List<Recipe> recipes,
        DocumentSnapshot<Map<String, dynamic>>? cursor,
        bool hasMore
      })> _fetchPages(
    Query<Map<String, dynamic>> base,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int generation, {
    String? titlePrefix,
  }) async {
    var cursor = after;
    var hasMore = true;
    final result = <Recipe>[];
    for (var page = 0;
        page < _maxAutoPages && hasMore && result.isEmpty;
        page++) {
      final paged = cursor == null ? base : base.startAfterDocument(cursor);
      final snap = await paged.limit(communityPageSize).get();
      if (generation != _generation) break;
      if (snap.docs.isNotEmpty) cursor = snap.docs.last;
      hasMore = snap.docs.length >= communityPageSize;
      result.addAll(_visible(snap.docs, titlePrefix: titlePrefix));
    }
    return (recipes: result, cursor: cursor, hasMore: hasMore);
  }

  /// Søger i titlerne (præfiks) på serveren, efter en kort pause i tastningen.
  /// Tom søgning går tilbage til den almindelige liste.
  void search(String text) {
    _debounce?.cancel();
    final q = text.trim().toLowerCase();
    if (q == state.query && !state.isLoading) return;
    if (q.isEmpty) {
      _generation++;
      _searchCursor = null;
      state = state.copyWith(
        searchHits: const [],
        query: '',
        isLoading: false,
        hasMore: _browseHasMore,
        clearError: true,
      );
      return;
    }
    _debounce = Timer(communitySearchDebounce, () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final generation = ++_generation;
    _searchCursor = null;
    state = state.copyWith(
        query: q, searchHits: const [], isLoading: true, clearError: true);
    try {
      final r =
          await _fetchPages(_searchQuery(q), null, generation, titlePrefix: q);
      if (generation != _generation) return;
      _searchCursor = r.cursor;
      state = state.copyWith(
          searchHits: r.recipes,
          isLoading: false,
          hasMore: r.hasMore,
          clearError: true);
    } catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  /// "Vis flere": næste side af den aktuelle visning (søgning eller liste).
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return;
    final generation = _generation;
    final searching = state.query.isNotEmpty;
    final cursor = searching ? _searchCursor : _browseCursor;
    if (cursor == null) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final r = await _fetchPages(
          searching ? _searchQuery(state.query) : _browseQuery(),
          cursor,
          generation,
          titlePrefix: searching ? state.query : null);
      if (generation != _generation) return;
      if (searching) {
        _searchCursor = r.cursor;
        state = state.copyWith(
            searchHits: [...state.searchHits, ...r.recipes],
            isLoadingMore: false,
            hasMore: r.hasMore);
      } else {
        _browseCursor = r.cursor;
        _browseHasMore = r.hasMore;
        state = state.copyWith(
            browse: [...state.browse, ...r.recipes],
            isLoadingMore: false,
            hasMore: r.hasMore);
      }
    } catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }
}

final communityRecipesProvider =
    NotifierProvider.autoDispose<CommunityRecipesNotifier, CommunityState>(
  CommunityRecipesNotifier.new,
);

/// En enkelt opskrift hentet direkte fra Firestore — bruges af detaljesiden
/// for opskrifter der ikke ligger i husstandens egen liste (delte opskrifter).
/// Null hvis den ikke findes eller ikke må læses.
final recipeByIdProvider =
    FutureProvider.autoDispose.family<Recipe?, String>((ref, id) async {
  try {
    final doc =
        await FirebaseFirestore.instance.collection('recipes').doc(id).get();
    final data = doc.data();
    return doc.exists && data != null ? recipeFromMap(doc.id, data) : null;
  } on FirebaseException {
    return null;
  }
});
