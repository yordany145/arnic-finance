import 'package:intl/intl.dart';

/// Locale de la app. RD usa fechas/números en español.
const kLocale = 'es_DO';

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "HOY", "AYER" o "Lunes 15 de septiembre" (con año si no es el actual).
String dayHeader(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'HOY';
  if (diff == 1) return 'AYER';
  final pattern = d.year == today.year ? "EEEE d 'de' MMMM" : "EEEE d 'de' MMMM 'de' y";
  return _capitalize(DateFormat(pattern, kLocale).format(d));
}

String shortDate(DateTime d) => DateFormat("d 'de' MMM", kLocale).format(d).replaceAll('.', '');

String shortDateWithYear(DateTime d) => DateFormat("d MMM y", kLocale).format(d).replaceAll('.', '');

String timeLabel(DateTime d) => DateFormat('h:mm a', kLocale).format(d).replaceAll('.', '').replaceAll(' ', ' ');

/// "Hoy 2:32 PM", "Ayer 9:10 AM", "15 sep 2:32 PM".
String dateTimeLabel(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final prefix = diff == 0 ? 'Hoy' : diff == 1 ? 'Ayer' : shortDate(d);
  return '$prefix · ${timeLabel(d)}';
}
