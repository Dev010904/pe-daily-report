import 'dart:convert';

import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/records.dart';
import 'package:daily_report/logic/stock.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:daily_report/models/gas.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Saved records from before AR SPL was removed.
MemoryLocalDb oldRecords() {
  final db = MemoryLocalDb();
  void put(String kind, String id, Map<String, dynamic> data) =>
      db.rows['$kind/$id'] = LocalRow(Rec(kind, id, data));
  put(Kind.plant, 'p1', {'name': 'Ambika'});
  put(Kind.company, 'c1', {
    'name': 'Sharma',
    'opening': {'AR_SPL': 4, 'O2': 1},
  });
  put(Kind.company, 'c2', {'name': 'Patel'});
  put(Kind.day, '2026-10-01', {
    'openFull': {'AR_COMM': 5, 'AR_SPL': 3},
    'openEmpty': {'AR_SPL': 2},
  });
  put(Kind.day, '2026-10-02', {
    'plantSent': {
      'AR_SPL': {'p1': 2},
    },
    'damagedEmpty': {'AR_SPL': 1},
  });
  put(Kind.entry, 'e1', {
    'date': '2026-10-02',
    'sort': 1,
    'companyId': 'c1',
    'company': 'Sharma',
    'full': {'AR_SPL': 1},
    'empty': {'AR_SPL': 1},
  });
  put(Kind.entry, 'e2', {
    'date': '2026-10-02',
    'sort': 2,
    'companyId': 'c2',
    'company': 'Patel',
    'full': {'AR_COMM': 1, 'AR_SPL': 1},
    'empty': {},
  });
  // A hand-corrected ARGON opening while AR SPL still had stock.
  put(Kind.day, '2026-10-03', {
    'openFull': {'AR_COMM': 10},
    'plantFilled': {
      'AR_SPL': {'p1': 2},
    },
  });
  return db;
}

Map<String, DayData> rawDays(MemoryLocalDb db) {
  final metas = <String, Map<String, dynamic>>{};
  final entries = <String, List<Entry>>{};
  for (final r in db.rows.values) {
    if (r.rec.kind == Kind.day) metas[r.rec.id] = r.rec.data;
    if (r.rec.kind == Kind.entry) {
      (entries[r.rec.data['date'] as String] ??= []).add(
        Entry.fromJson(r.rec.id, r.rec.data),
      );
    }
  }
  return {
    for (final d in {...metas.keys, ...entries.keys})
      d: DayData.fromMeta(d, metas[d] ?? const {}, entries[d]),
  };
}

void main() {
  test('AR SPL is no longer a gas', () {
    expect(kGases.map((g) => g.code), isNot(contains('AR_SPL')));
    expect(gasLabel('AR_SPL'), 'AR SPL'); // old records can still be named
  });

  test('old AR SPL counts as ARGON, exactly, every day', () async {
    final db = oldRecords();
    final raw = StockBook(rawDays(db), gases: [...kGases, kRetiredArgonSpl]);
    final store = await newStore(db: db);
    expect(store.hasUnsavedSplMerge, isTrue);

    for (final date in [
      '2026-10-01',
      '2026-10-02',
      '2026-10-03',
      '2026-10-04',
    ]) {
      final r = raw.dayStock(date), m = store.stock(date).row('AR_COMM');
      final c = r.row('AR_COMM'), s = r.row('AR_SPL');
      expect(m.openFull, c.openFull + s.openFull, reason: '$date open full');
      expect(m.closeFull, c.closeFull + s.closeFull, reason: '$date full');
      expect(
        m.closeGodown,
        c.closeGodown + s.closeGodown,
        reason: '$date empty',
      );
      expect(
        m.plantClose,
        c.plantClose + s.plantClose,
        reason: '$date at plant',
      );
      expect(
        m.damagedClose,
        c.damagedClose + s.damagedClose,
        reason: '$date damaged',
      );
    }
    // The hand-corrected 10 ARGON + the 1 AR SPL left = 11.
    expect(store.stock('2026-10-03').row('AR_COMM').openFull, 11);
    expect(store.problemsIfSaved(store.day('2026-10-03')), isEmpty);

    // Entries: merged, with the remark.
    final day = store.day('2026-10-02');
    final e1 = day.entries.firstWhere((e) => e.id == 'e1');
    final e2 = day.entries.firstWhere((e) => e.id == 'e2');
    expect(e1.full, {'AR_COMM': 1});
    expect(e1.empty, {'AR_COMM': 1});
    expect(e1.remarks, {'AR_COMM': 'ARGON SPL'});
    expect(e2.full, {'AR_COMM': 2});
    expect(e2.remarks, {'AR_COMM': 'ARGON SPL: 1 full'});
    // Company starting stock.
    expect(store.company('c1')!.opening, {'AR_COMM': 4, 'O2': 1});
    expect(store.balancesOn('2026-10-02')['c1'], {'AR_COMM': 4, 'O2': 1});

    // Saved for good: no AR SPL left in any record, same stock afterwards.
    await store.saveSplMerge();
    final all = jsonEncode([for (final r in db.rows.values) r.rec.data]);
    expect(all.contains('AR_SPL'), isFalse);
    final again = await newStore(db: db);
    expect(again.hasUnsavedSplMerge, isFalse);
    for (final date in ['2026-10-01', '2026-10-02', '2026-10-03']) {
      final a = again.stock(date).row('AR_COMM'),
          b = store.stock(date).row('AR_COMM');
      expect(
        [a.openFull, a.closeFull, a.closeGodown, a.plantClose, a.damagedClose],
        [b.openFull, b.closeFull, b.closeGodown, b.plantClose, b.damagedClose],
        reason: date,
      );
    }
    expect(
      again.day('2026-10-02').entries.firstWhere((e) => e.id == 'e1').remarks,
      {'AR_COMM': 'ARGON SPL'},
    );
  });

  test('remarks are saved with the entry', () {
    final e = Entry.fromJson('x', {
      'company': 'A',
      'full': {'O2': 1},
      'empty': {},
      'remarks': {'O2': 'urgent', 'CO2': '  '},
    });
    expect(e.remarks, {'O2': 'urgent'});
    expect(e.toJson()['remarks'], {'O2': 'urgent'});
  });
}
