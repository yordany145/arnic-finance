import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import 'category_editor.dart';

/// Categorías en una rejilla de 3 columnas con posiciones fijas: se ven todas a la vez junto al
/// teclado (con chips que se acomodan, la mitad quedaba oculta y era fácil tocar una vecina por error).
/// Las más usadas salen primero, así la habitual ya está a mano (y preseleccionada) al abrir el formulario.
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

  static const _columns = 3;
  static const _tileHeight = 46.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      for (final c in categories)
        _Tile(
          selected: c.id == selectedId,
          semanticLabel: c.name,
          onTap: () => onSelected(c),
          // Los nombres largos ("Entretenimiento", "Suscripciones") se achican en vez de cortarse con "…".
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(c.name, maxLines: 1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      _Tile(
        selected: false,
        semanticLabel: 'Nueva categoría',
        onTap: () => showCategoryEditor(context, type: type),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 18, color: scheme.primary),
            const SizedBox(width: 4),
            Text('Nueva', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.primary)),
          ],
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        return GridView.count(
          crossAxisCount: _columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: _gap,
          crossAxisSpacing: _gap,
          childAspectRatio: width / _tileHeight,
          children: tiles,
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.selected, required this.onTap, required this.child, required this.semanticLabel});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: child),
        ),
      ),
    );
  }
}
