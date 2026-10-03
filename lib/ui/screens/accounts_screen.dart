import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/emoji_grid.dart';

/// Cuentas / métodos de pago. Con una sola cuenta (Efectivo) el registro rápido
/// ni la muestra; al crear más, aparece un selector discreto en el formulario.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar "${a.name}"?'),
        content: const Text('Sus movimientos no se borran: seguirán en el historial.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(accountRepositoryProvider).delete(a.id);
    } on StateError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final defaultId = ref.watch(defaultAccountIdProvider).value ?? accounts.firstOrNull?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAccountEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cuenta'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('La cuenta predeterminada (★) es la que se usa al registrar sin elegir una.'),
          ),
          for (final a in accounts)
            ListTile(
              leading: Text(a.icon, style: const TextStyle(fontSize: 26)),
              title: Text(a.name),
              subtitle: Text(a.kind.label),
              onTap: () => _showAccountEditor(context, existing: a),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: a.id == defaultId ? 'Cuenta predeterminada' : 'Hacer predeterminada',
                    icon: Icon(a.id == defaultId ? Icons.star : Icons.star_border),
                    onPressed: () => ref.read(settingsRepositoryProvider).setDefaultAccountId(a.id),
                  ),
                  IconButton(tooltip: 'Eliminar ${a.name}', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, ref, a)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _showAccountEditor(BuildContext context, {Account? existing}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccountEditor(existing: existing),
    );

class _AccountEditor extends ConsumerStatefulWidget {
  const _AccountEditor({this.existing});

  final Account? existing;

  @override
  ConsumerState<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends ConsumerState<_AccountEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late AccountKind _kind = widget.existing?.kind ?? AccountKind.bank;
  late String _icon = widget.existing?.icon ?? AccountKind.bank.defaultIcon;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final repo = ref.read(accountRepositoryProvider);
    if (widget.existing == null) {
      await repo.create(name: name, icon: _icon, kind: _kind);
    } else {
      await repo.update(widget.existing!.id, name: name, icon: _icon, kind: _kind);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Nueva cuenta' : 'Editar cuenta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre (p. ej. Banco Popular)'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final k in AccountKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      // Si el icono era el de tipo anterior, acompaña al nuevo tipo.
                      if (_icon == _kind.defaultIcon) _icon = k.defaultIcon;
                      _kind = k;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            EmojiGrid(selected: _icon, onSelected: (e) => setState(() => _icon = e)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('GUARDAR')),
          ],
        ),
      ),
    );
  }
}
