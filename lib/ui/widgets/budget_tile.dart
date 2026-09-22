import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';

/// Presupuesto con su barra de progreso. Verde tranquilo, ámbar ≥80%, rojo si
/// te pasaste (o verde intenso si ya cumpliste la meta de ahorro).
class BudgetTile extends StatelessWidget {
  const BudgetTile({super.key, required this.progress, required this.currency, this.onTap});

  final BudgetProgress progress;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final budget = progress.budget;
    final savings = budget.kind == BudgetKind.savings;
    final ratio = progress.ratio.clamp(0.0, 1.0);
    final over = progress.isOver;
    final metGoal = savings && progress.ratio >= 1.0;

    final barColor = over
        ? context.money.expense
        : metGoal
            ? context.money.income
            : progress.level == AlertLevel.approaching
                ? const Color(0xFFC77800)
                : scheme.primary;

    final pct = (progress.ratio * 100).clamp(0, 999).round();
    final subtitle = savings
        ? '${formatMoney(progress.currentMinor, currency)} de ${formatMoney(budget.amountMinor, currency)} ahorrados'
        : '${formatMoney(progress.currentMinor, currency)} de ${formatMoney(budget.amountMinor, currency)}'
            '${over ? ' · te pasaste' : ''}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(budget.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(budget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text('$pct%', style: TextStyle(fontWeight: FontWeight.w800, color: barColor)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: barColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
