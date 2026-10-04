import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../domain/models.dart';
import '../../domain/report.dart';
import '../../state/providers.dart';

/// Gasto por categoría del mes elegido y comparación de los últimos 6 meses, con barras sencillas (sin librerías):
/// se leen bien con lector de pantalla y respetan el tema claro/oscuro.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  static const _months = 6;
  int _selected = _months - 1; // índice en la lista de meses; el último es el actual

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(nowProvider);
    final currency = ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
    final movementsAsync = ref.watch(reportMovementsProvider);
    final movements = movementsAsync.value ?? const <Movement>[];
    final totals = monthlyTotals(movements, now, months: _months);
    final selected = totals[_selected];
    final categories = expenseByCategory(movements, selected.month);
    final maxMonth = totals.fold<int>(0, (m, t) => t.expenseMinor > m ? t.expenseMinor : m);
    final monthLabel = toBeginningOfSentenceCase(DateFormat.yMMMM('es').format(selected.month));

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes y gráficas')),
      body: movementsAsync.isLoading && !movementsAsync.hasValue
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Mes anterior',
                      onPressed: _selected > 0 ? () => setState(() => _selected--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(monthLabel, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mes siguiente',
                      onPressed: _selected < _months - 1 ? () => setState(() => _selected++) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Stat(label: 'Gastos', value: formatMoney(selected.expenseMinor, currency), color: scheme.error),
                    _Stat(label: 'Ingresos', value: formatMoney(selected.incomeMinor, currency), color: scheme.primary),
                    _Stat(label: 'Neto', value: formatMoney(selected.netMinor, currency, showSign: true), color: selected.netMinor < 0 ? scheme.error : scheme.primary),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Gasto por categoría', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (categories.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('No hay gastos registrados en este mes.', style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                else
                  for (final c in categories) _CategoryBar(total: c, of: selected.expenseMinor, currency: currency),
                const SizedBox(height: 24),
                Text('Últimos $_months meses (gastos)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 170,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < totals.length; i++)
                        Expanded(
                          child: _MonthBar(
                            totals: totals[i],
                            maxMinor: maxMonth,
                            selected: i == _selected,
                            currency: currency,
                            onTap: () => setState(() => _selected = i),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color))),
          ],
        ),
      );
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.total, required this.of, required this.currency});

  final CategoryTotal total;
  final int of;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = of == 0 ? 0.0 : total.minor / of;
    return Semantics(
      label: '${total.category.name}: ${formatMoney(total.minor, currency)}, ${(share * 100).round()}% del gasto del mes',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(total.category.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(total.category.name)),
                Text(formatMoney(total.minor, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(width: 48, child: Text('${(share * 100).round()}%', textAlign: TextAlign.end, style: TextStyle(color: scheme.onSurfaceVariant))),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: share, minHeight: 8, backgroundColor: scheme.surfaceContainerHighest),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.totals, required this.maxMinor, required this.selected, required this.currency, required this.onTap});

  final MonthTotals totals;
  final int maxMinor;
  final bool selected;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = maxMinor == 0 ? 0.0 : totals.expenseMinor / maxMinor;
    final name = toBeginningOfSentenceCase(DateFormat.MMM('es').format(totals.month));
    return Semantics(
      button: true,
      selected: selected,
      label: '$name: ${formatMoney(totals.expenseMinor, currency)} de gasto',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(_compact(totals.expenseMinor), style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.fade),
              const SizedBox(height: 4),
              Container(
                height: 100 * fraction + (totals.expenseMinor > 0 ? 4 : 1),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : scheme.primary.withValues(alpha: 0.35),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ),
              const SizedBox(height: 6),
              Text(name, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w800 : FontWeight.w400)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1,234,500 centavos → "12.3k"; 95,000 → "950". Cabe sobre una barra estrecha.
String _compact(int minor) {
  if (minor == 0) return '';
  final units = minor / 100;
  return units >= 1000 ? '${(units / 1000).toStringAsFixed(units >= 10000 ? 0 : 1)}k' : units.round().toString();
}
