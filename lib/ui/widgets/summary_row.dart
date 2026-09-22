import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';

/// Ingresos / Gastos / Neto de un período.
class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.summary, required this.currency, this.showNet = true});

  final PeriodSummary summary;
  final String currency;
  final bool showNet;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Stat(label: 'Ingresos', value: formatMoney(summary.incomeMinor, currency), color: context.money.income)),
        const SizedBox(width: 10),
        Expanded(child: _Stat(label: 'Gastos', value: formatMoney(summary.expenseMinor, currency), color: context.money.expense)),
        if (showNet) ...[
          const SizedBox(width: 10),
          Expanded(child: _Stat(label: 'Neto', value: formatMoney(summary.balanceMinor, currency, showSign: true), color: null)),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }
}
