import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../logic/ledger.dart';
import '../logic/plant_report.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
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
  String? _daPlantSetting;
  String? _daPlantOldSetting;
  StockBook? _book;
  int _seen = -1;

  void _onRepo() {
    if (repo.dataVersion != _seen) _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    _seen = repo.dataVersion;
    _companies.clear();
    _plants.clear();
    _days.clear();
    cashTypes = List.of(kDefaultCashTypes);
    _vehicles.clear();
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
    _book = null;
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

  Future<void> removeVehicle(Vehicle v) =>
      repo.put([Rec(Kind.setting, 'vehicle_${v.id}', v.toJson(), deleted: true)]);

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
        if (!out.any((t) => t.toLowerCase() == p.type.toLowerCase())) out.add(p.type);
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
      if (sent.isNotEmpty ||
          filled.isNotEmpty ||
          loanIn.isNotEmpty ||
          loanBack.isNotEmpty) {
        out.add(
          PlantDay(date, sent, filled, loanIn: loanIn, loanBack: loanBack),
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
