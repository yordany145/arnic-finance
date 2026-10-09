import 'package:shared_preferences/shared_preferences.dart';

/// Ids de gastos del banco que el usuario ya confirmó ("está bien") aunque sigan en "Otros".
/// Solo vive en el teléfono: es una comodidad de la bandeja "Por revisar", no un dato contable.
class ReviewedStore {
  ReviewedStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'reviewed_movement_ids_v1';

  /// Tope para que la lista no crezca sin límite con los años (se conservan los más recientes).
  static const _max = 500;

  Set<String> read() => (_prefs.getStringList(_key) ?? const <String>[]).toSet();

  Future<void> write(Set<String> ids) {
    final list = ids.toList();
    return _prefs.setStringList(_key, list.length > _max ? list.sublist(list.length - _max) : list);
  }
}
