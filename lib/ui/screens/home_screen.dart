import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/budget_tile.dart';
import '../widgets/movement_tile.dart';
import '../widgets/summary_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currency = ref.watch(currencySymbolProvider).value ?? 'RD\$';
    final balance = ref.watch(balanceSummaryProvider).value ?? const PeriodSummary();
    final month = ref.watch(monthSummaryProvider).value ?? const PeriodSummary();
    final recent = ref.watch(recentMovementsProvider).value ?? const <Movement>[];
    final now = ref.watch(nowProvider);
    // Sólo los que ya están en 80%+: no llenamos la pantalla con presupuestos tranquilos.
    final attention = (ref.watch(budgetProgressProvider).value ?? const <BudgetProgress>[])
        .where((p) => p.level != null)
        .toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Row(
            children: [
              Image.asset('assets/images/logo.png', height: 30),
              const SizedBox(width: 10),
              Text('Arnic Finance', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [kBrandBlue, Color(0xFF1C7FB8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Balance actual', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(balance.balanceMinor, currency),
                    style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Este mes', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          SummaryRow(summary: month, currency: currency, showNet: false),
          if (attention.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Presupuestos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => context.push('/budgets'), child: const Text('Ver todos')),
              ],
            ),
            for (final p in attention.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BudgetTile(progress: p, currency: currency, onTap: () => context.push('/budgets')),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Recientes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => context.go('/history'), child: const Text('Ver todo')),
            ],
          ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: scheme.outline),
                  const SizedBox(height: 8),
                  Text('Aún no hay movimientos.\nPulsa + para registrar el primero.',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          else
            for (final m in recent)
              MovementTile(movement: m, currency: currency, now: now, onTap: () => context.push('/edit/${m.id}')),
        ],
      ),
    );
  }
}
