import '../../core/models/recipe.dart';

final _wordSeparator = RegExp(r'[\s,.;:!?()/\-]+');

/// Søgeordene i [query]: små bogstaver (også æ/ø/å), delt på mellemrum og
/// tegnsætning ("kylling, ris."), uden tomme ord. Et efterstillet mellemrum
/// fra tastaturets ordforslag giver derfor ikke et ekstra (tomt) ord, der
/// matcher alt eller intet.
List<String> recipeSearchWords(String query) => query
    .toLowerCase()
    .split(_wordSeparator)
    .where((w) => w.isNotEmpty)
    .toList();

/// Sorteringsnøgle efter det danske alfabet: æ, ø, å kommer efter z og i den
/// rækkefølge (ren tegnkode-sortering lægger å før æ og ø).
String danishSortKey(String s) => s
    .toLowerCase()
    .replaceAll('æ', '{')
    .replaceAll('ø', '|')
    .replaceAll('å', '}');

bool _titleHas(Recipe r, String word) => r.title.toLowerCase().contains(word);

bool _ingredientHas(Recipe r, String word) =>
    r.ingredients.any((i) => i.name.toLowerCase().contains(word));

/// Om [recipe] matcher [query]: hvert søgeord skal findes (som tekststump) i
/// titlen eller i mindst ét ingrediensnavn. Ordene må godt fordele sig, så
/// "kylling ris" finder en opskrift med det ene i titlen og det andet i
/// ingredienserne. Tom søgning matcher alt.
bool matchesRecipeSearch(Recipe recipe, String query) {
  final words = recipeSearchWords(query);
  return words.every((w) => _titleHas(recipe, w) || _ingredientHas(recipe, w));
}

/// Om alle søgeord står i titlen (bruges til at sortere titel-træffere først).
bool titleMatchesRecipeSearch(Recipe recipe, String query) =>
    recipeSearchWords(query).every((w) => _titleHas(recipe, w));

/// Navnene på de ingredienser, der indeholder mindst ét søgeord (uden
/// dubletter, i opskriftens rækkefølge). Tom ved tom søgning.
List<String> matchingIngredientNames(Recipe recipe, String query) {
  final words = recipeSearchWords(query);
  if (words.isEmpty) return const [];
  final seen = <String>{};
  final result = <String>[];
  for (final i in recipe.ingredients) {
    final name = i.name.trim();
    final lower = name.toLowerCase();
    if (name.isNotEmpty && words.any(lower.contains) && seen.add(lower)) {
      result.add(name);
    }
  }
  return result;
}

/// De opskrifter i [all] der matcher [query]. Titel-træffere kommer først,
/// derefter dem der kun matcher via ingredienser; hver gruppe alfabetisk
/// efter det danske alfabet.
List<Recipe> searchRecipes(List<Recipe> all, String query) {
  int byTitle(Recipe a, Recipe b) =>
      danishSortKey(a.title).compareTo(danishSortKey(b.title));
  final hits = all.where((r) => matchesRecipeSearch(r, query)).toList();
  final inTitle = hits.where((r) => titleMatchesRecipeSearch(r, query)).toList()
    ..sort(byTitle);
  final viaIngredients = hits
      .where((r) => !titleMatchesRecipeSearch(r, query))
      .toList()
    ..sort(byTitle);
  return [...inTitle, ...viaIngredients];
}
