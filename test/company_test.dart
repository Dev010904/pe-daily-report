import 'package:daily_report/data/store.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppStore store;
  late NamedItem abc;

  setUp(() async {
    store = await newStore();
    abc = await store.addCompany('ABC Industries');
    // Enough godown stock so only company rules matter here.
    await store.saveDay(
      DayData('2026-10-01', openFull: {'O2': 100, 'CO2': 100}),
    );
  });

  Future<void> add(
    String date, {
    Map<String, int>? full,
    Map<String, int>? empty,
    String challan = '',
  }) async {
    final d = store.day(date);
    d.entries.add(
      entry(abc.name, companyId: abc.id, full: full, empty: empty)
        ..challan = challan,
    );
    expect(store.problemsIfSaved(d), isEmpty);
    await store.saveDay(d);
  }

  test(
    'company balance = starting balance + supplied - empty received',
    () async {
      await add('2026-10-02', full: {'O2': 2}, challan: '101');
      await add(
        '2026-10-03',
        full: {'O2': 4, 'CO2': 1},
        empty: {'O2': 1},
        challan: '102',
      );
      await add('2026-10-05', empty: {'O2': 3}, challan: '103');

      expect(store.balancesOn('2026-10-03')[abc.id], {'O2': 5, 'CO2': 1});
      expect(store.balancesOn('2026-10-05')[abc.id], {'O2': 2, 'CO2': 1});

      final led = store.ledger(abc.id);
      expect(led.lines.map((l) => l.entry.challan), ['101', '102', '103']);
      expect(led.lines.map((l) => l.after['O2']), [2, 5, 2]);
      expect(led.supplied, {'O2': 6, 'CO2': 1});
      expect(led.received, {'O2': 4});
      expect(led.end, {'O2': 2, 'CO2': 1});
      expect(led.gases.map((g) => g.code), ['O2', 'CO2']);

      // A period shows the balance carried in from before it.
      final oct3to5 = store.ledger(
        abc.id,
        from: '2026-10-03',
        to: '2026-10-05',
      );
      expect(oct3to5.start, {'O2': 2});
      expect(oct3to5.lines.length, 2);
    },
  );

  test('owner\'s example: ABC has 5 O2 + 5 CO2, gets 4 + 4, returns 3 + 3 empty', () async {
    await store.setCompanyOpening(store.company(abc.id)!, {'O2': 5, 'CO2': 5});
    expect(store.ledger(abc.id).totalEnd, 10);
    // Same entry: 4 O2 and 4 CO2 delivered, 3 O2 and 3 CO2 empties taken back.
    await add(
      '2026-10-02',
      full: {'O2': 4, 'CO2': 4},
      empty: {'O2': 3, 'CO2': 3},
    );
    expect(store.balancesOn('2026-10-02')[abc.id], {'O2': 6, 'CO2': 6});
    final led = store.ledger(abc.id);
    expect(led.end, {'O2': 6, 'CO2': 6});
    expect(led.totalEnd, 12);
    expect(led.lines.single.after, {'O2': 6, 'CO2': 6});
  });

  test('a company cannot return more empties than it has', () async {
    await add('2026-10-02', full: {'O2': 2});
    final d = store.day('2026-10-04');
    d.entries.add(entry(abc.name, companyId: abc.id, empty: {'O2': 3}));
    final p = store.problemsIfSaved(d);
    expect(p.single.gas.code, 'O2');
    expect(
      p.single.message,
      contains('they have only 2 with them, but 3 empty received (short by 1)'),
    );
    expect(p.single.message, contains('Starting Stock'));
  });

  test('starting balance covers cylinders they had before the app', () async {
    expect(store.problemsIfOpening(abc.id, {'O2': 5}), isEmpty);
    await store.setCompanyOpening(store.company(abc.id)!, {'O2': 5});
    final d = store.day('2026-10-04');
    d.entries.add(entry(abc.name, companyId: abc.id, empty: {'O2': 3}));
    expect(store.problemsIfSaved(d), isEmpty);
    await store.saveDay(d);
    expect(store.balancesOn('2026-10-04')[abc.id], {'O2': 2});
    // Lowering the starting balance below what came back is refused.
    expect(store.problemsIfOpening(abc.id, {'O2': 1}).single.gas.code, 'O2');
  });

  test('deleting a supply that empties came back for is refused', () async {
    await add('2026-10-02', full: {'O2': 2});
    await add('2026-10-03', empty: {'O2': 2});
    final d = store.day('2026-10-02')..entries.clear();
    expect(store.problemsIfSaved(d), isNotEmpty);
  });
}
