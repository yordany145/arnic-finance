import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../domain/budget.dart';
import '../../domain/budget_suggestions.dart';
import '../../domain/enums.dart';
import '../../state/providers.dart';
import '../widgets/budget_tile.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Budget b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar "${b.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) await ref.read(budgetRepositoryProvider).delete(b.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currency = ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
    final suggestions = ref.watch(budgetSuggestionsProvider);
    final progressList = ref.watch(budgetProgressProvider).value ?? const <BudgetProgress>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Presupuestos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBudgetEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo presupuesto'),
      ),
      body: progressList.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 100),
              children: [
                Icon(Icons.savings_outlined, size: 48, color: scheme.outline),
                const SizedBox(height: 12),
                Text(
                  'Aún no tienes presupuestos.\nCrea uno para que Arnic te avise cuando te acerques o llegues a un límite o meta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (suggestions.isNotEmpty) _SuggestionsCard(suggestions: suggestions, currency: currency),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: progressList.length + (suggestions.isEmpty ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i == progressList.length) return _SuggestionsCard(suggestions: suggestions, currency: currency);
                final p = progressList[i];
                return Dismissible(
                  key: ValueKey(p.budget.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) async {
                    await _delete(context, ref, p.budget);
                    return false; // el propio delete actualiza el stream; evita doble animación.
                  },
                  background: Container(
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(18)),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                  ),
                  child: BudgetTile(progress: p, currency: currency, onTap: () => showBudgetEditor(context, ref, existing: p.budget)),
                );
              },
            ),
    );
  }
}

/// Límites propuestos a partir de lo que realmente se gastó en meses anteriores: un toque y queda creado.
class _SuggestionsCard extends ConsumerWidget {
  const _SuggestionsCard({required this.suggestions, required this.currency});

  final List<BudgetSuggestion> suggestions;
  final String currency;

  Future<void> _create(BuildContext context, WidgetRef ref, BudgetSuggestion s) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    await container.read(budgetRepositoryProvider).createCategoryBudget(categoryId: s.category.id, amountMinor: s.suggestedMinor);
    await container.read(budgetNotifierProvider).requestPermission();
    unawaited(syncWithServerIfEnabled(container));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Límite de ${formatMoney(s.suggestedMinor, currency)} para ${s.category.name}.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lightbulb_outline, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Sugeridos para ti', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Text('Según lo que gastaste en los últimos meses.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text(s.category.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Gastas ~${formatMoney(s.averageMinor, currency)} al mes', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  // El tema da a los botones ancho infinito: dentro de una fila hay que quitárselo o aplasta el texto.
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => _create(context, ref, s),
                    child: Text(formatMoney(s.suggestedMinor, currency)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showBudgetEditor(BuildContext context, WidgetRef ref, {Budget? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BudgetEditor(existing: existing),
  );
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({this.existing});

  final Budget? existing;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  late BudgetKind _kind = widget.existing?.kind ?? BudgetKind.category;
  late String? _categoryId = widget.existing?.categoryId;
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : (widget.existing!.amountMinor / 100).toStringAsFixed(0),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pesos = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (pesos == null || pesos <= 0) return;
    final minor = (pesos * 100).round();
    // Capturado antes de los await: `ref` puede dejar de ser válido si la
    // hoja se cierra mientras se guarda.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(budgetRepositoryProvider);
    final notifier = container.read(budgetNotifierProvider);

    if (widget.existing != null) {
      await repo.updateAmount(widget.existing!.id, minor);
    } else {
      switch (_kind) {
        case BudgetKind.category:
          if (_categoryId == null) return;
          await repo.createCategoryBudget(categoryId: _categoryId!, amountMinor: minor);
        case BudgetKind.overallExpense:
          await repo.createOverallExpenseBudget(amountMinor: minor);
        case BudgetKind.savings:
          await repo.createSavingsBudget(amountMinor: minor);
      }
      // Sólo tiene sentido pedir el permiso cuando ya hay algo que notificar.
      await notifier.requestPermission();
    }
    unawaited(syncWithServerIfEnabled(container));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final categories = ref.watch(categoriesProvider(TxType.expense)).value ?? const [];
    final existingBudgets = ref.watch(budgetsProvider).value ?? const [];
    // Sólo se puede tener un presupuesto por categoría (y uno general, uno de ahorro).
    final usedCategoryIds = existingBudgets.where((b) => b.kind == BudgetKind.category).map((b) => b.categoryId).toSet();
    final hasOverall = existingBudgets.any((b) => b.kind == BudgetKind.overallExpense);
    final hasSavings = existingBudgets.any((b) => b.kind == BudgetKind.savings);
    final availableCategories = categories.where((c) => !usedCategoryIds.contains(c.id)).toList();
    if (_kind == BudgetKind.category && _categoryId == null && availableCategories.isNotEmpty) {
      _categoryId = availableCategories.first.id;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? 'Editar presupuesto' : 'Nuevo presupuesto', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (!editing) ...[
              SegmentedButton<BudgetKind>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: BudgetKind.category, label: Text('Categoría')),
                  ButtonSegment(value: BudgetKind.overallExpense, label: const Text('General'), enabled: !hasOverall),
                  ButtonSegment(value: BudgetKind.savings, label: const Text('Ahorro'), enabled: !hasSavings),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 16),
            ],
            if (_kind == BudgetKind.category && !editing)
              if (availableCategories.isEmpty)
                const Text('Ya tienes un presupuesto para todas tus categorías de gasto.')
              else
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final c in availableCategories) DropdownMenuItem(value: c.id, child: Text('${c.icon}  ${c.name}')),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
            if (editing) Text('${widget.existing!.icon}  ${widget.existing!.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: !editing,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _kind == BudgetKind.savings ? 'Meta de ahorro' : 'Límite mensual',
                prefixText: ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(
              _kind == BudgetKind.savings
                  ? 'Te avisaremos cuando te acerques (80%) y cuando cumplas la meta este mes.'
                  : 'Te avisaremos cuando llegues al 80% y al 100% de este límite, cada mes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('GUARDAR')),
          ],
        ),
      ),
    );
  }
}
