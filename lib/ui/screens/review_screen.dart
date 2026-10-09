import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/movement_tile.dart';

/// Gastos que entraron solos desde el aviso del banco y quedaron sin clasificar ("Otros").
/// Cada uno se resuelve en un toque: elegir la categoría, o confirmar que "Otros" está bien.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  Future<void> _setCategory(BuildContext context, WidgetRef ref, Movement m, List<Category> categories) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(movementRepositoryProvider);
    final quick = container.read(quickActionsProvider);
    final picked = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿En qué categoría va?', style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(bankLabel(m), style: TextStyle(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories.where((c) => c.id != m.category.id))
                    ActionChip(
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      label: Text('${c.icon}  ${c.name}', style: const TextStyle(fontSize: 16)),
                      onPressed: () => Navigator.pop(sheetContext, c),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await repo.update(
      m.id,
      MovementInput(type: m.type, amountMinor: m.amountMinor, categoryId: picked.id, accountId: m.account.id, occurredAt: m.occurredAt, note: m.note),
    );
    quick.refreshWidgets();
    unawaited(checkBudgetAlerts(container));
    unawaited(syncWithServerIfEnabled(container));
  }

  static String bankLabel(Movement m) => m.note ?? m.category.name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(reviewQueueProvider);
    // Se observa aquí (no se lee al tocar) para que ya esté cargada cuando se abra la hoja.
    final categories = ref.watch(categoriesByUsageProvider(TxType.expense)).value ?? const <Category>[];
    final currency = ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
    final now = ref.watch(nowProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Por revisar'),
        actions: [
          if (queue.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(reviewedIdsProvider.notifier).markAll(queue.map((m) => m.id)),
              child: const Text('Todo en orden'),
            ),
        ],
      ),
      body: queue.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.task_alt, size: 48, color: scheme.primary),
                    const SizedBox(height: 12),
                    Text('Todo clasificado.\nLos gastos nuevos del banco que no se puedan clasificar aparecerán aquí.',
                        textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    OutlinedButton(onPressed: () => context.pop(), child: const Text('Volver')),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Text(
                  'Estos gastos entraron solos desde los avisos de tu banco y no encajaron en ninguna categoría. '
                  'Elige la correcta; la app aprende de tus correcciones.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                for (final m in queue)
                  Card(
                    margin: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: [
                        MovementTile(movement: m, currency: currency, now: now, showAccount: true, onTap: () => context.push('/edit/${m.id}')),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () => _setCategory(context, ref, m, categories),
                                  icon: const Icon(Icons.category_outlined, size: 18),
                                  label: const Text('Elegir categoría'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => ref.read(reviewedIdsProvider.notifier).markAll([m.id]),
                                child: const Text('Está bien'),
                              ),
                            ],
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
