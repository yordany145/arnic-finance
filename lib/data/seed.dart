import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'database.dart';
import 'settings_keys.dart';

/// IDs estables para los datos iniciales: dos dispositivos que siembren la base
/// por separado producirán las mismas filas (facilita una sincronización futura).
const kDefaultAccountId = 'acc_cash';

const _expenseSeed = <(String, String, String)>[
  ('exp_food', 'Comida', '🍔'),
  ('exp_transport', 'Transporte', '🚌'),
  ('exp_fuel', 'Combustible', '⛽'),
  ('exp_shopping', 'Compras', '🛍️'),
  ('exp_fun', 'Entretenimiento', '🎬'),
  ('exp_health', 'Salud', '💊'),
  ('exp_home', 'Hogar', '🏠'),
  ('exp_services', 'Servicios', '💡'),
  ('exp_education', 'Educación', '📚'),
  ('exp_subscriptions', 'Suscripciones', '🔁'),
  ('exp_other', 'Otros', '📦'),
];

const _incomeSeed = <(String, String, String)>[
  ('inc_salary', 'Salario', '💰'),
  ('inc_business', 'Negocio', '🏪'),
  ('inc_transfer', 'Transferencia', '🏦'),
  ('inc_gift', 'Regalo', '🎁'),
  ('inc_other', 'Otros', '📦'),
];

Future<void> seedDefaults(AppDatabase db) async {
  final now = DateTime.now().millisecondsSinceEpoch;

  await db.batch((b) {
    b.insert(
      db.accounts,
      AccountsCompanion.insert(
        id: kDefaultAccountId,
        name: 'Efectivo',
        icon: AccountKind.cash.defaultIcon,
        kind: AccountKind.cash,
        createdAt: now,
        updatedAt: now,
      ),
    );

    void addCategories(List<(String, String, String)> seed, TxType type) {
      for (var i = 0; i < seed.length; i++) {
        final (id, name, icon) = seed[i];
        b.insert(
          db.categories,
          CategoriesCompanion.insert(
            id: id,
            name: name,
            icon: icon,
            type: type,
            sortOrder: Value(i),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    addCategories(_expenseSeed, TxType.expense);
    addCategories(_incomeSeed, TxType.income);

    b.insert(db.appSettings, AppSettingsCompanion.insert(key: kSettingCurrencySymbol, value: kDefaultCurrencySymbol));
    b.insert(db.appSettings, AppSettingsCompanion.insert(key: kSettingDefaultAccountId, value: kDefaultAccountId));
  });
}
