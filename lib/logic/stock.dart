import '../models/day_data.dart';
import '../models/gas.dart';

/// Closing position of one gas at the end of a day.
class GasState {
  final int full;
  final int godown;

  /// plant id -> empties waiting at that plant
  final Map<String, int> plant;

  /// Damaged cylinders of this gas (they keep their gas until repaired).
  final int damaged;

  /// Loan cylinders of this gas in our godown, by the plant they belong
  /// to: full (not supplied yet) / empty (came back from companies).
  final Map<String, int> loanFull;
  final Map<String, int> loanEmpty;

  const GasState({
    this.full = 0,
    this.godown = 0,
    this.plant = const {},
    this.damaged = 0,
    this.loanFull = const {},
    this.loanEmpty = const {},
  });

  int get plantTotal => plant.values.fold(0, (a, b) => a + b);
}

/// Empties of one gas at one filling plant during the day:
/// at plant = start + sent today − filled back today.
class PlantLine {
  final String plantId;
  final int open;

  /// What the start would be without a hand correction.
  final int autoOpen;
  final List<int> sentSteps;
  final List<int> filledSteps;
  final int close;

  const PlantLine(
    this.plantId, {
    required this.open,
    required this.autoOpen,
    this.sentSteps = const [],
    this.filledSteps = const [],
    required this.close,
  });

  int get sent => sentSteps.fold(0, (a, b) => a + b);
  int get filled => filledSteps.fold(0, (a, b) => a + b);

  bool get openEdited => open != autoOpen;

  /// "40 + 10 − 11 − 3 = 36" (every step of the day), or just the number
  /// when nothing moved. Days written the old way show "8 → 5".
  String calcText({bool ascii = false, String arrow = '→'}) {
    final minus = ascii ? '-' : '−';
    if (sentSteps.isEmpty && filledSteps.isEmpty) {
      return open == close ? '$close' : '$open $arrow $close';
    }
    final b = StringBuffer('$open');
    for (final x in sentSteps) {
      b.write(' + $x');
    }
    for (final x in filledSteps) {
      b.write(' $minus $x');
    }
    return '$b = $close';
  }
}

/// Loan cylinders of one gas from one plant during the day.
/// In godown full = start + taken − supplied − given back full.
/// In godown empty = start + empty received from companies − given back
/// empty. With companies = supplied − empty received, over all days.
class LoanLine {
  final String plantId;
  final int openFull;
  final int taken;
  final int supplied;
  final int backFull;
  final int closeFull;
  final int openEmpty;
  final int emptyBack;
  final int backEmpty;
  final int closeEmpty;

  /// With companies at the end of the day.
  final int atCompanies;

  const LoanLine(
    this.plantId, {
    required this.openFull,
    required this.taken,
    required this.supplied,
    required this.backFull,
    required this.closeFull,
    required this.openEmpty,
    required this.emptyBack,
    required this.backEmpty,
    required this.closeEmpty,
    required this.atCompanies,
  });

  /// Still to be given back to the plant (in godown + with companies).
  int get toReturn => closeFull + closeEmpty + atCompanies;

  bool get moved =>
      taken != 0 ||
      supplied != 0 ||
      backFull != 0 ||
      emptyBack != 0 ||
      backEmpty != 0;

  /// "0 + 20 − 18 = 2" (full in godown), or just the number.
  String fullCalcText({bool ascii = false}) {
    if (taken == 0 && supplied == 0 && backFull == 0) return '$closeFull';
    final minus = ascii ? '-' : '−';
    final b = StringBuffer('$openFull');
    if (taken != 0) b.write(' + $taken');
    if (supplied != 0) b.write(' $minus $supplied');
    if (backFull != 0) b.write(' $minus $backFull');
    return '$b = $closeFull';
  }

  /// "0 + 4 − 4 = 0" (empty in godown), or just the number.
  String emptyCalcText({bool ascii = false}) {
    if (emptyBack == 0 && backEmpty == 0) return '$closeEmpty';
    final minus = ascii ? '-' : '−';
    final b = StringBuffer('$openEmpty');
    if (emptyBack != 0) b.write(' + $emptyBack');
    if (backEmpty != 0) b.write(' $minus $backEmpty');
    return '$b = $closeEmpty';
  }
}

/// One row of the daily stock table.
class StockRow {
  final Gas gas;
  final int openFull;
  final int autoOpenFull;

  /// All filled cylinders received today (the Filling column).
  final int fill;

  /// Each filling of the day, in order (e.g. 11 and later 3).
  final List<int> fillSteps;
  final int sales;
  final int closeFull;

  final int openGodown;
  final int autoOpenGodown;
  final int received;

  /// Filled without a plant line: DA, and old entries that were taken
  /// straight from the godown empties.
  final int godownFill;

  /// Empties taken from the godown to filling plants today.
  final int sentToPlant;

  /// Each lot of empties sent to plants today.
  final List<int> sentSteps;

  /// Filled cylinders back from filling plants today.
  final int filledFromPlant;

  /// DA only: empties handed over at the plant.
  final int daGiven;
  final List<int> daGivenSteps;

  /// Declared damaged today: from the godown empties / from full stock.
  final int damagedEmpty;
  final int damagedFull;

  /// Damaged cylinders of this gas repaired today (back as empties).
  final int repaired;

  /// Damaged cylinders of this gas: at the start of the day (and without a
  /// hand correction), and at the end.
  final int damagedOpen;
  final int autoDamagedOpen;
  final int damagedClose;

  /// Old way only: change in the typed plant count (close - open).
  final int plantDelta;
  final int closeGodown;
  final List<PlantLine> plantLines;

  /// Loan cylinders of this gas, one line per plant they belong to.
  final List<LoanLine> loanLines;

  const StockRow({
    required this.gas,
    required this.openFull,
    required this.autoOpenFull,
    required this.fill,
    this.fillSteps = const [],
    required this.sales,
    required this.closeFull,
    required this.openGodown,
    required this.autoOpenGodown,
    required this.received,
    required this.godownFill,
    required this.sentToPlant,
    this.sentSteps = const [],
    required this.filledFromPlant,
    required this.daGiven,
    this.daGivenSteps = const [],
    this.damagedEmpty = 0,
    this.damagedFull = 0,
    this.repaired = 0,
    this.damagedOpen = 0,
    this.autoDamagedOpen = 0,
    this.damagedClose = 0,
    required this.plantDelta,
    required this.closeGodown,
    required this.plantLines,
    this.loanLines = const [],
  });

  bool get openFullEdited => openFull != autoOpenFull;
  bool get openEmptyEdited => openGodown != autoOpenGodown;

  /// Declared damaged today (from empty + from full).
  int get damagedIn => damagedEmpty + damagedFull;

  /// Empties of this gas at all plants at the end of the day.
  int get plantClose => plantLines.fold(0, (a, l) => a + l.close);

  /// "+11 +3" when filled in more than one go that day, else "".
  String get fillStepsText =>
      fillSteps.length > 1 ? fillSteps.map((x) => '+$x').join(' ') : '';

  /// The empty-column working, e.g. "40 − 40 = 0". Returns only the
  /// number when nothing changed today.
  List<CalcPart> emptyCalc() {
    final parts = <CalcPart>[CalcPart('$openGodown')];
    if (gas.isDA) {
      for (final x
          in (daGivenSteps.isEmpty && daGiven != 0
              ? [daGiven]
              : daGivenSteps)) {
        parts.add(CalcPart('− $x'));
      }
    } else if (godownFill != 0) {
      parts.add(CalcPart('− $godownFill'));
    }
    if (received != 0) parts.add(CalcPart('+ $received'));
    if (damagedEmpty != 0) {
      parts.add(CalcPart('− $damagedEmpty', damaged: true, label: 'damaged'));
    }
    if (repaired != 0) {
      parts.add(CalcPart('+ $repaired', damaged: true, label: 'repaired'));
    }
    if (!gas.isDA) {
      for (final x
          in (sentSteps.isEmpty && sentToPlant != 0
              ? [sentToPlant]
              : sentSteps)) {
        parts.add(CalcPart('− $x', plant: true, label: 'to plant'));
      }
    }
    if (!gas.isDA && plantDelta != 0) {
      parts.add(
        CalcPart(
          plantDelta > 0 ? '− $plantDelta' : '+ ${-plantDelta}',
          plant: true,
        ),
      );
    }
    return parts;
  }

  String emptyCalcText({bool ascii = false, bool labelPlant = false}) {
    final parts = emptyCalc();
    if (parts.length == 1) return '$closeGodown';
    final body = parts
        .map(
          (p) =>
              (ascii ? p.text.replaceAll('−', '-') : p.text) +
              ((p.plant || p.damaged) && labelPlant ? ' (${p.label})' : ''),
        )
        .join(' ');
    return '$body = $closeGodown';
  }
}

class CalcPart {
  final String text;

  /// Empties going to / coming from a filling plant.
  final bool plant;

  /// Cylinders declared damaged, or damaged ones repaired.
  final bool damaged;
  final String label;
  const CalcPart(
    this.text, {
    this.plant = false,
    this.damaged = false,
    this.label = 'plant',
  });
}

/// Which company a loan cylinder is with (old entries without a company id
/// go by name).
String loanCompanyKey(Entry e) => e.companyId ?? '#${e.company}';

/// Stock for one date.
class StockDay {
  final String date;
  final List<StockRow> rows;

  /// True when there is any saved day before this one.
  final bool hasPrevious;
  final Map<String, GasState> closing;

  /// Loan cylinders with each company at the end of the day:
  /// company key (see [loanCompanyKey]) -> gas -> plant -> qty.
  final Map<String, PlantQty> loanAtCompanies;

  const StockDay({
    required this.date,
    required this.rows,
    required this.hasPrevious,
    required this.closing,
    this.loanAtCompanies = const {},
  });

  StockRow row(String code) => rows.firstWhere((r) => r.gas.code == code);

  // Damaged cylinders, all gases together (each gas is in its row).
  int get damagedOpen => rows.fold(0, (a, r) => a + r.damagedOpen);
  int get damagedAutoOpen => rows.fold(0, (a, r) => a + r.autoDamagedOpen);
  int get damagedIn => rows.fold(0, (a, r) => a + r.damagedIn);
  int get repairedOut => rows.fold(0, (a, r) => a + r.repaired);
  int get damagedClose => rows.fold(0, (a, r) => a + r.damagedClose);
  bool get damagedOpenEdited =>
      rows.any((r) => r.damagedOpen != r.autoDamagedOpen);

  /// Declared damaged today / repaired today / damaged at the end, by gas.
  Map<String, int> get damagedToday => {
    for (final r in rows)
      if (r.damagedIn != 0) r.gas.code: r.damagedIn,
  };
  Map<String, int> get repairedToday => {
    for (final r in rows)
      if (r.repaired != 0) r.gas.code: r.repaired,
  };
  Map<String, int> get damagedStartBy => {
    for (final r in rows)
      if (r.damagedOpen != 0) r.gas.code: r.damagedOpen,
  };
  Map<String, int> get damagedCloseBy => {
    for (final r in rows)
      if (r.damagedClose != 0) r.gas.code: r.damagedClose,
  };

  bool get hasDamaged => rows.any(
    (r) =>
        r.damagedOpen != 0 ||
        r.damagedIn != 0 ||
        r.repaired != 0 ||
        r.damagedClose != 0,
  );

  /// "4 + 2 − 3 = 3" for all gases together, or just the number.
  String damagedCalcText({bool ascii = false}) {
    if (damagedIn == 0 && repairedOut == 0) return '$damagedClose';
    final b = StringBuffer('$damagedOpen');
    if (damagedIn != 0) b.write(' + $damagedIn');
    if (repairedOut != 0) {
      b.write(ascii ? ' - $repairedOut' : ' − $repairedOut');
    }
    return '$b = $damagedClose';
  }

  /// Every loan line of the day (all gases).
  List<(Gas, LoanLine)> get loanLines => [
    for (final r in rows)
      for (final l in r.loanLines) (r.gas, l),
  ];

  bool get hasLoans => rows.any((r) => r.loanLines.isNotEmpty);

  /// Loan cylinders still to be given back, all plants and gases.
  int get loanToReturn =>
      rows.fold(0, (a, r) => a + r.loanLines.fold(0, (b, l) => b + l.toReturn));
}

Map<String, int> sumFull(DayData d) {
  final m = <String, int>{};
  for (final e in d.entries) {
    e.full.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
  }
  return m;
}

Map<String, int> sumEmpty(DayData d) {
  final m = <String, int>{};
  for (final e in d.entries) {
    e.empty.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
  }
  return m;
}

int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

/// Loan cylinders supplied / received back in the day's entries.
PlantQty _sumLoan(DayData d, {required bool full}) {
  final m = <String, Map<String, int>>{};
  for (final e in d.entries) {
    (full ? e.loanFull : e.loanEmpty).forEach((gas, byPlant) {
      byPlant.forEach((plant, v) => addPlantQty(m, gas, plant, v));
    });
  }
  return m;
}

/// Loan cylinders with each company after the day's entries.
Map<String, PlantQty> _loanCompanies(Map<String, PlantQty> prev, DayData d) {
  final out = <String, PlantQty>{
    for (final e in prev.entries)
      e.key: {for (final g in e.value.entries) g.key: Map.of(g.value)},
  };
  for (final e in d.entries) {
    if (!e.hasLoan) continue;
    final co = out[loanCompanyKey(e)] ??= {};
    e.loanFull.forEach((gas, byPlant) {
      byPlant.forEach((plant, v) => addPlantQty(co, gas, plant, v));
    });
    e.loanEmpty.forEach((gas, byPlant) {
      byPlant.forEach((plant, v) => addPlantQty(co, gas, plant, -v));
    });
  }
  // Drop zeros.
  for (final co in out.values) {
    for (final g in co.values) {
      g.removeWhere((_, v) => v == 0);
    }
    co.removeWhere((_, g) => g.isEmpty);
  }
  out.removeWhere((_, co) => co.isEmpty);
  return out;
}

/// Works out one day's stock from the previous closing and the day's inputs.
StockDay computeDay(
  String date,
  Map<String, GasState> prev,
  DayData? day, {
  required bool hasPrevious,
  Map<String, PlantQty> prevLoanCompanies = const {},
}) {
  final d = day ?? DayData(date);
  final sales = sumFull(d);
  final received = sumEmpty(d);
  final loanSupplied = _sumLoan(d, full: true);
  final loanEmptyBack = _sumLoan(d, full: false);
  final loanCos = _loanCompanies(prevLoanCompanies, d);
  final rows = <StockRow>[];
  final closing = <String, GasState>{};

  for (final gas in kGases) {
    final p = prev[gas.code] ?? const GasState();
    final openFull = d.openFull[gas.code] ?? p.full;
    final openGodown = d.openEmpty[gas.code] ?? p.godown;
    final direct = d.filling[gas.code] ?? 0;
    final sold = sales[gas.code] ?? 0;
    final got = received[gas.code] ?? 0;

    final autoPlant = gas.canKeepAtPlant ? p.plant : const <String, int>{};
    final openPlant = {...autoPlant};
    var sent = const <String, int>{}, back = const <String, int>{};
    if (gas.canKeepAtPlant) {
      openPlant.addAll(d.openPlant[gas.code] ?? const {});
      if (d.plant == null) {
        sent = d.plantSent[gas.code] ?? const {};
        back = d.plantFilled[gas.code] ?? const {};
      }
    }
    List<int> sentStepsAt(String id) =>
        (sent[id] ?? 0) == 0 ? const [] : d.sentStepsOf(gas.code, id);
    List<int> backStepsAt(String id) =>
        (back[id] ?? 0) == 0 ? const [] : d.filledStepsOf(gas.code, id);
    final sentTotal = _sum(sent), backTotal = _sum(back);

    final Map<String, int> closePlant;
    var oldDelta = 0;
    if (!gas.canKeepAtPlant) {
      closePlant = const {};
    } else if (d.plant != null) {
      // Old way: the count at each plant was typed for the end of the day.
      closePlant = {
        for (final e in (d.plant![gas.code] ?? const <String, int>{}).entries)
          if (e.value != 0) e.key: e.value,
      };
      oldDelta = _sum(closePlant) - _sum(openPlant);
    } else {
      closePlant = {};
      for (final id in {...openPlant.keys, ...sent.keys, ...back.keys}) {
        final v = (openPlant[id] ?? 0) + (sent[id] ?? 0) - (back[id] ?? 0);
        if (v != 0) closePlant[id] = v;
      }
    }

    final dmgEmpty = d.damagedEmpty[gas.code] ?? 0;
    final dmgFull = d.damagedFull[gas.code] ?? 0;
    final rep = d.repaired[gas.code] ?? 0;
    final dmgOpen = d.openDamagedGas[gas.code] ?? p.damaged;
    final dmgClose = dmgOpen + dmgEmpty + dmgFull - rep;

    final fill = direct + backTotal;
    final closeFull = openFull + fill - sold - dmgFull;
    final int closeGodown;
    if (gas.isDA) {
      closeGodown = openGodown - d.daEmptyGiven + got - dmgEmpty + rep;
    } else {
      closeGodown =
          openGodown - direct + got - sentTotal - oldDelta - dmgEmpty + rep;
    }

    final plantIds = {
      ...openPlant.keys,
      ...autoPlant.keys,
      ...closePlant.keys,
      ...sent.keys,
      ...back.keys,
    }.toList()..sort();
    final lines = <PlantLine>[];
    for (final id in plantIds) {
      final l = PlantLine(
        id,
        open: openPlant[id] ?? 0,
        autoOpen: autoPlant[id] ?? 0,
        sentSteps: sentStepsAt(id),
        filledSteps: backStepsAt(id),
        close: closePlant[id] ?? 0,
      );
      if (l.open != 0 ||
          l.autoOpen != 0 ||
          l.sent != 0 ||
          l.filled != 0 ||
          l.close != 0) {
        lines.add(l);
      }
    }

    // Loan cylinders of this gas, by the plant they belong to.
    int atCos(String plant) {
      var t = 0;
      for (final co in loanCos.values) {
        t += co[gas.code]?[plant] ?? 0;
      }
      return t;
    }

    final loanPlants = <String>{
      ...p.loanFull.keys,
      ...p.loanEmpty.keys,
      ...?d.loanIn[gas.code]?.keys,
      ...?d.loanBackEmpty[gas.code]?.keys,
      ...?d.loanBackFull[gas.code]?.keys,
      ...?loanSupplied[gas.code]?.keys,
      ...?loanEmptyBack[gas.code]?.keys,
      for (final co in loanCos.values) ...?co[gas.code]?.keys,
    }.toList()..sort();
    final loanLines = <LoanLine>[];
    final loanFullClose = <String, int>{}, loanEmptyClose = <String, int>{};
    for (final id in loanPlants) {
      final openF = p.loanFull[id] ?? 0, openE = p.loanEmpty[id] ?? 0;
      final taken = d.loanIn[gas.code]?[id] ?? 0;
      final supplied = loanSupplied[gas.code]?[id] ?? 0;
      final backF = d.loanBackFull[gas.code]?[id] ?? 0;
      final emptyBack = loanEmptyBack[gas.code]?[id] ?? 0;
      final backE = d.loanBackEmpty[gas.code]?[id] ?? 0;
      final l = LoanLine(
        id,
        openFull: openF,
        taken: taken,
        supplied: supplied,
        backFull: backF,
        closeFull: openF + taken - supplied - backF,
        openEmpty: openE,
        emptyBack: emptyBack,
        backEmpty: backE,
        closeEmpty: openE + emptyBack - backE,
        atCompanies: atCos(id),
      );
      if (l.closeFull != 0) loanFullClose[id] = l.closeFull;
      if (l.closeEmpty != 0) loanEmptyClose[id] = l.closeEmpty;
      if (l.moved || l.openFull != 0 || l.openEmpty != 0 || l.toReturn != 0) {
        loanLines.add(l);
      }
    }

    rows.add(
      StockRow(
        gas: gas,
        openFull: openFull,
        autoOpenFull: p.full,
        fill: fill,
        fillSteps: [
          ...(direct == 0 ? const <int>[] : d.fillingStepsOf(gas.code)),
          for (final id in plantIds) ...backStepsAt(id),
        ],
        sales: sold,
        closeFull: closeFull,
        openGodown: openGodown,
        autoOpenGodown: p.godown,
        received: got,
        godownFill: gas.isDA ? 0 : direct,
        sentToPlant: sentTotal,
        sentSteps: [for (final id in plantIds) ...sentStepsAt(id)],
        filledFromPlant: backTotal,
        daGiven: gas.isDA ? d.daEmptyGiven : 0,
        daGivenSteps: gas.isDA ? d.daGivenStepList : const [],
        damagedEmpty: dmgEmpty,
        damagedFull: dmgFull,
        repaired: rep,
        damagedOpen: dmgOpen,
        autoDamagedOpen: p.damaged,
        damagedClose: dmgClose,
        plantDelta: oldDelta,
        closeGodown: closeGodown,
        plantLines: lines,
        loanLines: loanLines,
      ),
    );
    closing[gas.code] = GasState(
      full: closeFull,
      godown: closeGodown,
      plant: closePlant,
      damaged: dmgClose,
      loanFull: loanFullClose,
      loanEmpty: loanEmptyClose,
    );
  }

  return StockDay(
    date: date,
    rows: rows,
    hasPrevious: hasPrevious,
    closing: closing,
    loanAtCompanies: loanCos,
  );
}

/// Chains every saved day in date order so each day's opening is the
/// previous saved day's closing. Rebuilt whenever data changes.
class StockBook {
  final List<String> _dates;
  final Map<String, DayData> _days;
  final Map<String, Map<String, GasState>> _closing = {};
  final Map<String, Map<String, PlantQty>> _loanCos = {};

  StockBook(Map<String, DayData> days)
    : _days = days,
      _dates = days.keys.toList()..sort() {
    var state = <String, GasState>{};
    var loanCos = <String, PlantQty>{};
    for (var i = 0; i < _dates.length; i++) {
      final date = _dates[i];
      final day = computeDay(
        date,
        state,
        _days[date],
        hasPrevious: i > 0,
        prevLoanCompanies: loanCos,
      );
      state = day.closing;
      loanCos = day.loanAtCompanies;
      _closing[date] = state;
      _loanCos[date] = loanCos;
    }
  }

  /// Index of the last saved date strictly before [date], or -1.
  int _prevIndex(String date) {
    var lo = 0, hi = _dates.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_dates[mid].compareTo(date) < 0) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  StockDay dayStock(String date) {
    final i = _prevIndex(date);
    final prev = i >= 0 ? _closing[_dates[i]]! : <String, GasState>{};
    return computeDay(
      date,
      prev,
      _days[date],
      hasPrevious: i >= 0,
      prevLoanCompanies: i >= 0 ? _loanCos[_dates[i]]! : const {},
    );
  }
}

/// Why a save is refused: it would push some stock below zero.
class StockProblem {
  final String date;
  final Gas gas;
  final String message;
  const StockProblem(this.date, this.gas, this.message);
}

String _somePlant(String id) => 'the plant';
String _someCompany(String key) =>
    key.startsWith('#') ? key.substring(1) : 'A company';

/// Checks what saving [changed] would do to that day and every later day.
/// Returns the problems on the first day that would go below zero. Days
/// that were already below zero before this change are not blamed on it.
List<StockProblem> newNegatives(
  Map<String, DayData> current,
  DayData changed, {
  String Function(String plantId) plantName = _somePlant,
  String Function(String companyKey) companyName = _someCompany,
}) {
  final after = Map.of(current);
  if (changed.isEmpty) {
    after.remove(changed.date);
  } else {
    after[changed.date] = changed;
  }
  final before = StockBook(current);
  final now = StockBook(after);
  final dates = {
    changed.date,
    ...after.keys.where((d) => d.compareTo(changed.date) > 0),
  }.toList()..sort();
  for (final date in dates) {
    final o = before.dayStock(date), n = now.dayStock(date);
    final out = <StockProblem>[];
    for (var i = 0; i < n.rows.length; i++) {
      final r = n.rows[i], was = o.rows[i];
      if (r.closeFull < 0 && r.closeFull < was.closeFull) {
        final used = [
          if (r.sales > 0) '${r.sales} supplied',
          if (r.damagedFull > 0) '${r.damagedFull} damaged',
        ];
        out.add(
          StockProblem(
            date,
            r.gas,
            '${r.gas.label} FULL: only ${r.openFull + r.fill} in stock, '
            'but ${used.isEmpty ? 'more used' : used.join(' + ')} '
            '(short by ${-r.closeFull}).',
          ),
        );
      }
      if (r.closeGodown < 0 && r.closeGodown < was.closeGodown) {
        final String used;
        final int have;
        final damaged = [if (r.damagedEmpty > 0) '${r.damagedEmpty} damaged'];
        if (r.gas.isDA) {
          have = r.openGodown + r.received + r.repaired;
          used = [
            if (r.daGiven > 0) '${r.daGiven} given to plant',
            ...damaged,
          ].join(' + ');
        } else {
          have =
              r.openGodown +
              r.received +
              r.repaired +
              (r.plantDelta < 0 ? -r.plantDelta : 0);
          final parts = [
            if (r.godownFill > 0) '${r.godownFill} filled',
            if (r.sentToPlant > 0) '${r.sentToPlant} sent to plant',
            if (r.plantDelta > 0) '${r.plantDelta} left at plant',
            ...damaged,
          ];
          used = parts.isEmpty ? 'more used' : parts.join(' + ');
        }
        out.add(
          StockProblem(
            date,
            r.gas,
            '${r.gas.label} EMPTY: only $have empty in godown, '
            'but $used (short by ${-r.closeGodown}).',
          ),
        );
      }
      for (final l in r.plantLines) {
        if (l.close >= 0) continue;
        final old = was.plantLines.where((x) => x.plantId == l.plantId);
        if (old.isNotEmpty && old.first.close <= l.close) continue;
        out.add(
          StockProblem(
            date,
            r.gas,
            '${r.gas.label} at ${plantName(l.plantId)}: only ${l.open + l.sent} '
            'empty there, but ${l.filled} filled back (short by ${-l.close}).',
          ),
        );
      }
      if (r.damagedClose < 0 && r.damagedClose < was.damagedClose) {
        out.add(
          StockProblem(
            date,
            r.gas,
            'DAMAGED ${r.gas.label}: only ${r.damagedOpen + r.damagedIn} damaged '
            '${r.gas.label}, but ${r.repaired} repaired (short by ${-r.damagedClose}). '
            'A damaged cylinder comes back only as its own gas.',
          ),
        );
      }
      for (final l in r.loanLines) {
        final old = was.loanLines.where((x) => x.plantId == l.plantId);
        final oldFull = old.isEmpty ? 0 : old.first.closeFull;
        final oldEmpty = old.isEmpty ? 0 : old.first.closeEmpty;
        final from = '${r.gas.label} LOAN from ${plantName(l.plantId)}';
        if (l.closeFull < 0 && l.closeFull < oldFull) {
          final used = [
            if (l.supplied > 0) '${l.supplied} supplied',
            if (l.backFull > 0) '${l.backFull} given back full',
          ];
          out.add(
            StockProblem(
              date,
              r.gas,
              '$from: only ${l.openFull + l.taken} loan cylinders full in godown, '
              'but ${used.isEmpty ? 'more used' : used.join(' + ')} '
              '(short by ${-l.closeFull}).',
            ),
          );
        }
        if (l.closeEmpty < 0 && l.closeEmpty < oldEmpty) {
          out.add(
            StockProblem(
              date,
              r.gas,
              '$from: only ${l.openEmpty + l.emptyBack} loan empties in godown, '
              'but ${l.backEmpty} given back empty (short by ${-l.closeEmpty}).',
            ),
          );
        }
      }
    }
    // Loan cylinders with each company.
    final day = after[date];
    n.loanAtCompanies.forEach((co, byGas) {
      byGas.forEach((gas, byPlant) {
        byPlant.forEach((plant, v) {
          if (v >= 0) return;
          final wasV = o.loanAtCompanies[co]?[gas]?[plant] ?? 0;
          if (v >= wasV) return;
          var emptyToday = 0;
          for (final e in day?.entries ?? const <Entry>[]) {
            if (loanCompanyKey(e) == co) {
              emptyToday += e.loanEmpty[gas]?[plant] ?? 0;
            }
          }
          final g = gasByCode(gas) ?? kGases.first;
          out.add(
            StockProblem(
              date,
              g,
              '${companyName(co)} – ${g.label} LOAN from ${plantName(plant)}: '
              'they have only ${v + emptyToday} loan cylinders, but $emptyToday '
              'loan empty received (short by ${-v}).',
            ),
          );
        });
      });
    });
    if (out.isNotEmpty) return out;
  }
  return const [];
}
