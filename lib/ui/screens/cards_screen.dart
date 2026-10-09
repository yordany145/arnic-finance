import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../domain/card_config.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/card_usage_tile.dart';

final _day = DateFormat('d MMM', 'es');
final _short = DateFormat('dd/MM');

/// Pide el nombre y crea una cuenta de tipo tarjeta de crédito; el límite y las fechas se ponen después tocándola.
Future<void> addCreditCard(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(accountRepositoryProvider);
  final name = await showDialog<String>(context: context, builder: (_) => const _NewCardDialog());
  if (name == null) return;
  await repo.create(name: name, icon: AccountKind.creditCard.defaultIcon, kind: AccountKind.creditCard);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$name creada. Tócala para poner el límite y las fechas.')));
}

class _NewCardDialog extends StatefulWidget {
  const _NewCardDialog();

  @override
  State<_NewCardDialog> createState() => _NewCardDialogState();
}

class _NewCardDialogState extends State<_NewCardDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva tarjeta'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Tarjeta Banreservas'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Crear')),
      ],
    );
  }
}

/// Tarjetas de crédito: consumo del ciclo frente al límite, lo que queda disponible y la fecha de pago.
/// Límite y días de corte y de pago se editan aquí y se sincronizan con el servidor, que también los
/// usa el puente de correo para sus avisos. El consumo no descuenta pagos: mide el ciclo, no la deuda total.
class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final cards = [for (final a in accounts) if (a.kind == AccountKind.creditCard) a];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tarjetas de crédito')),
      body: cards.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.credit_card_outlined, size: 48, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      'Aún no tienes tarjetas.\nAgrégalas para ver cuánto llevas gastado, lo que te queda y cuándo pagar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => addCreditCard(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar tarjeta'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Toca una tarjeta para poner su límite y sus fechas. El consumo cuenta desde el último corte y no descuenta pagos.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: _CardTile(account: card)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: () => addCreditCard(context, ref), icon: const Icon(Icons.add), label: const Text('Agregar otra tarjeta')),
                ),
              ],
            ),
    );
  }
}

class _CardTile extends ConsumerWidget {
  const _CardTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currency = ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
    final config = ref.watch(cardSettingsProvider).forAccount(account.id);
    final usage = ref.watch(cardUsageProvider(account.id)).value;
    final ratio = usage?.ratio;
    final now = ref.watch(nowProvider);
    final due = usage?.due;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(context, ref, config),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(account.icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(account.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  Icon(Icons.edit_outlined, color: scheme.outline, semanticLabel: 'Editar ${account.name}'),
                ],
              ),
              const SizedBox(height: 12),
              if (usage == null)
                const LinearProgressIndicator()
              else if (ratio == null) ...[
                Text(formatMoney(usage.spentMinor, currency), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('Consumido en el ciclo. Toca para poner el límite.', style: TextStyle(color: scheme.onSurfaceVariant)),
              ] else ...[
                Semantics(
                  label: '${(ratio * 100).round()}% del límite usado',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0, 1).toDouble(),
                      minHeight: 12,
                      color: cardBarColor(scheme, ratio),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatMoney(usage.spentMinor, currency)} de ${formatMoney(usage.limitMinor!, currency)} (${(ratio * 100).round()}%)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  ratio >= 1 ? 'Llegaste al límite del ciclo' : 'Disponible ${formatMoney(usage.availableMinor!, currency)}',
                  style: TextStyle(color: ratio >= 1 ? scheme.error : scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _Chip(
                    icon: Icons.event_repeat,
                    text: usage == null
                        ? '…'
                        : config?.cutDay == null
                            ? 'Mes calendario (sin día de corte)'
                            : 'Ciclo ${_short.format(usage.range.start)}–${_short.format(usage.range.lastDay)}',
                  ),
                  _Chip(
                    icon: Icons.payments_outlined,
                    text: due == null ? 'Sin fecha de pago' : 'Pago ${_day.format(due)} (${dueDaysLabel(due, now)})',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, CardConfig? current) async {
    final container = ProviderScope.containerOf(context);
    final currency = ref.read(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
    final result = await showDialog<CardConfig>(
      context: context,
      builder: (_) => _CardEditor(account: account, initial: current, currency: currency),
    );
    if (result == null) return;
    await ref.read(cardSettingsProvider.notifier).save(result);
    unawaited(syncWithServerIfEnabled(container));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${account.name}: guardado.')));
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: scheme.onSurfaceVariant), const SizedBox(width: 6), Flexible(child: Text(text, style: Theme.of(context).textTheme.bodySmall))]),
    );
  }
}

class _CardEditor extends StatefulWidget {
  const _CardEditor({required this.account, required this.initial, required this.currency});

  final Account account;
  final CardConfig? initial;
  final String currency;

  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final _limit = TextEditingController(text: widget.initial?.limitMinor == null ? '' : amountToInputText(widget.initial!.limitMinor!));
  late int? _cutDay = widget.initial?.cutDay;
  late int? _dueDay = widget.initial?.dueDay;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  void _save() {
    final text = _limit.text.trim().replaceAll(',', '');
    Navigator.pop(
      context,
      CardConfig(accountId: widget.account.id, limitMinor: text.isEmpty ? null : parseAmountMinor(text), cutDay: _cutDay, dueDay: _dueDay),
    );
  }

  Widget _dayField(String label, int? value, ValueChanged<int?> onChanged, String hint) => DropdownButtonFormField<int?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, helperText: hint),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Sin definir')),
          for (var d = 1; d <= 31; d++) DropdownMenuItem<int?>(value: d, child: Text('Día $d')),
        ],
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.account.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _limit,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Límite de crédito', prefixText: '${widget.currency} '),
            ),
            const SizedBox(height: 16),
            _dayField('Día de corte', _cutDay, (v) => setState(() => _cutDay = v), 'Cuando cierra el ciclo del estado de cuenta'),
            const SizedBox(height: 8),
            _dayField('Día límite de pago', _dueDay, (v) => setState(() => _dueDay = v), 'Te avisamos 3 días antes, el día anterior y ese día'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
