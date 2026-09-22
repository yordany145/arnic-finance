import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';

/// App Group de iOS compartido con la extensión de widgets/controles y los
/// App Intents. Debe coincidir con el entitlement (ver docs/IOS.md).
const kAppGroupId = 'group.com.arnic.finance';

const kDatabaseFileName = 'arnic.db';

/// Ruta del archivo SQLite.
///
/// • Android: `context.filesDir` (lo comprobé en path_provider_android:
///   `getApplicationSupportPath` → `filesDir`). Kotlin usa la misma ruta.
/// • iOS: contenedor del App Group, para que la extensión lo vea. Si el App
///   Group aún no está configurado en Xcode, se usa el directorio privado de la
///   app (todo funciona salvo los accesos rápidos del sistema).
Future<String> resolveDatabasePath() async {
  String? dir;
  if (Platform.isIOS) {
    dir = await PathProviderFoundation().getContainerPath(appGroupIdentifier: kAppGroupId);
  }
  dir ??= (await getApplicationSupportDirectory()).path;
  await Directory(dir).create(recursive: true);
  return p.join(dir, kDatabaseFileName);
}
