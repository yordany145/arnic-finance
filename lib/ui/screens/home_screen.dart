import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../domain/month_pace.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/budget_tile.dart';
import '../widgets/card_usage_tile.dart';
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
    final cards = ref.watch(creditCardAccountsProvider);
    final cardDebt = ref.watch(creditCardNetSpendProvider);
    final pace = ref.watch(monthPaceProvider);
    final toReview = ref.watch(reviewQueueProvider);
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
              Expanded(child: Text('Arnic Finance', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              const _SyncChip(),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
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
                // El consumo con tarjeta de crédito resta del balance aunque todavía no haya salido dinero:
                // se dice para que un número negativo o bajo no asuste sin explicación.
                if (cardDebt > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.credit_card, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Incluye ${formatMoney(cardDebt, currency)} consumidos con tarjeta de crédito',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Este mes', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          SummaryRow(summary: month, currency: currency, showNet: false),
          if (pace != null) ...[
            const SizedBox(height: 10),
            _PaceCard(pace: pace, currency: currency),
          ],
          if (toReview.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ReviewBanner(count: toReview.length, onTap: () => context.push('/review')),
          ],
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Tarjetas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => context.push('/cards'), child: const Text('Ver todas')),
              ],
            ),
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CardUsageTile(account: card, onTap: () => context.push('/cards')),
              ),
          ],
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

/// Estado de la sincronización con el servidor (sólo si está activada): un fallo ya no pasa inadvertido.
class _SyncChip extends ConsumerWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(serverSyncEnabledProvider);
    final configured = ref.watch(serverSyncPrefsProvider).isConfigured;
    if (!enabled || !configured) return const SizedBox.shrink();
    final status = ref.watch(syncStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String text, Color color) = switch (status.state) {
      SyncState.syncing => (Icons.sync, 'Sincronizando…', scheme.onSurfaceVariant),
      SyncState.error => (Icons.cloud_off_outlined, 'Sin sincronizar · reintentar', scheme.error),
      SyncState.ok => (Icons.cloud_done_outlined, 'Sincronizado', scheme.onSurfaceVariant),
      SyncState.idle => (Icons.cloud_queue, 'Servidor', scheme.onSurfaceVariant),
    };
    return Tooltip(
      message: status.lastOk == null ? 'Toca para sincronizar ahora' : 'Última vez: ${_ago(status.lastOk!)}. Toca para sincronizar ahora.',
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 16, color: color),
        label: Text(text, style: TextStyle(fontSize: 12, color: color)),
        onPressed: status.state == SyncState.syncing ? null : () => syncWithServerIfEnabled(ProviderScope.containerOf(context, listen: false)),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }
}

class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.pace, required this.currency});

  final MonthPace pace;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = <String>[
      'Promedio de ${formatMoney(pace.dailyAverageMinor, currency)} al día',
      if (pace.projectionReliable) 'A este ritmo cerrarás el mes en ${formatMoney(pace.projectedMinor, currency)}',
      if (pace.perDayLeftMinor != null && pace.daysLeft > 0) 'Te quedan ${formatMoney(pace.perDayLeftMinor!, currency)} por día hasta fin de mes',
      if (pace.limitMinor != null && pace.spentMinor > pace.limitMinor!) 'Ya superaste tu límite general de ${formatMoney(pace.limitMinor!, currency)}',
    ];
    final warn = pace.projectedOverLimit && pace.projectionReliable || (pace.limitMinor != null && pace.spentMinor > pace.limitMinor!);
    final color = warn ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outlineVariant)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warn ? Icons.warning_amber_rounded : Icons.speed_outlined, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final l in lines) Text(l, style: TextStyle(fontSize: 13, color: color))],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = count == 1 ? '1 gasto del banco por revisar' : '$count gastos del banco por revisar';
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.rule_folder_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer)),
                    Text('Entraron solos y no tienen categoría. Tócalos para clasificarlos.', style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
