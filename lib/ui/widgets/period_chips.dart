import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_labels.dart';
import '../../domain/date_range.dart';
import '../../domain/enums.dart';
import '../../state/providers.dart';

/// Hoy · Ayer · Esta semana · Este mes · Rango · Todo.
/// "Rango" abre el selector de fechas (p. ej. 15 sep → 14 oct, ambos inclusivos).
class PeriodChips extends ConsumerWidget {
  const PeriodChips({super.key});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = ref.read(nowProvider);
    final current = ref.read(historyFilterProvider).customRange;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: current == null ? null : DateTimeRange(start: current.start, end: current.lastDay),
      helpText: 'Elige el período',
      saveText: 'Aplicar',
      locale: const Locale('es', 'DO'),
    );
    if (picked != null) {
      ref.read(historyFilterProvider.notifier).setCustomRange(DateRange.days(picked.start, picked.end));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(historyFilterProvider);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final p in PeriodPreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: f.preset == p,
                showCheckmark: false,
                label: Text(
                  p == PeriodPreset.custom && f.customRange != null
                      ? '${shortDate(f.customRange!.start)} – ${shortDate(f.customRange!.lastDay)}'
                      : p.label,
                ),
                avatar: p == PeriodPreset.custom ? const Icon(Icons.date_range, size: 18) : null,
                onSelected: (_) {
                  if (p == PeriodPreset.custom) {
                    _pickRange(context, ref);
                  } else {
                    ref.read(historyFilterProvider.notifier).setPreset(p);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
