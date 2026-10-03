import '../db/database.dart';
import 'validation.dart';

/// Resuelve lo que mandó quien llama a la API (un id exacto, un nombre exacto,
/// o un nombre parcial) contra las categorías reales del usuario. Nunca
/// inventa una categoría nueva ni adivina si hay ambigüedad: si no hay un
/// único resultado razonable, devuelve sugerencias para que quien integró la
/// API corrija el valor.
class CategoryMatch {
  const CategoryMatch.found(this.category) : suggestions = const [];
  const CategoryMatch.notFound(this.suggestions) : category = null;

  final CategoryRow? category;
  final List<CategoryRow> suggestions;
  bool get isFound => category != null;
}

CategoryMatch matchCategory(String input, List<CategoryRow> categories) {
  for (final c in categories) {
    if (c.id == input) return CategoryMatch.found(c);
  }
  final needle = normalize(input);
  for (final c in categories) {
    if (normalize(c.name) == needle) return CategoryMatch.found(c);
  }
  final partial = categories.where((c) {
    final name = normalize(c.name);
    return name.contains(needle) || needle.contains(name);
  }).toList();
  if (partial.length == 1) return CategoryMatch.found(partial.single);
  return CategoryMatch.notFound(categories);
}
