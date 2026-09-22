import '../domain/models.dart';
import 'database.dart';

Category categoryFromRow(CategoryRow r) => Category(
      id: r.id,
      name: r.name,
      icon: r.icon,
      type: r.type,
      sortOrder: r.sortOrder,
      isDeleted: r.deletedAt != null,
    );

Account accountFromRow(AccountRow r) => Account(
      id: r.id,
      name: r.name,
      icon: r.icon,
      kind: r.kind,
      sortOrder: r.sortOrder,
      isDeleted: r.deletedAt != null,
    );

Movement movementFromRows(TxRow t, CategoryRow c, AccountRow a) => Movement(
      id: t.id,
      type: t.type,
      amountMinor: t.amountMinor,
      category: categoryFromRow(c),
      account: accountFromRow(a),
      occurredAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAt),
      note: t.note,
    );
