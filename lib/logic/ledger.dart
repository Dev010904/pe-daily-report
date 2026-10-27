import '../models/day_data.dart';
import '../models/gas.dart';
import 'stock.dart';

/// An entry together with its date.
class DatedEntry {
  final String date;
  final Entry entry;
  const DatedEntry(this.date, this.entry);
}

int compareDated(DatedEntry a, DatedEntry b) {
  final d = a.date.compareTo(b.date);
  if (d != 0) return d;
  final s = a.entry.sort.compareTo(b.entry.sort);
  return s != 0 ? s : a.entry.id.compareTo(b.entry.id);
}

/// One supply/return line in a company's statement with the balance after it.
class LedgerLine {
  final String date;
  final Entry entry;
  final Map<String, int> after;
  const LedgerLine(this.date, this.entry, this.after);
}

/// A company's cylinder statement for a period.
/// Balance = starting balance + full supplied − empty received.
class CompanyLedger {
  final NamedItem company;

  /// Balance at the start of the period (starting balance + earlier days).
  final Map<String, int> start;
  final List<LedgerLine> lines;

  /// Balance at the end of the period.
  final Map<String, int> end;

  const CompanyLedger(this.company, this.start, this.lines, this.end);

  Map<String, int> get supplied => _sum((e) => e.full);
  Map<String, int> get received => _sum((e) => e.empty);

  Map<String, int> _sum(Map<String, int> Function(Entry) pick) {
    final m = <String, int>{};
    for (final l in lines) {
      pick(l.entry).forEach((k, v) => m[k] = (m[k] ?? 0) + v);
    }
    return m;
  }

  /// Gases that appear anywhere in this statement, in the standard order.
  List<Gas> get gases => [
    for (final g in kGases)
      if ((start[g.code] ?? 0) != 0 ||
          (end[g.code] ?? 0) != 0 ||
          lines.any(
            (l) =>
                (l.entry.full[g.code] ?? 0) != 0 ||
                (l.entry.empty[g.code] ?? 0) != 0,
          ))
        g,
  ];

  int get totalEnd => end.values.fold(0, (a, b) => a + b);
}

Map<String, int> _clean(Map<String, int> m) => {
  for (final e in m.entries)
    if (e.value != 0) e.key: e.value,
};

/// Builds a statement from the company's entries (any order).
CompanyLedger buildLedger(
  NamedItem company,
  List<DatedEntry> entries, {
  String? from,
  String? to,
}) {
  final list = [...entries]..sort(compareDated);
  final bal = Map<String, int>.of(company.opening);
  Map<String, int>? start;
  final lines = <LedgerLine>[];
  for (final d in list) {
    if (to != null && d.date.compareTo(to) > 0) break;
    if (from != null && d.date.compareTo(from) < 0) {
      _apply(bal, d.entry);
      continue;
    }
    start ??= _clean(bal);
    _apply(bal, d.entry);
    lines.add(LedgerLine(d.date, d.entry, _clean(bal)));
  }
  return CompanyLedger(company, start ?? _clean(bal), lines, _clean(bal));
}

void _apply(Map<String, int> bal, Entry e) {
  e.full.forEach((k, v) => bal[k] = (bal[k] ?? 0) + v);
  e.empty.forEach((k, v) => bal[k] = (bal[k] ?? 0) - v);
}

/// Lowest balance per gas reached from [fromDate] on (including the balance
/// carried into that date), plus where it first went below zero.
({Map<String, int> min, Map<String, DatedEntry> firstNegative}) _lows(
  Map<String, int> opening,
  List<DatedEntry> sorted,
  String fromDate,
) {
  final bal = Map<String, int>.of(opening);
  final mins = <String, int>{};
  final firstNeg = <String, DatedEntry>{};
  void note(DatedEntry? at) {
    for (final g in kGases) {
      final v = bal[g.code] ?? 0;
      if (v < (mins[g.code] ?? 0)) mins[g.code] = v;
      if (v < 0 && at != null) firstNeg.putIfAbsent(g.code, () => at);
    }
  }

  var started = false;
  for (final d in sorted) {
    if (!started && d.date.compareTo(fromDate) >= 0) {
      started = true;
      note(null);
    }
    _apply(bal, d.entry);
    if (started) note(d);
  }
  if (!started) note(null);
  return (min: mins, firstNegative: firstNeg);
}

/// Checks that no company would hold fewer than zero cylinders of any gas
/// after a change. Only problems made worse by the change are reported.
List<StockProblem> companyProblems({
  required NamedItem company,
  required List<DatedEntry> before,
  required List<DatedEntry> after,
  Map<String, int>? openingAfter,
  String fromDate = '',
}) {
  final oldSorted = [...before]..sort(compareDated);
  final newSorted = [...after]..sort(compareDated);
  final o = _lows(company.opening, oldSorted, fromDate);
  final n = _lows(openingAfter ?? company.opening, newSorted, fromDate);
  final out = <StockProblem>[];
  for (final g in kGases) {
    final nv = n.min[g.code] ?? 0;
    final ov = o.min[g.code] ?? 0;
    if (nv >= 0 || nv >= ov) continue;
    final at = n.firstNegative[g.code];
    final date = at?.date ?? fromDate;
    final String message;
    if (at == null) {
      message =
          '${company.name} – ${g.label}: starting stock would '
          'leave them with $nv (below zero).';
    } else {
      final balAfter = _balanceAfter(
        openingAfter ?? company.opening,
        newSorted,
        at,
        g.code,
      );
      final empty = at.entry.empty[g.code] ?? 0;
      final have = balAfter + empty;
      message =
          '${company.name} – ${g.label}: they have only $have with '
          'them, but $empty empty received (short by ${-balAfter}). If they '
          'had cylinders before using the app, set their Starting Stock '
          'in the Companies tab.';
    }
    out.add(StockProblem(date, g, message));
  }
  return out;
}

int _balanceAfter(
  Map<String, int> opening,
  List<DatedEntry> sorted,
  DatedEntry at,
  String gas,
) {
  final bal = Map<String, int>.of(opening);
  for (final d in sorted) {
    _apply(bal, d.entry);
    if (identical(d, at)) break;
  }
  return bal[gas] ?? 0;
}
