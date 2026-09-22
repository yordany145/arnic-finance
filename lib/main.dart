import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/date_labels.dart';
import 'data/database.dart';
import 'data/db_location.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(kLocale);
  final db = AppDatabase.file(await resolveDatabasePath());
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const ArnicApp(),
  ));
}
