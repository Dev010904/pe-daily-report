import 'dart:convert';
import 'dart:math';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/argon_spl.dart';
import '../logic/ledger.dart';
import '../logic/plant_report.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../models/purchase_order.dart';
import '../models/vehicle.dart';
import 'records.dart';
import 'repo.dart';

const List<String> kDefaultCashTypes = ['Deposit', 'Payment'];

final Random _rng = Random.secure();

/// New unique id (32 hex characters).
String newId() => List.generate(
  16,
  (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

/// The app's data as screens see it: days, entries, companies, plants and
/// settings, worked out from the synced records in [repo].
class AppStore extends ChangeNotifier {
  final Repo repo;

  AppStore(this.repo) {
    repo.addListener(_onRepo);
    _rebuild();
  }

  final Map<String, NamedItem> _companies = {};
  final Map<String, NamedItem> _plants = {};
  final Map<String, DayData> _days = {};
  List<String> cashTypes = List.of(kDefaultCashTypes);

  /// Delivery vehicles and their papers (stored as settings records named
  /// "vehicle_" + id, so the cloud needs no change).
  final Map<String, Vehicle> _vehicles = {};

  /// Companies' purchase orders (settings records "po_" + id).
  final Map<String, PurchaseOrder> _pos = {};

  /// PO id -> gas -> full cylinders supplied against it, and what each
  /// entry added (to leave one entry out while it is being changed).
  final Map<String, Map<String, int>> _poSupplied = {};
  final Map<String, Map<String, Map<String, int>>> _poByEntry = {};
  String? _daPlantSetting;
  String? _daPlantOldSetting;
  StockBook? _book;
  int _seen = -1;

  void _onRepo() {
    if (repo.dataVersion != _seen) _rebuild();
    notifyListeners();
    _maybeSaveSplMerge();
  }

  // ------------------------------------------------- AR SPL -> ARGON

  /// Records that still say AR SPL, as they will be saved once merged into
  /// ARGON (empty when there are none). The screens already show them merged.
  List<Rec> _splRecords = const [];
  bool _splSaving = false;

  /// True while old AR SPL records have not been rewritten yet.
  bool get hasUnsavedSplMerge => _splRecords.isNotEmpty;

  /// Writes the merged records, right after a sync has brought this device
  /// up to date (so nothing newer from another device is overwritten).
  void _maybeSaveSplMerge() {
    if (_splRecords.isEmpty || _splSaving) return;
    if (repo.state != SyncState.idle || repo.lastSynced == null) return;
    scheduleMicrotask(saveSplMerge);
  }

  /// Rewrites every record that still uses AR SPL (ARGON from now on).
  Future<void> saveSplMerge() async {
    if (_splRecords.isEmpty || _splSaving) return;
    _splSaving = true;
    try {
      await repo.put(_splRecords);
    } finally {
      _splSaving = false;
    }
  }

  void _rebuild() {
    _seen = repo.dataVersion;
    _companies.clear();
    _plants.clear();
    _days.clear();
    cashTypes = List.of(kDefaultCashTypes);
    _vehicles.clear();
    _pos.clear();
    _daPlantSetting = null;
    _daPlantOldSetting = null;
    final metas = <String, Map<String, dynamic>>{};
    final entries = <String, List<Entry>>{};
    for (final r in repo.records) {
      if (r.deleted) continue;
      switch (r.kind) {
        case Kind.company:
          _companies[r.id] = NamedItem.fromJson(r.id, r.data);
        case Kind.plant:
          _plants[r.id] = NamedItem.fromJson(r.id, r.data);
        case Kind.day:
          metas[r.id] = r.data;
        case Kind.entry:
          final date = r.data['date'] as String?;
          if (date != null) {
            (entries[date] ??= []).add(Entry.fromJson(r.id, r.data));
          }
        case Kind.setting:
          if (r.id.startsWith('vehicle_')) {
            final id = r.id.substring('vehicle_'.length);
            _vehicles[id] = Vehicle.fromJson(id, r.data);
          }
          if (r.id.startsWith('po_')) {
            final id = r.id.substring('po_'.length);
            _pos[id] = PurchaseOrder.fromJson(id, r.data);
          }
          if (r.id == 'cashTypes' && r.data['values'] is List) {
            cashTypes = List<String>.from(r.data['values'] as List);
          }
          if (r.id == 'daPlant') {
            if (r.data['id'] is String) {
              _daPlantSetting = r.data['id'] as String;
            }
            if (r.data['old'] is String) {
              _daPlantOldSetting = r.data['old'] as String;
            }
          }
      }
    }
    for (final date in {...metas.keys, ...entries.keys}) {
      final list = entries[date] ?? [];
      list.sort((a, b) {
        final s = a.sort.compareTo(b.sort);
        return s != 0 ? s : a.id.compareTo(b.id);
      });
      // Show a company's current name even on old entries.
      for (final e in list) {
        final c = e.companyId == null ? null : _companies[e.companyId];
        if (c != null) e.company = c.name;
      }
      final day = DayData.fromMeta(date, metas[date] ?? const {}, list);
      if (!day.isEmpty) _days[date] = day;
    }
    _mergeSpl(metas);
    _countPoSupplied();
    _book = null;
  }

  /// Counts old AR SPL as ARGON (see logic/argon_spl.dart) and keeps the
  /// records to rewrite.
  void _mergeSpl(Map<String, Map<String, dynamic>> metas) {
    final out = <Rec>[];
    for (final c in _companies.values) {
      if (c.opening.containsKey(kSpl)) {
        c.opening = mergeSplOpening(c.opening);
        out.add(Rec(Kind.company, c.id, c.toJson()));
      }
    }
    if (daysUseSpl(_days)) {
      final merged = mergeSplDays(_days);
      merged.forEach((date, d) {
        final was = _days[date]!;
        final meta = d.metaJson();
        if (jsonEncode(meta) != jsonEncode(was.metaJson())) {
          out.add(Rec(Kind.day, date, meta, deleted: d.metaEmpty));
        }
        for (var i = 0; i < d.entries.length; i++) {
          if (entryUsesSpl(was.entries[i])) {
            final e = d.entries[i];
            out.add(Rec(Kind.entry, e.id, {...e.toJson(), 'date': date}));
          }
        }
      });
      _days
        ..clear()
        ..addAll(merged);
    }
    _splRecords = out;
  }

  // ---------------------------------------------------------------- days

  /// A copy of the day (or a blank one) that screens can edit freely.
  DayData day(String date) => _days[date]?.copy() ?? DayData(date);

  bool hasData(String date) => _days.containsKey(date);

  /// Dates with data, oldest first.
  List<String> get savedDates => _days.keys.toList()..sort();

  Future<void> saveDay(DayData d) => repo.put(_dayChanges(d));

  /// The records that change when [d] replaces the saved day.
  List<Rec> _dayChanges(DayData d) {
    final old = _days[d.date];
    final oldEntries = {
      for (final e in old?.entries ?? const <Entry>[]) e.id: e,
    };
    final out = <Rec>[];
    for (final e in d.entries) {
      final data = {...e.toJson(), 'date': d.date};
      final before = oldEntries.remove(e.id);
      if (before == null ||
          jsonEncode({...before.toJson(), 'date': d.date}) !=
              jsonEncode(data)) {
        out.add(Rec(Kind.entry, e.id, data));
      }
    }
    for (final gone in oldEntries.values) {
      out.add(
        Rec(Kind.entry, gone.id, {
          ...gone.toJson(),
          'date': d.date,
        }, deleted: true),
      );
    }
    final meta = d.metaJson();
    if (jsonEncode(meta) != jsonEncode(old?.metaJson() ?? const {})) {
      out.add(Rec(Kind.day, d.date, meta, deleted: d.metaEmpty));
    }
    return out;
  }

  /// Order number for a new entry (keeps the order it was written in).
  int nextSort() => DateTime.now().microsecondsSinceEpoch;

  StockDay stock(String date) => (_book ??= StockBook(_days)).dayStock(date);

  /// What would go below zero if [d] were saved (stock or company
  /// balances). Empty = safe to save.
  List<StockProblem> problemsIfSaved(DayData d) {
    final stock = newNegatives(
      _days,
      d,
      plantName: plantName,
      companyName: loanCompanyName,
    );
    if (stock.isNotEmpty) return stock;
    final old = _days[d.date]?.entries ?? const <Entry>[];
    final ids = {
      for (final e in [...old, ...d.entries])
        if (e.companyId != null) e.companyId!,
    };
    final out = <StockProblem>[];
    for (final id in ids) {
      final c = _companies[id];
      if (c == null) continue;
      final before = companyEntries(id);
      final after = [
        for (final x in before)
          if (x.date != d.date) x,
        for (final e in d.entries)
          if (e.companyId == id) DatedEntry(d.date, e),
      ];
      out.addAll(
        companyProblems(
          company: c,
          before: before,
          after: after,
          fromDate: d.date,
        ),
      );
    }
    return out;
  }

  // --------------------------------------------------- companies & ledger

  List<NamedItem> get companies => _companies.values.toList();
  List<NamedItem> get plants => _plants.values.toList();
  List<NamedItem> get activeCompanies => _sorted(_companies.values);
  List<NamedItem> get activePlants => _sorted(_plants.values);

  static List<NamedItem> _sorted(Iterable<NamedItem> items) =>
      items.where((c) => c.active).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  NamedItem? company(String id) => _companies[id];

  String plantName(String id) => _plants[id]?.name ?? 'Plant';

  /// Name of the company a loan cylinder is with (see loanCompanyKey).
  String loanCompanyName(String key) => key.startsWith('#')
      ? key.substring(1)
      : (_companies[key]?.name ?? 'Company');

  // --------------------------------------------------------------- vehicles

  /// Delivery vehicles, by number.
  List<Vehicle> get vehicles => _vehicles.values.toList()
    ..sort((a, b) => Vehicle.norm(a.number).compareTo(Vehicle.norm(b.number)));

  /// A copy that a page can change freely (saved with [saveVehicle]).
  Vehicle? vehicle(String id) => _vehicles[id]?.copy();

  /// Another vehicle with the same number (spaces / dashes ignored).
  Vehicle? vehicleWithNumber(String number, {String? except}) {
    final n = Vehicle.norm(number);
    for (final v in _vehicles.values) {
      if (v.id != except && Vehicle.norm(v.number) == n) return v;
    }
    return null;
  }

  Future<Vehicle> addVehicle(String number) async {
    final v = Vehicle(id: newId(), number: number.trim().toUpperCase());
    await saveVehicle(v);
    return v;
  }

  Future<void> saveVehicle(Vehicle v) =>
      repo.put([Rec(Kind.setting, 'vehicle_${v.id}', v.toJson())]);

  Future<void> removeVehicle(Vehicle v) => repo.put([
    Rec(Kind.setting, 'vehicle_${v.id}', v.toJson(), deleted: true),
  ]);

  /// Papers to renew: expiring within kPaperAlertDays days, or expired
  /// (most urgent first).
  List<PaperAlert> paperAlerts({DateTime? now}) {
    final out = <PaperAlert>[
      for (final v in vehicles)
        for (final p in v.papers)
          if (p.isDue(now)) PaperAlert(v, p, p.daysLeft(now)),
    ];
    out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return out;
  }

  /// Paper names used so far plus the usual ones, for the list.
  List<String> get paperTypes {
    final out = <String>[...kPaperTypes];
    for (final v in _vehicles.values) {
      for (final p in v.papers) {
        if (!out.any((t) => t.toLowerCase() == p.type.toLowerCase())) {
          out.add(p.type);
        }
      }
    }
    return out;
  }

  // --------------------------------------------------------- loan cylinders

  /// Loan cylinders with one company at the end of [date]: gas -> plant -> qty.
  PlantQty loanWithCompany(String companyId, String date) =>
      stock(date).loanAtCompanies[companyId] ?? const {};

  /// Every loan line (gas, plant) at the end of [date].
  List<(Gas, LoanLine)> loanLinesOn(String date) => stock(date).loanLines;

  /// Which companies have loan cylinders of [gas] from [plantId] at the end
  /// of [date]: company name -> qty.
  Map<String, int> loanCompaniesFor(String gas, String plantId, String date) {
    final out = <String, int>{};
    stock(date).loanAtCompanies.forEach((co, byGas) {
      final v = byGas[gas]?[plantId] ?? 0;
      if (v != 0) out[loanCompanyName(co)] = v;
    });
    return out;
  }

  // ------------------------------------------------------------ DA plant

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The plant DA was always swapped at before DA had its own plant line:
  /// every DA filling saved without a plant (all the old ones) counts there.
  /// It is the plant named "Aims Oxygen ...", fixed the first time DA is
  /// saved so a later rename or a change of DA plant can't move old days.
  String? get oldDaPlantId {
    final s = _daPlantOldSetting;
    if (s != null && _plants.containsKey(s)) return s;
    final all = _plants.values.toList()
      // Active plants first, then by name.
      ..sort(
        (a, b) => a.active != b.active
            ? (a.active ? -1 : 1)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    // "Aims Oxygen P Ltd", however it is spelled.
    for (final key in const ['aimsoxygen', 'aimsoxy', 'aims']) {
      for (final p in all) {
        if (_norm(p.name).contains(key)) return p.id;
      }
    }
    return null;
  }

  /// The plant a new DA line starts with: where DA was last swapped.
  String? get daPlantId {
    final s = _daPlantSetting;
    if (s != null && _plants[s]?.active == true) return s;
    final old = oldDaPlantId;
    return old != null && _plants[old]?.active == true ? old : null;
  }

  /// The plant a day's DA was swapped at.
  String? daPlantOf(DayData d) => d.daPlant ?? oldDaPlantId;

  /// Remembers [id] as the DA plant for the next days.
  Future<void> setDaPlant(String id) async {
    final old = oldDaPlantId ?? id;
    if (_daPlantSetting == id && _daPlantOldSetting == old) return;
    await repo.put([
      Rec(Kind.setting, 'daPlant', {'id': id, 'old': old}),
    ]);
  }

  // ------------------------------------------------------ purchase orders

  void _countPoSupplied() {
    _poSupplied.clear();
    _poByEntry.clear();
    for (final d in _days.values) {
      for (final e in d.entries) {
        e.po.forEach((gas, id) {
          final q = e.fullOf(gas);
          if (q == 0) return;
          final m = _poSupplied[id] ??= {};
          m[gas] = (m[gas] ?? 0) + q;
          ((_poByEntry[e.id] ??= {})[id] ??= {})[gas] = q;
        });
      }
    }
  }

  /// A company's POs, oldest first (none for most companies).
  List<PurchaseOrder> posOf(String? companyId) =>
      [
        for (final p in _pos.values)
          if (p.companyId == companyId) p,
      ]..sort((a, b) {
        final m = a.made.compareTo(b.made);
        return m != 0 ? m : a.id.compareTo(b.id);
      });

  bool hasPos(String? companyId) =>
      _pos.values.any((p) => p.companyId == companyId);

  PurchaseOrder? po(String id) => _pos[id];

  /// Full cylinders of [gas] supplied against [poId] (own + loan), leaving
  /// out the saved entry [exceptEntry] (the one being changed).
  int poSupplied(String poId, String gas, {String? exceptEntry}) {
    final all = _poSupplied[poId]?[gas] ?? 0;
    final own = exceptEntry == null
        ? 0
        : (_poByEntry[exceptEntry]?[poId]?[gas] ?? 0);
    return all - own;
  }

  PoLine poLine(PurchaseOrder p, String gas, {String? exceptEntry}) =>
      PoLine(p, gas, poSupplied(p.id, gas, exceptEntry: exceptEntry));

  /// Every gas of every PO of [companyId] (all companies when null).
  List<PoLine> poLines({String? companyId}) => [
    for (final p in companyId == null ? _allPos : posOf(companyId))
      for (final g in kGases)
        if (p.hasGas(g.code)) poLine(p, g.code),
  ];

  List<PurchaseOrder> get _allPos => [
    for (final c in activeCompanies) ...posOf(c.id),
  ];

  /// POs supplied in full (or more), then the ones almost finished: for
  /// the dashboard, so a new PO is asked for in time.
  List<PoLine> poAlerts() {
    final lines = poLines().where((l) => l.done || l.nearlyDone).toList();
    lines.sort((a, b) {
      if (a.done != b.done) return a.done ? -1 : 1;
      return a.left.compareTo(b.left);
    });
    return lines;
  }

  /// Which PO each gas in [gases] counts against for [companyId]:
  /// [chosen] when it has that gas, else the oldest PO with some of that
  /// gas still to supply, else the newest PO that has the gas (so supplying
  /// more than ordered shows up). [kNoPo] = none at all.
  Map<String, String> poLinksFor(
    String? companyId,
    Iterable<String> gases, {
    String? chosen,
    String? exceptEntry,
  }) {
    if (chosen == kNoPo) return {};
    final pos = posOf(companyId);
    final pick = chosen == null ? null : _pos[chosen];
    final out = <String, String>{};
    for (final gas in gases) {
      if (pick != null && pick.companyId == companyId && pick.hasGas(gas)) {
        out[gas] = pick.id;
        continue;
      }
      final withGas = pos.where((p) => p.hasGas(gas)).toList();
      if (withGas.isEmpty) continue;
      final open = withGas.where(
        (p) => !poLine(p, gas, exceptEntry: exceptEntry).done,
      );
      out[gas] = (open.isNotEmpty ? open.first : withGas.last).id;
    }
    return out;
  }

  /// The PO a new entry for [companyId] starts with: the oldest one with
  /// something still to supply, else the newest. Null when it has none.
  String? defaultPo(String? companyId) {
    final pos = posOf(companyId);
    if (pos.isEmpty) return null;
    for (final p in pos) {
      if (p.items.keys.any((g) => !poLine(p, g).done)) return p.id;
    }
    return pos.last.id;
  }

  /// The PO number shown for [gas] of an entry ("" when none).
  String poNumberOf(Entry e, String gas) {
    final id = e.po[gas];
    if (id == null) return '';
    return _pos[id]?.number ?? e.poNo[gas] ?? '';
  }

  Future<PurchaseOrder> addPo(
    String companyId,
    String number,
    Map<String, int> items,
  ) async {
    final p = PurchaseOrder(
      id: newId(),
      companyId: companyId,
      number: number.trim(),
      items: items,
      // Always after the company's last PO, even when added in a hurry.
      made: max(
        DateTime.now().microsecondsSinceEpoch,
        posOf(companyId).fold(0, (m, p) => max(m, p.made)) + 1,
      ),
    );
    await savePo(p);
    return p;
  }

  Future<void> savePo(PurchaseOrder p) =>
      repo.put([Rec(Kind.setting, 'po_${p.id}', p.toJson())]);

  /// Removes a PO. Entries that were supplied against it keep its number.
  Future<void> removePo(PurchaseOrder p) =>
      repo.put([Rec(Kind.setting, 'po_${p.id}', p.toJson(), deleted: true)]);

  // ------------------------------------------------------ stock remark

  /// The stock note on [gas] for [date]: written that day, or carried on
  /// from the last day it was written ([from] = that day). Null = none.
  ({String text, String from})? stockRemarkOn(String date, String gas) =>
      _stockRemark(date, gas, sameDay: true);

  ({String text, String from})? _stockRemark(
    String date,
    String gas, {
    required bool sameDay,
  }) {
    final dates = savedDates;
    for (var i = dates.length - 1; i >= 0; i--) {
      final d = dates[i], c = d.compareTo(date);
      if (c > 0 || (c == 0 && !sameDay)) continue;
      final t = _days[d]!.stockRemarks[gas];
      if (t == null) continue;
      return t.isEmpty ? null : (text: t, from: d);
    }
    return null;
  }

  /// Writes the stock note on [gas] for [date] (it goes on to the next
  /// days). An empty [text] clears it from this day on.
  Future<void> setStockRemark(String date, String gas, String text) async {
    final t = text.trim();
    final day = this.day(date);
    if (t.isNotEmpty) {
      day.stockRemarks[gas] = t;
    } else if (_stockRemark(date, gas, sameDay: false) != null) {
      day.stockRemarks[gas] = ''; // stops the one from an earlier day
    } else {
      day.stockRemarks.remove(gas);
    }
    await saveDay(day);
  }

  // ------------------------------------------------------ plant report

  /// Every day something went to or came from [plantId] (oldest first):
  /// empties sent and filled cylinders back, by gas. DA counts at the
  /// plant it was swapped at.
  List<PlantDay> plantDays(String plantId, {String? from, String? to}) {
    final out = <PlantDay>[];
    for (final date in savedDates) {
      if (from != null && date.compareTo(from) < 0) continue;
      if (to != null && date.compareTo(to) > 0) continue;
      final d = _days[date]!;
      final sent = <String, int>{}, filled = <String, int>{};
      if (d.plant != null) {
        // Old way (count at the plant typed): the change in the count.
        for (final r in stock(date).rows) {
          if (!r.gas.canKeepAtPlant) continue;
          for (final l in r.plantLines) {
            if (l.plantId != plantId) continue;
            final change = l.close - l.open;
            if (change > 0) sent[r.gas.code] = change;
            if (change < 0) filled[r.gas.code] = -change;
          }
        }
      } else {
        d.plantSent.forEach((gas, byPlant) {
          final v = byPlant[plantId] ?? 0;
          if (v != 0) sent[gas] = v;
        });
        d.plantFilled.forEach((gas, byPlant) {
          final v = byPlant[plantId] ?? 0;
          if (v != 0) filled[gas] = v;
        });
      }
      if (daPlantOf(d) == plantId) {
        if (d.daEmptyGiven != 0) sent['DA'] = d.daEmptyGiven;
        final f = d.filling['DA'] ?? 0;
        if (f != 0) filled['DA'] = f;
      }
      // Loan cylinders taken from / given back to this plant.
      final loanIn = <String, int>{}, loanBack = <String, int>{};
      d.loanIn.forEach((gas, byPlant) {
        final v = byPlant[plantId] ?? 0;
        if (v != 0) loanIn[gas] = v;
      });
      for (final m in [d.loanBackEmpty, d.loanBackFull]) {
        m.forEach((gas, byPlant) {
          final v = byPlant[plantId] ?? 0;
          if (v != 0) loanBack[gas] = (loanBack[gas] ?? 0) + v;
        });
      }
      // Notes written on this plant's filling lines (ARGON).
      final remarks = <String, String>{};
      d.fillingRemarks.forEach((k, v) {
        final at = k.indexOf('|');
        if (at > 0 && k.substring(at + 1) == plantId) {
          remarks[k.substring(0, at)] = v;
        }
      });
      if (sent.isNotEmpty ||
          filled.isNotEmpty ||
          loanIn.isNotEmpty ||
          loanBack.isNotEmpty ||
          remarks.isNotEmpty) {
        out.add(
          PlantDay(
            date,
            sent,
            filled,
            loanIn: loanIn,
            loanBack: loanBack,
            remarks: remarks,
          ),
        );
      }
    }
    return out;
  }

  /// Empties of each gas waiting at [plantId] at the end of [date].
  Map<String, int> emptiesAtPlant(String plantId, String date) {
    final out = <String, int>{};
    for (final r in stock(date).rows) {
      for (final l in r.plantLines) {
        if (l.plantId == plantId && l.close != 0) out[r.gas.code] = l.close;
      }
    }
    return out;
  }

  /// All entries of a company, oldest first.
  List<DatedEntry> companyEntries(String companyId) {
    final out = <DatedEntry>[];
    for (final d in _days.values) {
      for (final e in d.entries) {
        if (e.companyId == companyId) out.add(DatedEntry(d.date, e));
      }
    }
    return out..sort(compareDated);
  }

  CompanyLedger ledger(String companyId, {String? from, String? to}) =>
      buildLedger(
        _companies[companyId]!,
        companyEntries(companyId),
        from: from,
        to: to,
      );

  /// Every company's cylinders (gas -> qty) at the end of [date].
  Map<String, Map<String, int>> balancesOn(String date) {
    final out = <String, Map<String, int>>{
      for (final c in _companies.values) c.id: Map.of(c.opening),
    };
    for (final d in _days.values) {
      if (d.date.compareTo(date) > 0) continue;
      for (final e in d.entries) {
        final b = out[e.companyId];
        if (b == null) continue;
        e.full.forEach((k, v) => b[k] = (b[k] ?? 0) + v);
        e.empty.forEach((k, v) => b[k] = (b[k] ?? 0) - v);
      }
    }
    return {
      for (final e in out.entries)
        e.key: {
          for (final g in e.value.entries)
            if (g.value != 0) g.key: g.value,
        },
    };
  }

  /// Problems if a company's starting balance were changed to [opening].
  List<StockProblem> problemsIfOpening(
    String companyId,
    Map<String, int> opening,
  ) {
    final c = _companies[companyId];
    if (c == null) return const [];
    final list = companyEntries(companyId);
    return companyProblems(
      company: c,
      before: list,
      after: list,
      openingAfter: opening,
    );
  }

  Future<void> setCompanyOpening(NamedItem c, Map<String, int> opening) {
    c.opening = {
      for (final e in opening.entries)
        if (e.value != 0) e.key: e.value,
    };
    return repo.put([Rec(Kind.company, c.id, c.toJson())]);
  }

  Future<NamedItem> addCompany(String name) =>
      _add(_companies, Kind.company, name);
  Future<NamedItem> addPlant(String name) => _add(_plants, Kind.plant, name);

  Future<NamedItem> _add(
    Map<String, NamedItem> items,
    String kind,
    String name,
  ) async {
    final clean = name.trim();
    // Re-use an item with the same name instead of making a duplicate.
    for (final it in items.values) {
      if (it.name.toLowerCase() == clean.toLowerCase()) {
        it
          ..active = true
          ..name = clean;
        await repo.put([Rec(kind, it.id, it.toJson())]);
        return it;
      }
    }
    final item = NamedItem(id: newId(), name: clean);
    await repo.put([Rec(kind, item.id, item.toJson())]);
    return _companies[item.id] ?? _plants[item.id] ?? item;
  }

  Future<void> renameCompany(NamedItem it, String name) =>
      _update(Kind.company, it..name = name.trim());
  Future<void> renamePlant(NamedItem it, String name) =>
      _update(Kind.plant, it..name = name.trim());
  Future<void> removeCompany(NamedItem it) =>
      _update(Kind.company, it..active = false);
  Future<void> removePlant(NamedItem it) =>
      _update(Kind.plant, it..active = false);

  Future<void> _update(String kind, NamedItem it) =>
      repo.put([Rec(kind, it.id, it.toJson())]);

  // ------------------------------------------------------------ cash types

  Future<void> addCashType(String name) async {
    final clean = name.trim();
    if (clean.isEmpty ||
        cashTypes.any((t) => t.toLowerCase() == clean.toLowerCase())) {
      return;
    }
    await _saveCashTypes([...cashTypes, clean]);
  }

  Future<void> removeCashType(String name) => _saveCashTypes([
    for (final t in cashTypes)
      if (t != name) t,
  ]);

  Future<void> _saveCashTypes(List<String> list) => repo.put([
    Rec(Kind.setting, 'cashTypes', {'values': list}),
  ]);

  @override
  void dispose() {
    repo.removeListener(_onRepo);
    super.dispose();
  }
}
