import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/date_labels.dart';
import 'data/database.dart';
import 'data/db_location.dart';
import 'data/server_sync_prefs.dart';
import 'data/secret_store.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(kLocale);
  final db = AppDatabase.file(await resolveDatabasePath());
  final prefs = await SharedPreferences.getInstance();
  final serverSyncPrefs = ServerSyncPrefs(prefs, const FlutterSecretStore());
  await serverSyncPrefs.load();
  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      serverSyncPrefsProvider.overrideWithValue(serverSyncPrefs),
    ],
    child: const ArnicApp(),
  ));
}
