import 'package:intl/intl.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

/// Storage key, e.g. 2026-10-12. Sorts correctly as text.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String k) {
  final parts = k.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// 12-10-2026
String fmtDmy(DateTime d) => DateFormat('dd-MM-yyyy').format(d);

/// Mon, 12 Oct 2026
String fmtLong(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

/// 12 Oct
String fmtShort(DateTime d) => DateFormat('d MMM').format(d);

/// Monday
String fmtWeekday(DateTime d) => DateFormat('EEEE').format(d);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Number of calendar days from [a] to [b], counting both ends.
int daysInclusive(DateTime a, DateTime b) =>
    DateTime.utc(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime.utc(a.year, a.month, a.day)).inDays +
    1;

final NumberFormat _money = NumberFormat('#,##,##0.##', 'en_IN');

/// ₹2,50,000 style amount
String fmtMoney(double v) => '₹${_money.format(v)}';

/// Same without the rupee sign (for typing back into a field).
String fmtAmountPlain(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// "1 day", "3 days"
String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
