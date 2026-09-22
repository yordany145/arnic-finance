
import '../../domain/repositories.dart';
import '../database.dart';
import '../settings_keys.dart';

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  Stream<String?> _watch(String key) => (_db.select(_db.appSettings)..where((s) => s.key.equals(key)))
      .watchSingleOrNull()
      .map((r) => r?.value);

  Future<void> _set(String key, String value) =>
      _db.into(_db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  @override
  Stream<String> watchCurrencySymbol() => _watch(kSettingCurrencySymbol).map((v) => v ?? kDefaultCurrencySymbol);

  @override
  Future<void> setCurrencySymbol(String symbol) => _set(kSettingCurrencySymbol, symbol.trim());

  @override
  Stream<String?> watchDefaultAccountId() => _watch(kSettingDefaultAccountId);

  @override
  Future<void> setDefaultAccountId(String id) => _set(kSettingDefaultAccountId, id);
}
