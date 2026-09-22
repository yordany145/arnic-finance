// OJO: la ñ/Ñ NO va aquí a propósito — se conserva (sólo baja a minúscula
// más abajo). Incluirla aquí la convertiría en "n" y rompería nombres reales
// ("Cañón", "Peña").
const _accented = 'áéíóúÁÉÍÓÚüÜ';
const _plain = 'aeiouAEIOUuU';

/// Minúsculas, sin acentos (conserva la ñ), espacios colapsados. Es la base de
/// todo el análisis del asistente: todas las palabras clave se comparan ya
/// normalizadas.
String normalize(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final i = _accented.indexOf(char);
    buffer.write(i >= 0 ? _plain[i] : char);
  }
  return buffer.toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Distancia de edición con transposición (Damerau-Levenshtein, variante de
/// "alineación óptima"): además de insertar/borrar/sustituir, intercambiar
/// dos letras adyacentes cuenta como un solo cambio. Se hace así porque es,
/// con diferencia, el typo más común al escribir rápido ("comdia" en vez de
/// "comida"), y sin esto un Levenshtein normal lo cuenta como distancia 2.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final rows = a.length + 1;
  final cols = b.length + 1;
  final d = List.generate(rows, (i) => List<int>.filled(cols, 0));
  for (var i = 0; i < rows; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j < cols; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i < rows; i++) {
    for (var j = 1; j < cols; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        best = best < d[i - 2][j - 2] + 1 ? best : d[i - 2][j - 2] + 1;
      }
      d[i][j] = best;
    }
  }
  return d[a.length][b.length];
}

/// `true` si [needle] (una sola palabra o una frase de varias) aparece en
/// [haystack]: como sub-cadena si tiene espacios ("banco popular"), como
/// palabra completa si es una sola, o como una variante muy cercana (typo)
/// de una palabra de [haystack] cuando [needle] tiene 5+ letras.
bool containsWord(String haystack, String needle) {
  if (needle.isEmpty) return false;
  if (needle.contains(' ')) return haystack.contains(needle);
  final words = haystack.split(RegExp(r'[^a-zñ0-9]+'));
  for (final w in words) {
    if (w == needle) return true;
    if (needle.length >= 5 && w.length >= 4 && levenshtein(w, needle) <= 1) return true;
  }
  return false;
}
