import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/category_editor.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categorías'),
          bottom: const TabBar(tabs: [Tab(text: 'Gastos'), Tab(text: 'Ingresos')]),
        ),
        body: const TabBarView(children: [_CategoryList(TxType.expense), _CategoryList(TxType.income)]),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList(this.type);

  final TxType type;

  Future<void> _delete(BuildContext context, WidgetRef ref, Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('¿Eliminar "${c.name}"?'),
        content: const Text('Los movimientos que ya registraste con esta categoría no se borran: conservan su nombre en el historial.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(categoryRepositoryProvider).delete(c.id);
    } on StateError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(type)).value ?? const <Category>[];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final c in categories)
          ListTile(
            leading: Text(c.icon, style: const TextStyle(fontSize: 26)),
            title: Text(c.name),
            onTap: () => showCategoryEditor(context, type: type, existing: c),
            trailing: IconButton(
              tooltip: 'Eliminar ${c.name}',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref, c),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.tonalIcon(
            onPressed: () => showCategoryEditor(context, type: type),
            icon: const Icon(Icons.add),
            label: const Text('Nueva categoría'),
          ),
        ),
      ],
    );
  }
}
