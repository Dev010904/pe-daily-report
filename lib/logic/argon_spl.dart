import '../models/day_data.dart';
import '../models/gas.dart';
import 'stock.dart';

/// "AR SPL" was removed as a gas (2026-10-29, the user's request): every
/// AR SPL cylinder counts as ARGON from now on, and the entries it was used
/// in get the remark "ARGON SPL".
///
/// Old records are merged here, exactly: plain numbers are added together,
/// and a hand-corrected start of day (opening stock, at a plant, damaged)
/// becomes the sum of what each of the two gases really started with, so
/// the ARGON stock is AR SPL + ARGON on every day.
const String kSpl = 'AR_SPL';
const String kComm = 'AR_COMM';

/// The remark written on lines that held AR SPL.
const String kSplRemark = 'ARGON SPL';

bool _mentions(Map<String, dynamic> m) => m.containsKey(kSpl);

/// True when any of these records still use AR SPL.
bool daysUseSpl(Map<String, DayData> days) => days.values.any(_dayUsesSpl);

bool _dayUsesSpl(DayData d) {
  final meta = d.metaJson();
  bool deep(Object? v) =>
      v is Map && (v.containsKey(kSpl) || v.values.any(deep));
  if (deep(meta)) return true;
  return d.entries.any(entryUsesSpl);
}

bool entryUsesSpl(Entry e) =>
    _mentions(e.full) ||
    _mentions(e.empty) ||
    _mentions(e.loanFull) ||
    _mentions(e.loanEmpty);

void _addInto(Map<String, int> m) {
  final v = m.remove(kSpl);
  if (v == null || v == 0) return;
  m[kComm] = (m[kComm] ?? 0) + v;
  if (m[kComm] == 0) m.remove(kComm);
}

void _addPlants(PlantQty m) {
  final spl = m.remove(kSpl);
  if (spl == null) return;
  final comm = m[kComm] ??= {};
  spl.forEach((p, v) => comm[p] = (comm[p] ?? 0) + v);
  comm.removeWhere((_, v) => v == 0);
  if (comm.isEmpty) m.remove(kComm);
}

/// A hand-corrected start: (ARGON's start) + (AR SPL's start); dropped when
/// it equals what would come on its own from the day before.
void _override(Map<String, int> o, int autoComm, int autoSpl) {
  if (!o.containsKey(kSpl) && !o.containsKey(kComm)) return;
  final v = (o[kComm] ?? autoComm) + (o[kSpl] ?? autoSpl);
  o.remove(kSpl);
  if (v == autoComm + autoSpl) {
    o.remove(kComm);
  } else {
    o[kComm] = v;
  }
}

String _remark(int full, int empty, bool alone) {
  if (alone) return kSplRemark;
  return '$kSplRemark: ${[if (full > 0) '$full full', if (empty > 0) '$empty empty'].join(', ')}';
}

String _join(String? a, String b) =>
    (a == null || a.trim().isEmpty) ? b : '$a; $b';

/// The entry with AR SPL counted as ARGON and the remark added.
Entry mergeSplEntry(Entry src) {
  final e = src.copy();
  if (!entryUsesSpl(e)) return e;
  final f = e.full[kSpl] ?? 0, m = e.empty[kSpl] ?? 0;
  if (f != 0 || m != 0) {
    final alone = (e.full[kComm] ?? 0) == 0 && (e.empty[kComm] ?? 0) == 0;
    e.remarks[kComm] = _join(e.remarks[kComm], _remark(f, m, alone));
  }
  _addInto(e.full);
  _addInto(e.empty);
  // Loan lines: same, per plant.
  for (final plant in {
    ...?e.loanFull[kSpl]?.keys,
    ...?e.loanEmpty[kSpl]?.keys,
  }) {
    final lf = e.loanFull[kSpl]?[plant] ?? 0,
        le = e.loanEmpty[kSpl]?[plant] ?? 0;
    final alone =
        (e.loanFull[kComm]?[plant] ?? 0) == 0 &&
        (e.loanEmpty[kComm]?[plant] ?? 0) == 0;
    final code = '$kComm|$plant';
    e.remarks[code] = _join(e.remarks[code], _remark(lf, le, alone));
  }
  _addPlants(e.loanFull);
  _addPlants(e.loanEmpty);
  return e;
}

/// Starting stock of a company, AR SPL counted as ARGON.
Map<String, int> mergeSplOpening(Map<String, int> opening) {
  final m = Map.of(opening);
  _addInto(m);
  return m;
}

List<int> _stepsSum(List<int> a, List<int> b) => [...a, ...b];

/// Every day with AR SPL counted as ARGON. [days] are the records as saved
/// (with AR SPL); they are not changed.
Map<String, DayData> mergeSplDays(Map<String, DayData> days) {
  if (!daysUseSpl(days)) return days;
  // The stock with AR SPL as its own gas, for the starts of each day.
  final raw = StockBook(days, gases: [...kGases, kRetiredArgonSpl]);
  final out = <String, DayData>{};
  for (final entry in days.entries) {
    final date = entry.key;
    final src = entry.value;
    final d = src.copy();
    final s = raw.dayStock(date);
    final comm = s.row(kComm), spl = s.row(kSpl);

    // Filling (with its steps).
    if ((d.filling[kSpl] ?? 0) != 0) {
      final steps = _stepsSum(d.fillingStepsOf(kComm), d.fillingStepsOf(kSpl));
      d.filling.remove(kSpl);
      d.fillingSteps.remove(kSpl);
      d.setFillingSteps(kComm, steps);
    } else {
      d.filling.remove(kSpl);
      d.fillingSteps.remove(kSpl);
    }

    // Sent to / filled back from plants (with their steps).
    for (final sent in [true, false]) {
      final totals = sent ? d.plantSent : d.plantFilled;
      final steps = sent ? d.plantSentSteps : d.plantFilledSteps;
      final plants = {...?totals[kSpl]?.keys};
      final merged = <String, List<int>>{
        for (final p in plants)
          p: _stepsSum(
            sent ? d.sentStepsOf(kComm, p) : d.filledStepsOf(kComm, p),
            sent ? d.sentStepsOf(kSpl, p) : d.filledStepsOf(kSpl, p),
          ),
      };
      totals.remove(kSpl);
      steps.remove(kSpl);
      for (final p in plants) {
        final all = merged[p]!;
        final total = all.fold(0, (a, b) => a + b);
        if (total != 0) (totals[kComm] ??= {})[p] = total;
        if (all.length > 1) {
          (steps[kComm] ??= {})[p] = all;
        } else {
          steps[kComm]?.remove(p);
          if (steps[kComm]?.isEmpty ?? false) steps.remove(kComm);
        }
      }
    }

    // Hand-corrected starts.
    _override(d.openFull, comm.autoOpenFull, spl.autoOpenFull);
    _override(d.openEmpty, comm.autoOpenGodown, spl.autoOpenGodown);
    _override(d.openDamagedGas, comm.autoDamagedOpen, spl.autoDamagedOpen);
    if (d.openPlant.containsKey(kSpl) || d.openPlant.containsKey(kComm)) {
      int autoAt(StockRow r, String p) {
        for (final l in r.plantLines) {
          if (l.plantId == p) return l.autoOpen;
        }
        return 0;
      }

      final c = d.openPlant[kComm] ?? {}, sp = d.openPlant[kSpl] ?? {};
      final merged = <String, int>{};
      for (final p in {...c.keys, ...sp.keys}) {
        final ac = autoAt(comm, p), as = autoAt(spl, p);
        final v = (c[p] ?? ac) + (sp[p] ?? as);
        if (v != ac + as) merged[p] = v;
      }
      d.openPlant.remove(kSpl);
      if (merged.isEmpty) {
        d.openPlant.remove(kComm);
      } else {
        d.openPlant[kComm] = merged;
      }
    }

    // Plain numbers.
    if (d.plant != null) _addPlants(d.plant!);
    _addInto(d.damagedEmpty);
    _addInto(d.damagedFull);
    _addInto(d.repaired);
    _addPlants(d.loanIn);
    _addPlants(d.loanBackEmpty);
    _addPlants(d.loanBackFull);
    d.entries = [for (final e in d.entries) mergeSplEntry(e)];
    out[date] = d;
  }
  return out;
}
