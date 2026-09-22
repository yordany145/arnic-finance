import 'package:arnic_finance/data/backup_service.dart';
import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_budget_repository.dart';
import 'package:arnic_finance/data/repositories/drift_category_repository.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/seed.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:arnic_finance/domain/repositories.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Cada test abre más de una AppDatabase.inMemory() a la vez (origen y
  // destino de la restauración): son independientes a propósito.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('exportar y restaurar en otra base reproduce los mismos datos', () async {
    final source = AppDatabase.inMemory();
    final movements = DriftMovementRepository(source);
    final categories = DriftCategoryRepository(source);
    final budgets = DriftBudgetRepository(source);

    await categories.create(name: 'Mascotas', icon: '🐶', type: TxType.expense);
    final petId = (await categories.watch(TxType.expense).first).last.id;
    final txId = await movements.add(MovementInput(
      type: TxType.expense,
      amountMinor: 12345,
      categoryId: petId,
      accountId: kDefaultAccountId,
      occurredAt: DateTime(2026, 9, 1),
      note: 'Comida del perro',
    ));
    await budgets.createCategoryBudget(categoryId: petId, amountMinor: 500000);

    final json = await BackupService(source).exportJson();
    await source.close();

    final target = AppDatabase.inMemory();
    await BackupService(target).restoreFromJson(json);

    final restoredMovements = DriftMovementRepository(target);
    final m = await restoredMovements.getById(txId);
    expect(m, isNotNull);
    expect(m!.amountMinor, 12345);
    expect(m.note, 'Comida del perro');
    expect(m.category.name, 'Mascotas');

    final restoredBudgets = await DriftBudgetRepository(target).watch().first;
    expect(restoredBudgets.single.amountMinor, 500000);
    expect(restoredBudgets.single.categoryName, 'Mascotas');

    await target.close();
  });

  test('restaurar reemplaza los datos existentes, no los combina', () async {
    final db = AppDatabase.inMemory();
    final movements = DriftMovementRepository(db);
    await movements.add(MovementInput(
      type: TxType.expense,
      amountMinor: 999,
      categoryId: 'exp_food',
      accountId: kDefaultAccountId,
      occurredAt: DateTime(2026, 1, 1),
    ));

    // Copia de un estado "vacío" (recién sembrado, sin el movimiento de arriba).
    final empty = AppDatabase.inMemory();
    final emptyBackup = await BackupService(empty).exportJson();
    await empty.close();

    await BackupService(db).restoreFromJson(emptyBackup);
    expect(await movements.watch(const MovementFilter()).first, isEmpty);

    await db.close();
  });

  test('rechaza un archivo que no es una copia de Arnic Finance', () async {
    final db = AppDatabase.inMemory();
    await expectLater(
      BackupService(db).restoreFromJson('{"algo": "distinto"}'),
      throwsFormatException,
    );
    await expectLater(BackupService(db).restoreFromJson('no es json'), throwsFormatException);
    await db.close();
  });
}
