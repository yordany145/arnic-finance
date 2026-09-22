import 'package:flutter/material.dart';

/// Colores del logo de Arnic (azul profundo y turquesa).
const kBrandBlue = Color(0xFF185EA8);
const kBrandTeal = Color(0xFF3FC5D0);

/// Colores semánticos de dinero. Además del color, el signo (+/−) siempre
/// acompaña al monto, para no depender sólo del color.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  const MoneyColors({required this.expense, required this.income});

  final Color expense;
  final Color income;

  @override
  MoneyColors copyWith({Color? expense, Color? income}) =>
      MoneyColors(expense: expense ?? this.expense, income: income ?? this.income);

  @override
  MoneyColors lerp(ThemeExtension<MoneyColors>? other, double t) => other is! MoneyColors
      ? this
      : MoneyColors(expense: Color.lerp(expense, other.expense, t)!, income: Color.lerp(income, other.income, t)!);
}

extension MoneyColorsX on BuildContext {
  MoneyColors get money => Theme.of(this).extension<MoneyColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: kBrandBlue, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [
      MoneyColors(
        expense: dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
        income: dark ? const Color(0xFF6FE0A8) : const Color(0xFF1B7F52),
      ),
    ],
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0, centerTitle: false),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
