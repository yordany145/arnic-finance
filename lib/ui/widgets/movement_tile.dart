import 'package:flutter/material.dart';

import '../../core/date_labels.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/bank_movement.dart';
import '../../domain/models.dart';

class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.movement,
    required this.currency,
    required this.onTap,
    this.showAccount = false,
    this.now,
  });

  final Movement movement;
  final String currency;
  final VoidCallback onTap;
  final bool showAccount;

  /// Si se indica, el subtítulo muestra fecha y hora (lista de recientes).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = movement.type.isExpense ? context.money.expense : context.money.income;
    final fromBank = isBankMovement(movement);
    final parts = <String>[
      if (now != null) dateTimeLabel(movement.occurredAt, now!) else timeLabel(movement.occurredAt),
      if (showAccount) '${movement.account.icon} ${movement.account.name}',
      if (movement.note != null) (bankMerchant(movement) ?? movement.note!),
    ];
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: scheme.surfaceContainerHigh,
        child: Text(movement.category.icon, style: const TextStyle(fontSize: 24)),
      ),
      title: Row(
        children: [
          Flexible(child: Text(movement.category.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
          if (fromBank) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Registrado solo desde el aviso del banco',
              child: Icon(Icons.account_balance, size: 15, color: scheme.primary, semanticLabel: 'Registrado desde el aviso del banco'),
            ),
          ],
        ],
      ),
      subtitle: Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatMoney(movement.signedMinor, currency, showSign: true),
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
