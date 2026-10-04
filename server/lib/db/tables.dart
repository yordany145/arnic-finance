import 'package:drift/drift.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONTRATO CON LA APP FLUTTER (../../lib/data/tables.dart)
//
// Mismo nombre/forma de columnas que el esquema del teléfono, para que
// sincronizar sea una copia directa fila a fila (mismo `id`, mismo
// `updated_at`, etc.). Este servidor es sólo un ESPEJO en la nube: la fuente
// de verdad para el usuario sigue siendo su teléfono.
//
// Diferencias a propósito frente al esquema del teléfono:
//  • Cada tabla gana `user_id` (aquí sí hay multi-usuario: distintos
//    dispositivos/API keys).
//  • `kind`/`type` son texto plano, no un enum de Dart: este paquete es Dart
//    puro (sin Flutter) y no importa `package:arnic_finance/domain/enums.dart`
//    a propósito, para no arrastrar el SDK de Flutter a un servidor. Los
//    valores válidos están documentados junto a cada columna y se validan en
//    `lib/util/validation.dart`.
//  • No existe `budget_alerts` aquí: son sólo marcas de qué avisos locales ya
//    se mandaron, no datos del usuario que tenga sentido sincronizar.
//
// Si cambias una columna aquí, cámbiala también en ../../lib/data/tables.dart
// (y viceversa) y revisa lib/util/validation.dart.
// ─────────────────────────────────────────────────────────────────────────────

@DataClassName('UserRow')
class Users extends Table {
  TextColumn get id => text()();

  /// SHA-256 (hex) de la API key. La key en texto plano NUNCA se guarda: se
  /// genera una vez en `POST /v1/setup` y sólo se devuelve esa vez.
  TextColumn get apiKeyHash => text().unique()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text()();

  /// 'cash' | 'bank' | 'creditCard' | 'savings' | 'checking' (AccountKind.name en Dart).
  TextColumn get kind => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text()();

  /// 'expense' | 'income'.
  TextColumn get type => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TxRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();

  /// 'expense' | 'income'.
  TextColumn get type => text()();
  // ignore: recursive_getters (patrón documentado de drift para CHECK)
  IntColumn get amountMinor => integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get note => text().nullable()();
  IntColumn get occurredAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();

  /// 'category' | 'overallExpense' | 'savings'.
  TextColumn get kind => text()();
  // ignore: recursive_getters (patrón documentado de drift para CHECK)
  IntColumn get amountMinor => integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Configuración por usuario que la app edita y otros servicios (el puente de correo) leen:
/// límites y días de corte/pago de las tarjetas, etc. Un solo JSON por usuario; el esquema de
/// `cards` se valida en lib/util/validation.dart. `updatedAt` es la hora de la edición en el
/// cliente (gana la más reciente, ver routes/config_routes.dart).
@DataClassName('UserConfigRow')
class UserConfigs extends Table {
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get json => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {userId};
}

/// Datos del propio servidor (no del usuario). Hoy: `epoch`, un identificador aleatorio creado junto con la base.
/// Si la base se pierde (el plan gratis de Render es efímero) y se recrea, el `epoch` cambia, y la app lo nota
/// y vuelve a subir todo en vez de asumir que el servidor aún tiene lo que ya había enviado.
@DataClassName('ServerMetaRow')
class ServerMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
