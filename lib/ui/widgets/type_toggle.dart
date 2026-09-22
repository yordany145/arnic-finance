import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/enums.dart';

/// [ GASTO ] [ INGRESO ] — dos botones grandes.
class TypeToggle extends StatelessWidget {
  const TypeToggle({super.key, required this.value, required this.onChanged});

  final TxType value;
  final ValueChanged<TxType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final t in TxType.values) ...[
          Expanded(child: _Segment(type: t, selected: value == t, onTap: () => onChanged(t))),
          if (t == TxType.expense) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.type, required this.selected, required this.onTap});

  final TxType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = type.isExpense ? context.money.expense : context.money.income;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color.withValues(alpha: 0.16) : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Center(
              child: Text(
                type.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: selected ? color : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
