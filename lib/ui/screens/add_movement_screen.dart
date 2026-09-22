import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_labels.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/category_picker.dart';
import '../widgets/type_toggle.dart';

/// Registrar (o editar) un movimiento. Diseñado para el mínimo de pasos:
/// la categoría más usada y la cuenta predeterminada ya vienen elegidas, así que
/// lo normal es escribir el monto y pulsar GUARDAR.
class AddMovementScreen extends ConsumerStatefulWidget {
  const AddMovementScreen({super.key, this.editId, this.initialType = TxType.expense});

  final String? editId;
  final TxType initialType;

  @override
  ConsumerState<AddMovementScreen> createState() => _AddMovementScreenState();
}

class _AddMovementScreenState extends ConsumerState<AddMovementScreen> {
  late TxType _type = widget.initialType;
  String _amount = '';
  String? _categoryId;
  String? _accountId;
  DateTime? _pickedAt; // null = "ahora" (se toma al guardar)
  final _note = TextEditingController();
  Movement? _original; // sólo al editar
  bool _loading = false;
  bool _saving = false;

  bool get _editing => widget.editId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _loading = true;
      _loadOriginal();
    }
  }

  Future<void> _loadOriginal() async {
    final m = await ref.read(movementRepositoryProvider).getById(widget.editId!);
    if (!mounted) return;
    if (m == null) {
      context.pop();
      return;
    }
    setState(() {
      _original = m;
      _type = m.type;
      _amount = amountToInputText(m.amountMinor);
      _categoryId = m.category.id;
      _accountId = m.account.id;
      _pickedAt = m.occurredAt;
      _note.text = m.note ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final initial = _pickedAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    setState(() => _pickedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save({required String? categoryId, required String? accountId}) async {
    final minor = parseAmountMinor(_amount);
    final messenger = ScaffoldMessenger.of(context);
    if (minor <= 0) {
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(const SnackBar(content: Text('Escribe un monto')));
      return;
    }
    if (categoryId == null || accountId == null) return;

    // Se captura todo lo que hace falta ANTES del await: si el usuario cierra
    // la pantalla mientras se guarda, `ref` deja de ser válido pero estas
    // referencias siguen funcionando (el container vive mientras viva la app).
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(movementRepositoryProvider);
    final quickActions = container.read(quickActionsProvider);
    final currency = container.read(currencySymbolProvider).value ?? '';

    setState(() => _saving = true);
    final input = MovementInput(
      type: _type,
      amountMinor: minor,
      categoryId: categoryId,
      accountId: accountId,
      occurredAt: _pickedAt ?? DateTime.now(),
      note: _note.text,
    );
    if (_editing) {
      await repo.update(widget.editId!, input);
    } else {
      await repo.add(input);
    }
    quickActions.refreshWidgets();
    unawaited(checkBudgetAlerts(container));
    HapticFeedback.lightImpact();

    if (!mounted) return;
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${_type.label} guardado · ${formatMoney(minor, currency)}'),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Eliminar movimiento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(movementRepositoryProvider);
    final quickActions = container.read(quickActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.delete(widget.editId!);
    quickActions.refreshWidgets();
    if (!mounted) return;
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Movimiento eliminado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            repo.restore(widget.editId!);
            quickActions.refreshWidgets();
            unawaited(checkBudgetAlerts(container));
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typeColor = _type.isExpense ? context.money.expense : context.money.income;
    final currency = ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol;

    var categories = ref.watch(categoriesByUsageProvider(_type)).value ?? const <Category>[];
    // Al editar, la categoría original puede haberse borrado: sigue visible.
    final original = _original;
    if (original != null && original.type == _type && categories.every((c) => c.id != original.category.id)) {
      categories = [original.category, ...categories];
    }
    final categoryId = categories.any((c) => c.id == _categoryId) ? _categoryId : categories.firstOrNull?.id;

    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final defaultId = ref.watch(defaultAccountIdProvider).value;
    final accountId = accounts.any((a) => a.id == _accountId)
        ? _accountId
        : (accounts.any((a) => a.id == defaultId) ? defaultId : accounts.firstOrNull?.id);
    final account = accounts.where((a) => a.id == accountId).firstOrNull;

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final now = ref.watch(nowProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar movimiento' : 'Nuevo movimiento'),
        actions: [
          if (_editing) IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline), onPressed: _confirmDelete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      TypeToggle(
                        value: _type,
                        onChanged: (t) => setState(() {
                          _type = t;
                          _categoryId = null;
                        }),
                      ),
                      const SizedBox(height: 18),
                      _AmountDisplay(currency: currency, text: _amount, color: typeColor),
                      const SizedBox(height: 14),
                      Text('CATEGORÍA', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      CategoryPicker(
                        categories: categories,
                        selectedId: categoryId,
                        type: _type,
                        onSelected: (c) => setState(() => _categoryId = c.id),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _note,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(labelText: 'Nota (opcional)', prefixIcon: Icon(Icons.notes)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.schedule, size: 18),
                            label: Text(_pickedAt == null ? 'Ahora' : dateTimeLabel(_pickedAt!, now)),
                            onPressed: _pickDateTime,
                          ),
                          // Con una sola cuenta no se muestra: no estorba el registro rápido.
                          if (accounts.length > 1 && account != null)
                            PopupMenuButton<String>(
                              onSelected: (id) => setState(() => _accountId = id),
                              itemBuilder: (_) => [
                                for (final a in accounts) PopupMenuItem(value: a.id, child: Text('${a.icon}  ${a.name}')),
                              ],
                              child: IgnorePointer(
                                child: ActionChip(label: Text('${account.icon} ${account.name}'), onPressed: () {}),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!keyboardOpen) ...[
                          AmountKeypad(onKey: (k) => setState(() => _amount = applyAmountKey(_amount, k))),
                          const SizedBox(height: 10),
                        ],
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: typeColor, foregroundColor: scheme.surface),
                          onPressed: _saving ? null : () => _save(categoryId: categoryId, accountId: accountId),
                          child: const Text('GUARDAR'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.currency, required this.text, required this.color});

  final String currency;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final empty = text.isEmpty;
    return Semantics(
      label: 'Monto ${empty ? 'vacío' : text}',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(currency, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.8))),
            const SizedBox(width: 6),
            Text(
              empty ? '0' : _grouped(text),
              style: TextStyle(
                fontSize: 60,
                fontWeight: FontWeight.w800,
                color: empty ? color.withValues(alpha: 0.30) : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "1234.5" → "1,234.5" (sólo visual).
  String _grouped(String raw) {
    final dot = raw.indexOf('.');
    final whole = dot < 0 ? raw : raw.substring(0, dot);
    final frac = dot < 0 ? '' : raw.substring(dot);
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return '$buf$frac';
  }
}
