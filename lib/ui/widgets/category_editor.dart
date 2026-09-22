import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import 'emoji_grid.dart';

/// Hoja para crear (`existing == null`) o editar una categoría.
Future<void> showCategoryEditor(BuildContext context, {required TxType type, Category? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryEditor(type: type, existing: existing),
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({required this.type, this.existing});

  final TxType type;
  final Category? existing;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? (widget.type.isExpense ? '🛒' : '💰');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final repo = ref.read(categoryRepositoryProvider);
    if (widget.existing == null) {
      await repo.create(name: name, icon: _icon, type: widget.type);
    } else {
      await repo.update(widget.existing!.id, name: name, icon: _icon);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? 'Editar categoría' : 'Nueva categoría de ${widget.type.pluralLabel.toLowerCase()}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(_icon, style: const TextStyle(fontSize: 30)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: !editing,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    onSubmitted: (_) => _save(),
                  ),
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
