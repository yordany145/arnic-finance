import 'package:flutter/material.dart';

/// Teclado numérico grande, pensado para una mano. Evita levantar el teclado
/// del sistema (más lento y ocupa media pantalla). Emite `0-9`, `.` o `⌫`.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey, this.keyHeight = 58});

  final ValueChanged<String> onKey;
  final double keyHeight;

  static const _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: (MediaQuery.sizeOf(context).width - 32) / 3 / keyHeight,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final k in _keys)
          Semantics(
            button: true,
            label: k == '⌫' ? 'Borrar' : (k == '.' ? 'Punto decimal' : k),
            child: Material(
              color: k == '⌫' ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onKey(k),
                child: Center(
                  child: k == '⌫'
                      ? Icon(Icons.backspace_outlined, color: scheme.onSecondaryContainer)
                      : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
