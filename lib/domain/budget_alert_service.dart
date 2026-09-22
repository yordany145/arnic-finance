import 'budget.dart';
import 'repositories.dart';

/// Revisa los presupuestos activos contra el mes actual y, si alguno cruzó
/// un umbral (80% o 100%) que todavía no se había avisado, lo notifica.
///
/// Se llama justo después de cualquier escritura (guardar/editar/borrar un
/// movimiento) y al reanudar la app, para detectar también lo que insertó
/// la hoja rápida nativa (Kotlin) mientras la app estaba en segundo plano.
class BudgetAlertService {
  BudgetAlertService(this._budgets, this._notify);

  final BudgetRepository _budgets;
  final Future<void> Function(BudgetProgress progress, AlertLevel level) _notify;

  Future<void> check(DateTime now) async {
    final period = monthPeriodKey(now);
    final progressList = await _budgets.watchProgress(now).first;
    for (final progress in progressList) {
      final level = progress.level;
      if (level == null) continue;
      final isNew = await _budgets.markAlertIfNew(progress.budget.id, period, level);
      if (isNew) await _notify(progress, level);
    }
  }
}
