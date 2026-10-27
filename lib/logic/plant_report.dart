/// What went to and came from one filling plant on one day (or, grouped,
/// in one month or business year): empties sent and filled cylinders back,
/// by gas.
class PlantDay {
  /// yyyy-MM-dd for a day; yyyy-MM for a month; yyyy for a business year
  /// starting 1 April of that year.
  final String key;
  final Map<String, int> sent;
  final Map<String, int> filled;

  /// Loan cylinders taken from the plant / given back to it.
  final Map<String, int> loanIn;
  final Map<String, int> loanBack;

  PlantDay(
    this.key,
    this.sent,
    this.filled, {
    Map<String, int>? loanIn,
    Map<String, int>? loanBack,
  }) : loanIn = loanIn ?? {},
       loanBack = loanBack ?? {};

  int get totalSent => sent.values.fold(0, (a, b) => a + b);
  int get totalFilled => filled.values.fold(0, (a, b) => a + b);
  int get totalLoanIn => loanIn.values.fold(0, (a, b) => a + b);
  int get totalLoanBack => loanBack.values.fold(0, (a, b) => a + b);
  bool get hasLoan => loanIn.isNotEmpty || loanBack.isNotEmpty;

  void _add(PlantDay d) {
    d.sent.forEach((gas, v) => sent[gas] = (sent[gas] ?? 0) + v);
    d.filled.forEach((gas, v) => filled[gas] = (filled[gas] ?? 0) + v);
    d.loanIn.forEach((gas, v) => loanIn[gas] = (loanIn[gas] ?? 0) + v);
    d.loanBack.forEach((gas, v) => loanBack[gas] = (loanBack[gas] ?? 0) + v);
  }
}

enum PlantGroup { day, month, year }

/// Business year (April to March) a yyyy-MM-dd date belongs to.
int businessYearOf(String date) {
  final y = int.parse(date.substring(0, 4)),
      m = int.parse(date.substring(5, 7));
  return m >= 4 ? y : y - 1;
}

/// Adds the days up by month or business year (newest first), or keeps them
/// day by day (newest first).
List<PlantDay> groupPlantDays(List<PlantDay> days, PlantGroup by) {
  if (by == PlantGroup.day) return days.reversed.toList();
  final groups = <String, PlantDay>{};
  for (final d in days) {
    final k = by == PlantGroup.month
        ? d.key.substring(0, 7)
        : '${businessYearOf(d.key)}';
    (groups[k] ??= PlantDay(k, {}, {}))._add(d);
  }
  final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) groups[k]!];
}

/// The whole period added up.
PlantDay totalOf(List<PlantDay> days) {
  final t = PlantDay('total', {}, {});
  for (final d in days) {
    t._add(d);
  }
  return t;
}
