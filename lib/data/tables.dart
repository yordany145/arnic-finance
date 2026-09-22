import 'package:drift/drift.dart';

import '../domain/enums.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONTRATO CON EL CÓDIGO NATIVO
// La Activity de registro rápido de Android (Kotlin) y los App Intents de iOS
// (Swift) leen/escriben estas mismas tablas directamente. Si cambias nombres de
// tablas/columnas o el formato de los valores, actualiza también:
//   android/.../quick/QuickDb.kt  e  ios/ArnicQuick/QuickDb.swift
// y sube `schemaVersion` (los nativos rechazan versiones que no conocen).
//
// Convenciones (pensadas para sincronizar en la nube después):
//  • id: UUID v4 en texto (se puede generar sin servidor, en cualquier cliente).
//  • created_at / updated_at / occurred_at: epoch en milisegundos (UTC).
//  • deleted_at: borrado lógico (tombstone); null = activo.
//  • amount_minor: entero positivo en unidades menores (centavos).
// ─────────────────────────────────────────────────────────────────────────────

@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  TextColumn get kind => textEnum<AccountKind>()();
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
  TextColumn get name => text()();
  TextColumn get icon => text()();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TxRow')
@TableIndex(name: 'idx_transactions_occurred_at', columns: {#occurredAt})
@TableIndex(name: 'idx_transactions_category', columns: {#categoryId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<TxType>()();
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

/// Ajustes clave/valor que también necesita el código nativo
/// (símbolo de moneda, cuenta predeterminada).
@DataClassName('SettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Presupuesto mensual: por categoría, límite general de gasto, o meta de ahorro.
/// `type` es el texto de [BudgetKind] (`category`/`overallExpense`/`savings`).
/// Desde schemaVersion 2.
@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();
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

/// Registro de qué avisos (80%/100%) ya se mandaron, por presupuesto y mes
/// ("2026-09"), para no repetir la notificación. `level` es el texto de
/// [AlertLevel] (`approaching`/`reached`). Desde schemaVersion 2.
@DataClassName('BudgetAlertRow')
class BudgetAlerts extends Table {
  TextColumn get budgetId => text().references(Budgets, #id)();
  TextColumn get periodKey => text()();
  TextColumn get level => text()();
  IntColumn get firedAt => integer()();

  @override
  Set<Column> get primaryKey => {budgetId, periodKey, level};
}
