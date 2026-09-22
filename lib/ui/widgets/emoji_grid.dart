import 'package:flutter/material.dart';

import '../../core/emoji_catalog.dart';

/// Cuadrícula de emojis + campo para escribir uno distinto con el teclado del sistema.
class EmojiGrid extends StatefulWidget {
  const EmojiGrid({super.key, required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<EmojiGrid> createState() => _EmojiGridState();
}

class _EmojiGridState extends State<EmojiGrid> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in kEmojiCatalog)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onSelected(e),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: e == widget.selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                    border: e == widget.selected ? Border.all(color: scheme.primary, width: 2) : null,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _custom,
          decoration: const InputDecoration(labelText: 'Otro emoji (teclado del sistema)', isDense: true),
          onChanged: (v) {
            final chars = v.characters;
            if (chars.isNotEmpty) widget.onSelected(chars.last);
          },
        ),
      ],
    );
  }
}
