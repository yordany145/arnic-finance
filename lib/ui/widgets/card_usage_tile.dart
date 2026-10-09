import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';

final _dayFormat = DateFormat('d MMM', 'es');

Color cardBarColor(ColorScheme scheme, double ratio) {
  if (ratio >= 1) return scheme.error;
  if (ratio >= 0.8) return Colors.orange.shade700;
  return scheme.primary;
}

String dueDaysLabel(DateTime due, DateTime now) {
  final days = due.difference(DateTime(now.year, now.month, now.day)).inDays;
  return switch (days) { 0 => 'hoy', 1 => 'mañana', _ => 'en $days días' };
}

/// Resumen compacto de una tarjeta de crédito para Inicio: consumo del ciclo frente al límite,
/// lo disponible y cuándo toca pagar. Es lo que más se consulta, por eso no queda enterrado en Ajustes.
class CardUsageTile extends ConsumerWidget {
  const CardUsageTile({super.key, required this.account, this.onTap});

  final Account account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currency = ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
    final usage = ref.watch(cardUsageProvider(account.id)).value;
    final now = ref.watch(nowProvider);
    final ratio = usage?.ratio;
    final due = usage?.due;

    final String headline;
    if (usage == null) {
      headline = '…';
    } else if (usage.limitMinor == null) {
      headline = '${formatMoney(usage.spentMinor, currency)} consumido';
    } else {
      headline = '${formatMoney(usage.spentMinor, currency)} de ${formatMoney(usage.limitMinor!, currency)}';
    }
    final details = <String>[
      if (usage?.limitMinor == null && usage != null) 'Toca para poner el límite',
      if (ratio != null) (ratio >= 1 ? 'Límite alcanzado' : 'Disponible ${formatMoney(usage!.availableMinor!, currency)}'),
      if (due != null) 'Pago ${_dayFormat.format(due)} (${dueDaysLabel(due, now)})',
    ];

    return Semantics(
      container: true,
      label: '${account.name}. $headline. ${details.join('. ')}',
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(account.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(account.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    if (ratio != null)
                      Text('${(ratio * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: cardBarColor(scheme, ratio))),
                  ],
                ),
                const SizedBox(height: 10),
                if (ratio != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0, 1).toDouble(),
                      minHeight: 8,
                      color: cardBarColor(scheme, ratio),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(headline, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (details.isNotEmpty) Text(details.join(' · '), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
