import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import 'category_editor.dart';

/// Categorías como chips grandes. Las más usadas salen primero, así la habitual
/// ya está a mano (y preseleccionada) al abrir el formulario.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.type,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<Category> onSelected;
  final TxType type;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in categories)
          ChoiceChip(
            selected: c.id == selectedId,
            showCheckmark: false,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            label: Text('${c.icon}  ${c.name}', style: const TextStyle(fontSize: 16)),
            onSelected: (_) => onSelected(c),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 20),
          labelPadding: const EdgeInsets.symmetric(vertical: 6),
          label: const Text('Nueva', style: TextStyle(fontSize: 16)),
          onPressed: () => showCategoryEditor(context, type: type),
        ),
      ],
    );
  }
}
