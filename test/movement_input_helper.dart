import 'package:arnic_finance/data/seed.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';

class MovementInputHelper {
  static MovementInput make(String type, int minor, String cat, DateTime at) => MovementInput(
        type: type == 'income' ? TxType.income : TxType.expense,
        amountMinor: minor,
        categoryId: cat,
        accountId: kDefaultAccountId,
        occurredAt: at,
      );
}
