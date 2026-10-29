/// A company (customer) or a filling plant. Removed items are kept as
/// inactive so old entries still show their name.
class NamedItem {
  final String id;
  String name;
  bool active;

  /// Companies only: cylinders the company already had before using the
  /// app (gas code -> qty). Counted at the start of the company's balance.
  Map<String, int> opening;

  NamedItem({
    required this.id,
    required this.name,
    this.active = true,
    Map<String, int>? opening,
  }) : opening = opening ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'active': active,
    if (opening.isNotEmpty) 'opening': opening,
  };

  factory NamedItem.fromJson(String id, Map<String, dynamic> j) => NamedItem(
    id: id,
    name: j['name'] as String? ?? '',
    active: j['active'] as bool? ?? true,
    opening: intMap(j['opening']),
  );
}

const String kModeCash = 'cash';
const String kModeGpay = 'gpay';

String modeLabel(String mode) => mode == kModeGpay ? 'GPay' : 'Cash';

/// One line of cash received from a company, e.g. "Deposit 2000 by Cash".
class CashItem {
  String type;
  double amount;
  String mode;

  CashItem({required this.type, required this.amount, this.mode = kModeCash});

  Map<String, dynamic> toJson() => {
    'type': type,
    'amount': amount,
    'mode': mode,
  };

  factory CashItem.fromJson(Map<String, dynamic> j) => CashItem(
    type: j['type'] as String? ?? '',
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    mode: j['mode'] as String? ?? kModeCash,
  );
}

/// One row of the day's register: a company, the full cylinders supplied,
/// the challan number, the empties received back and optional cash.
class Entry {
  final String id;

  /// Order inside the day (Sr No.). New entries get the time they were made.
  int sort;
  String? companyId;
  String company;
  String challan;
  Map<String, int> full;
  Map<String, int> empty;
  List<CashItem> cash;

  /// True when this company's bill for the day has been made.
  bool billed;

  /// Loan cylinders (borrowed from a filling plant, marked as that plant's):
  /// full ones supplied to this company / empty ones received back.
  /// gas -> plant -> qty. Kept apart from our own cylinders.
  PlantQty loanFull;
  PlantQty loanEmpty;

  /// A remark on a line of the entry, by the line's gas code (loan lines:
  /// "gas|plantId"), e.g. "ARGON SPL".
  Map<String, String> remarks;

  /// Parts written by a newer version of the app, kept as they are.
  final Map<String, dynamic> _extra;

  Entry({
    required this.id,
    this.sort = 0,
    this.companyId,
    required this.company,
    this.challan = '',
    this.billed = false,
    Map<String, int>? full,
    Map<String, int>? empty,
    List<CashItem>? cash,
    PlantQty? loanFull,
    PlantQty? loanEmpty,
    Map<String, String>? remarks,
    Map<String, dynamic>? extra,
  }) : remarks = remarks ?? {},
       full = full ?? {},
       empty = empty ?? {},
       cash = cash ?? [],
       loanFull = loanFull ?? {},
       loanEmpty = loanEmpty ?? {},
       _extra = extra ?? {};

  int get totalFull => full.values.fold(0, (a, b) => a + b);

  bool get hasLoan => loanFull.isNotEmpty || loanEmpty.isNotEmpty;
  int get totalLoanFull => sumPlantQty(loanFull);
  int get totalLoanEmpty => sumPlantQty(loanEmpty);

  /// A bill is made only for full cylinders supplied (ours or loan ones).
  /// An entry with only empties received (and maybe cash) needs no bill.
  bool get needsBill => full.values.any((q) => q > 0) || totalLoanFull > 0;

  /// Bill still to be made (only entries that need one).
  bool get billPending => needsBill && !billed;
  int get totalEmpty => empty.values.fold(0, (a, b) => a + b);
  double get totalCash => cash.fold(0.0, (a, c) => a + c.amount);

  static const _known = {
    'sort',
    'companyId',
    'company',
    'challan',
    'billed',
    'full',
    'empty',
    'cash',
    'loanFull',
    'loanEmpty',
    'remarks',
    'date',
  };

  /// Stored form (the date is stored next to it).
  Map<String, dynamic> toJson() => {
    ..._extra,
    'sort': sort,
    'companyId': companyId,
    'company': company,
    'challan': challan,
    'billed': billed,
    'full': full,
    'empty': empty,
    if (cash.isNotEmpty) 'cash': [for (final c in cash) c.toJson()],
    if (loanFull.isNotEmpty) 'loanFull': loanFull,
    if (loanEmpty.isNotEmpty) 'loanEmpty': loanEmpty,
    if (remarks.isNotEmpty) 'remarks': remarks,
  };

  factory Entry.fromJson(String id, Map<String, dynamic> j) => Entry(
    id: id,
    sort: (j['sort'] as num?)?.toInt() ?? 0,
    companyId: j['companyId']?.toString(),
    company: j['company'] as String? ?? '',
    challan: j['challan'] as String? ?? '',
    billed: j['billed'] as bool? ?? false,
    full: intMap(j['full']),
    empty: intMap(j['empty']),
    cash: [
      for (final c in (j['cash'] as List? ?? const []))
        CashItem.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    loanFull: plantQty(j['loanFull']),
    loanEmpty: plantQty(j['loanEmpty']),
    remarks: {
      if (j['remarks'] is Map)
        for (final e in (j['remarks'] as Map).entries)
          if (e.value is String && (e.value as String).trim().isNotEmpty)
            e.key.toString(): e.value as String,
    },
    extra: {
      for (final e in j.entries)
        if (!_known.contains(e.key)) e.key: e.value,
    },
  );

  Entry copy() => Entry.fromJson(id, toJson());
}

/// gas code -> plant id -> qty
typedef PlantQty = Map<String, Map<String, int>>;

/// gas code -> plant id -> numbers typed one after another that day
typedef PlantSteps = Map<String, Map<String, List<int>>>;

int _sum(List<int> l) => l.fold(0, (a, b) => a + b);

/// The steps when they really add up to [total], else the total as one step.
List<int> _stepsOr(List<int>? steps, int total) {
  if (steps != null &&
      steps.length > 1 &&
      steps.every((x) => x > 0) &&
      _sum(steps) == total) {
    return List.of(steps);
  }
  return total == 0 ? <int>[] : <int>[total];
}

/// Everything entered for one date. Stock numbers are not stored; they are
/// worked out from these inputs and the previous day's closing.
class DayData {
  final String date; // yyyy-MM-dd

  List<Entry> entries;

  /// Filled cylinders received without a plant line (+ to full stock):
  /// DA, and entries written before plant tracking, which were taken
  /// straight out of the godown empties.
  Map<String, int> filling;

  /// DA only: empty DA cylinders handed over at the plant today.
  int daEmptyGiven;

  /// The filling plant where the day's DA was swapped (the DA filled and
  /// DA empty given above). Null = the usual DA plant (AppStore.daPlantId).
  /// DA keeps its own logic: no count is kept at the plant.
  String? daPlant;

  /// Hand-corrected opening values. Missing gas = use yesterday's closing.
  Map<String, int> openFull;
  Map<String, int> openEmpty;

  /// Empties taken from the godown to a filling plant today.
  PlantQty plantSent;

  /// Filled cylinders that came back from a filling plant today. They are
  /// added to full stock and taken off the empties waiting at that plant
  /// (not off the godown).
  PlantQty plantFilled;

  /// Hand-corrected empties at a plant at the start of the day. Missing =
  /// carried on from the day before.
  PlantQty openPlant;

  /// Old way (before plant tracking): empties waiting at plants at the end
  /// of this day, typed as a count. Null means "same as yesterday".
  PlantQty? plant;

  /// How some numbers were typed during the day, one after another (e.g. 11
  /// filled in the morning and 3 more later = 14). Only kept where there was
  /// more than one step; the totals above are what is counted.
  Map<String, List<int>> fillingSteps;
  PlantSteps plantSentSteps;
  PlantSteps plantFilledSteps;
  List<int> daGivenSteps;

  /// Cylinders declared damaged today, by gas: taken out of the godown
  /// empties / out of the full stock. A damaged cylinder keeps its gas: it
  /// is counted as "damaged Oxygen" etc. until it is repaired.
  Map<String, int> damagedEmpty;
  Map<String, int> damagedFull;

  /// Damaged cylinders repaired today, by gas. A damaged Oxygen comes back
  /// only as an Oxygen empty in the godown (never as another gas).
  Map<String, int> repaired;

  /// Hand-corrected damaged cylinders of each gas at the start of the day
  /// (only gases that differ from the day before; a 0 is kept). Missing
  /// gas = carried on from the day before. (Before 2.3 the start count had
  /// no gas, under "openDamaged"; that old number is kept but not used.)
  Map<String, int> openDamagedGas;

  /// Loan cylinders taken from a filling plant today (they come full and
  /// can be supplied straight away). gas -> plant -> qty.
  PlantQty loanIn;

  /// Loan cylinders given back to their plant today: empty / still full.
  PlantQty loanBackEmpty;
  PlantQty loanBackFull;

  /// Parts written by a newer version of the app. Kept as they are, so
  /// saving here never throws them away.
  final Map<String, dynamic> _extra;

  DayData(
    this.date, {
    List<Entry>? entries,
    Map<String, int>? filling,
    this.daEmptyGiven = 0,
    this.daPlant,
    Map<String, int>? openFull,
    Map<String, int>? openEmpty,
    PlantQty? plantSent,
    PlantQty? plantFilled,
    PlantQty? openPlant,
    this.plant,
    Map<String, List<int>>? fillingSteps,
    PlantSteps? plantSentSteps,
    PlantSteps? plantFilledSteps,
    List<int>? daGivenSteps,
    Map<String, int>? damagedEmpty,
    Map<String, int>? damagedFull,
    Map<String, int>? repaired,
    Map<String, int>? openDamagedGas,
    PlantQty? loanIn,
    PlantQty? loanBackEmpty,
    PlantQty? loanBackFull,
    Map<String, dynamic>? extra,
  }) : entries = entries ?? [],
       filling = filling ?? {},
       openFull = openFull ?? {},
       openEmpty = openEmpty ?? {},
       plantSent = plantSent ?? {},
       plantFilled = plantFilled ?? {},
       openPlant = openPlant ?? {},
       fillingSteps = fillingSteps ?? {},
       plantSentSteps = plantSentSteps ?? {},
       plantFilledSteps = plantFilledSteps ?? {},
       daGivenSteps = daGivenSteps ?? [],
       damagedEmpty = damagedEmpty ?? {},
       damagedFull = damagedFull ?? {},
       repaired = repaired ?? {},
       openDamagedGas = openDamagedGas ?? {},
       loanIn = loanIn ?? {},
       loanBackEmpty = loanBackEmpty ?? {},
       loanBackFull = loanBackFull ?? {},
       _extra = extra ?? {};

  /// True when the day-level stock inputs (not entries) are all empty.
  bool get metaEmpty =>
      filling.isEmpty &&
      daEmptyGiven == 0 &&
      openFull.isEmpty &&
      openEmpty.isEmpty &&
      plantSent.isEmpty &&
      plantFilled.isEmpty &&
      openPlant.isEmpty &&
      plant == null &&
      damagedEmpty.isEmpty &&
      damagedFull.isEmpty &&
      repaired.isEmpty &&
      openDamagedGas.isEmpty &&
      loanIn.isEmpty &&
      loanBackEmpty.isEmpty &&
      loanBackFull.isEmpty &&
      _extra.isEmpty;

  bool get isEmpty => entries.isEmpty && metaEmpty;

  // ------------------------------------------------ step by step numbers

  List<int> fillingStepsOf(String gas) =>
      _stepsOr(fillingSteps[gas], filling[gas] ?? 0);
  List<int> sentStepsOf(String gas, String plant) =>
      _stepsOr(plantSentSteps[gas]?[plant], plantSent[gas]?[plant] ?? 0);
  List<int> filledStepsOf(String gas, String plant) =>
      _stepsOr(plantFilledSteps[gas]?[plant], plantFilled[gas]?[plant] ?? 0);
  List<int> get daGivenStepList => _stepsOr(daGivenSteps, daEmptyGiven);

  /// Sets a (non-plant) filling, e.g. DA filled received, from its steps.
  void setFillingSteps(String gas, List<int> steps) {
    final total = _sum(steps);
    if (total > 0) {
      filling[gas] = total;
    } else {
      filling.remove(gas);
    }
    if (steps.length > 1) {
      fillingSteps[gas] = List.of(steps);
    } else {
      fillingSteps.remove(gas);
    }
  }

  void setDaGivenSteps(List<int> steps) {
    daEmptyGiven = _sum(steps);
    daGivenSteps = steps.length > 1 ? List.of(steps) : [];
  }

  /// Adds steps of empties sent to / filled back from a plant.
  void addPlantSteps({
    required bool sent,
    required String gas,
    required String plant,
    required List<int> steps,
  }) {
    if (steps.isEmpty) return;
    final all = [
      ...(sent ? sentStepsOf(gas, plant) : filledStepsOf(gas, plant)),
      ...steps,
    ];
    final totals = sent ? plantSent : plantFilled;
    final store = sent ? plantSentSteps : plantFilledSteps;
    final total = _sum(all);
    if (total > 0) (totals[gas] ??= {})[plant] = total;
    if (all.length > 1) {
      (store[gas] ??= {})[plant] = all;
    } else {
      store[gas]?.remove(plant);
      if (store[gas]?.isEmpty ?? false) store.remove(gas);
    }
  }

  /// Clears all filling numbers (before writing them again).
  void clearFilling() {
    filling = {};
    fillingSteps = {};
    plantSent = {};
    plantFilled = {};
    plantSentSteps = {};
    plantFilledSteps = {};
    daEmptyGiven = 0;
    daGivenSteps = [];
    daPlant = null;
  }

  /// All filled cylinders received today (with or without a plant line).
  Map<String, int> get totalFilling {
    final m = Map.of(filling);
    plantFilled.forEach((gas, byPlant) {
      for (final v in byPlant.values) {
        m[gas] = (m[gas] ?? 0) + v;
      }
    });
    return m;
  }

  /// All cylinders declared damaged today (from empty and from full).
  Map<String, int> get damagedToday {
    final m = Map.of(damagedEmpty);
    damagedFull.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
    return m;
  }

  static const _known = {
    'filling',
    'daEmptyGiven',
    'daPlant',
    'openFull',
    'openEmpty',
    'plantSent',
    'plantFilled',
    'openPlant',
    'plant',
    'steps',
    'damagedEmpty',
    'damagedFull',
    'repaired',
    'openDamagedGas',
    'loanIn',
    'loanBackEmpty',
    'loanBackFull',
  };

  /// Stored form of the day-level stock inputs (entries are stored apart).
  Map<String, dynamic> metaJson() => {
    ..._extra,
    if (filling.isNotEmpty) 'filling': filling,
    if (daEmptyGiven != 0) 'daEmptyGiven': daEmptyGiven,
    if (daPlant != null && ((filling['DA'] ?? 0) > 0 || daEmptyGiven > 0))
      'daPlant': daPlant,
    if (openFull.isNotEmpty) 'openFull': openFull,
    if (openEmpty.isNotEmpty) 'openEmpty': openEmpty,
    if (plantSent.isNotEmpty) 'plantSent': plantSent,
    if (plantFilled.isNotEmpty) 'plantFilled': plantFilled,
    if (openPlant.isNotEmpty) 'openPlant': openPlant,
    if (plant != null) 'plant': plant,
    if (fillingSteps.isNotEmpty ||
        plantSentSteps.isNotEmpty ||
        plantFilledSteps.isNotEmpty ||
        daGivenSteps.length > 1)
      'steps': {
        if (fillingSteps.isNotEmpty) 'filling': fillingSteps,
        if (plantSentSteps.isNotEmpty) 'plantSent': plantSentSteps,
        if (plantFilledSteps.isNotEmpty) 'plantFilled': plantFilledSteps,
        if (daGivenSteps.length > 1) 'daEmptyGiven': daGivenSteps,
      },
    if (damagedEmpty.isNotEmpty) 'damagedEmpty': damagedEmpty,
    if (damagedFull.isNotEmpty) 'damagedFull': damagedFull,
    if (repaired.isNotEmpty) 'repaired': repaired,
    if (openDamagedGas.isNotEmpty) 'openDamagedGas': openDamagedGas,
    if (loanIn.isNotEmpty) 'loanIn': loanIn,
    if (loanBackEmpty.isNotEmpty) 'loanBackEmpty': loanBackEmpty,
    if (loanBackFull.isNotEmpty) 'loanBackFull': loanBackFull,
  };

  static DayData fromMeta(
    String date,
    Map<String, dynamic> j, [
    List<Entry>? entries,
  ]) {
    final steps = j['steps'] is Map ? j['steps'] as Map : const {};
    return DayData(
      date,
      entries: entries,
      filling: intMap(j['filling']),
      daEmptyGiven: (j['daEmptyGiven'] as num?)?.toInt() ?? 0,
      daPlant: j['daPlant'] is String ? j['daPlant'] as String : null,
      // A correction to 0 is a real value, so keep zeros here.
      openFull: intMap(j['openFull'], keepZero: true),
      openEmpty: intMap(j['openEmpty'], keepZero: true),
      plantSent: plantQty(j['plantSent']),
      plantFilled: plantQty(j['plantFilled']),
      openPlant: plantQty(j['openPlant'], keepZero: true),
      plant: j['plant'] is Map ? plantQty(j['plant']) : null,
      fillingSteps: _stepMap(steps['filling']),
      plantSentSteps: _plantSteps(steps['plantSent']),
      plantFilledSteps: _plantSteps(steps['plantFilled']),
      daGivenSteps: _stepList(steps['daEmptyGiven']),
      damagedEmpty: intMap(j['damagedEmpty']),
      damagedFull: intMap(j['damagedFull']),
      repaired: intMap(j['repaired']),
      openDamagedGas: intMap(j['openDamagedGas'], keepZero: true),
      loanIn: plantQty(j['loanIn']),
      loanBackEmpty: plantQty(j['loanBackEmpty']),
      loanBackFull: plantQty(j['loanBackFull']),
      extra: {
        for (final e in j.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }

  DayData copy() =>
      fromMeta(date, metaJson(), [for (final e in entries) e.copy()]);
}

/// Reads a {gas: qty} map, dropping zeros unless [keepZero].
Map<String, int> intMap(Object? raw, {bool keepZero = false}) {
  if (raw is! Map) return {};
  final out = <String, int>{};
  raw.forEach((k, v) {
    final n = (v as num?)?.toInt() ?? 0;
    if (n != 0 || keepZero) out[k.toString()] = n;
  });
  return out;
}

/// Reads a {gas: {plant: qty}} map, dropping empty parts.
PlantQty plantQty(Object? raw, {bool keepZero = false}) {
  if (raw is! Map) return {};
  final out = <String, Map<String, int>>{};
  raw.forEach((g, m) {
    final q = intMap(m, keepZero: keepZero);
    if (q.isNotEmpty) out[g.toString()] = q;
  });
  return out;
}

/// All the numbers in a gas -> plant -> qty map added up.
int sumPlantQty(PlantQty m) {
  var t = 0;
  for (final g in m.values) {
    for (final v in g.values) {
      t += v;
    }
  }
  return t;
}

/// Adds [qty] to [m][gas][plantId].
void addPlantQty(PlantQty m, String gas, String plantId, int qty) {
  if (qty == 0) return;
  final g = m[gas] ??= {};
  g[plantId] = (g[plantId] ?? 0) + qty;
}

List<int> _stepList(Object? raw) => raw is List
    ? [
        for (final v in raw)
          if (v is num && v > 0) v.toInt(),
      ]
    : <int>[];

Map<String, List<int>> _stepMap(Object? raw) {
  if (raw is! Map) return {};
  final out = <String, List<int>>{};
  raw.forEach((k, v) {
    final l = _stepList(v);
    if (l.isNotEmpty) out[k.toString()] = l;
  });
  return out;
}

PlantSteps _plantSteps(Object? raw) {
  if (raw is! Map) return {};
  final out = <String, Map<String, List<int>>>{};
  raw.forEach((g, m) {
    final q = _stepMap(m);
    if (q.isNotEmpty) out[g.toString()] = q;
  });
  return out;
}
