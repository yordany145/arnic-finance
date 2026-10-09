import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_labels.dart';
import '../../domain/assistant/text_normalize.dart';
import '../../domain/bank_movement.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/movement_tile.dart';
import '../widgets/period_chips.dart';
import '../widgets/summary_row.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Movimientos deslizados para borrar: se ocultan al instante (un `Dismissible`
  /// debe desaparecer del árbol en el mismo frame) hasta que la base confirme.
  final _hidden = <String>{};

  /// Búsqueda por texto en nota y categoría (sobre lo que el filtro de período/tipo ya muestra).
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() => setState(() {
        _searching = !_searching;
        if (!_searching) _searchController.clear();
      });

  bool _matches(Movement m, String query) {
    final haystack = normalize('${m.category.name} ${bankMerchant(m) ?? m.note ?? ''} ${m.account.name}');
    return query.split(' ').every(haystack.contains);
  }

  Future<void> _delete(Movement m) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(movementRepositoryProvider);
    final quick = container.read(quickActionsProvider);
    setState(() => _hidden.add(m.id));
    await repo.delete(m.id);
    quick.refreshWidgets();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Movimiento eliminado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () async {
            await repo.restore(m.id);
            quick.refreshWidgets();
            unawaited(checkBudgetAlerts(container));
            unawaited(syncWithServerIfEnabled(container));
            if (mounted) setState(() => _hidden.remove(m.id));
          },
        ),
      ));
  }

  Future<void> _pickCategory() async {
    // Se captura antes del `await showModalBottomSheet` por la misma razón que en `_delete`.
    final notifier = ref.read(historyFilterProvider.notifier);
    final current = ref.read(historyFilterProvider);
    final expense = ref.read(categoriesProvider(TxType.expense)).value ?? const <Category>[];
    final income = ref.read(categoriesProvider(TxType.income)).value ?? const <Category>[];
    final shown = switch (current.type) {
      TxType.expense => [expense],
      TxType.income => [income],
      null => [expense, income],
    };
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('Todas las categorías'),
              selected: current.categoryId == null,
              onTap: () => Navigator.pop(context, 'all'),
            ),
            for (final group in shown) ...[
              if (shown.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(group.first.type.pluralLabel.toUpperCase(), style: Theme.of(context).textTheme.labelMedium),
                ),
              for (final c in group)
                ListTile(
                  leading: Text(c.icon, style: const TextStyle(fontSize: 24)),
                  title: Text(c.name),
                  selected: current.categoryId == c.id,
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ],
        ),
      ),
    );
    if (picked == 'all') {
      notifier.setCategory(null);
    } else if (picked is Category) {
      notifier.setCategory(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(historyFilterProvider);
    final currency = ref.watch(currencySymbolProvider).value ?? 'RD\$';
    final summary = ref.watch(historySummaryProvider).value ?? const PeriodSummary();
    final query = normalize(_searchController.text);
    final movements = (ref.watch(historyMovementsProvider).value ?? const <Movement>[])
        .where((m) => !_hidden.contains(m.id) && (query.isEmpty || _matches(m, query)))
        .toList();
    // Con una búsqueda activa los totales deben corresponder a lo que se ve, no a todo el período.
    final shownSummary = query.isEmpty
        ? summary
        : PeriodSummary(
            incomeMinor: movements.where((m) => !m.type.isExpense).fold(0, (a, m) => a + m.amountMinor),
            expenseMinor: movements.where((m) => m.type.isExpense).fold(0, (a, m) => a + m.amountMinor),
          );
    final category = ref.watch(historyCategoryProvider).value;
    final now = ref.watch(nowProvider);
    final multipleAccounts = (ref.watch(accountsProvider).value?.length ?? 0) > 1;

    // Aplana a [cabecera de día | movimiento].
    final items = <Object>[];
    DateTime? lastDay;
    for (final m in movements) {
      final day = DateTime(m.occurredAt.year, m.occurredAt.month, m.occurredAt.day);
      if (day != lastDay) {
        items.add(day);
        lastDay = day;
      }
      items.add(m);
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar por comercio, nota o categoría',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(tooltip: 'Cerrar búsqueda', icon: const Icon(Icons.close), onPressed: _toggleSearch),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(child: Text('Movimientos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                      IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search), onPressed: _toggleSearch),
                    ],
                  ),
          ),
          const PeriodChips(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<TxType?>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: null, label: Text('Todos')),
                      ButtonSegment(value: TxType.expense, label: Text('Gastos')),
                      ButtonSegment(value: TxType.income, label: Text('Ingresos')),
                    ],
                    selected: {filter.type},
                    onSelectionChanged: (s) => ref.read(historyFilterProvider.notifier).setType(s.first, currentCategory: category),
                  ),
                ),
                const SizedBox(width: 8),
                InputChip(
                  avatar: category == null ? const Icon(Icons.filter_list, size: 18) : Text(category.icon),
                  label: Text(category?.name ?? 'Categoría'),
                  selected: category != null,
                  showCheckmark: false,
                  onPressed: _pickCategory,
                  onDeleted: category == null ? null : () => ref.read(historyFilterProvider.notifier).setCategory(null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SummaryRow(summary: shownSummary, currency: currency)),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(query.isEmpty ? 'Sin movimientos en este filtro' : 'Nada coincide con "${_searchController.text.trim()}"', style: TextStyle(color: scheme.onSurfaceVariant)))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 110),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      if (item is DateTime) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(dayHeader(item, now),
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                        );
                      }
                      final m = item as Movement;
                      return Dismissible(
                        key: ValueKey(m.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: scheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                        ),
                        onDismissed: (_) => _delete(m),
                        child: MovementTile(
                          movement: m,
                          currency: currency,
                          showAccount: multipleAccounts,
                          onTap: () => context.push('/edit/${m.id}'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
