import 'package:daily_report/data/store.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppStore store;

  setUp(() async {
    store = await newStore();
  });

  test('sales, closing and empty follow the daily book rules', () async {
    final d = DayData(
      '2026-10-12',
      openFull: {'O2': 20, 'CO2': 10, 'AR_COMM': 8, 'DA': 5},
      openEmpty: {'O2': 10},
      filling: {'O2': 5},
    );
    d.entries.addAll([
      entry('A', full: {'O2': 2, 'CO2': 3, 'AR_COMM': 4}, empty: {'O2': 1}),
      entry('B', full: {'O2': 4, 'DA': 3}, empty: {'O2': 2}),
      entry('C', full: {'CO2': 3}),
    ]);
    await store.saveDay(d);

    final s = store.stock('2026-10-12');
    expect(s.row('O2').sales, 6);
    expect(s.row('CO2').sales, 6);
    expect(s.row('AR_COMM').sales, 4);
    expect(s.row('DA').sales, 3);
    expect(s.row('H2').sales, 0);

    // Closing = opening + filling - sales
    expect(s.row('O2').closeFull, 20 + 5 - 6);
    expect(s.row('CO2').closeFull, 4);

    // Empty = yesterday's empty - filling + total received (summed first)
    expect(s.row('O2').closeGodown, 10 - 5 + 3);
    expect(s.row('O2').emptyCalcText(), '10 − 5 + 3 = 8');
    expect(s.row('O2').emptyCalcText(ascii: true), '10 - 5 + 3 = 8');
    // Nothing happened to H2: only the number
    expect(s.row('H2').emptyCalcText(), '0');
  });

  test(
    'next day opens with yesterday closing, even across empty days',
    () async {
      final d1 = DayData(
        '2026-10-10',
        openFull: {'O2': 20},
        openEmpty: {'O2': 10},
        filling: {'O2': 5},
      );
      d1.entries.add(entry('A', full: {'O2': 6}, empty: {'O2': 3}));
      await store.saveDay(d1);

      final next = store.stock('2026-10-11');
      expect(next.hasPrevious, isTrue);
      expect(next.row('O2').openFull, 19);
      expect(next.row('O2').openGodown, 8);
      expect(next.row('O2').emptyCalcText(), '8');

      // Two days later (nothing saved on the 11th) still carries forward.
      final later = store.stock('2026-10-13');
      expect(later.row('O2').openFull, 19);
      expect(later.row('O2').openGodown, 8);

      // Editing the earlier day flows into later days.
      final edit = store.day('2026-10-10');
      edit.filling = {'O2': 10};
      await store.saveDay(edit);
      expect(store.stock('2026-10-13').row('O2').openFull, 24);
      expect(store.stock('2026-10-13').row('O2').openGodown, 3);
    },
  );

  test('DA filling and DA empty are entered separately', () async {
    final d = DayData(
      '2026-10-12',
      openFull: {'DA': 4},
      openEmpty: {'DA': 10},
      filling: {'DA': 5},
      daEmptyGiven: 3,
    );
    d.entries.add(entry('A', full: {'DA': 2}, empty: {'DA': 1}));
    await store.saveDay(d);
    final r = store.stock('2026-10-12').row('DA');
    expect(r.closeFull, 4 + 5 - 2);
    // filling is NOT subtracted from DA empties; the "given" number is.
    expect(r.closeGodown, 10 - 3 + 1);
    expect(r.emptyCalcText(), '10 − 3 + 1 = 8');
  });

  test('empties sent to a plant come back filled from that plant', () async {
    final abc = await store.addPlant('ABC Plant');
    // Day 1: 40 CO2 empties in the godown, all 40 sent to ABC.
    await store.saveDay(
      DayData(
        '2026-10-01',
        openFull: {'CO2': 10},
        openEmpty: {'CO2': 40},
        plantSent: {
          'CO2': {abc.id: 40},
        },
      ),
    );
    var r = store.stock('2026-10-01').row('CO2');
    expect(r.closeGodown, 0);
    expect(r.closeFull, 10);
    expect(r.emptyCalcText(), '40 − 40 = 0');
    expect(
      r.emptyCalcText(ascii: true, labelPlant: true),
      '40 - 40 (to plant) = 0',
    );
    expect(r.plantLines.single.calcText(), '0 + 40 = 40');

    // Day 2: only 25 come back filled. Full +25, godown stays 0 and the
    // 25 are taken off ABC's empties: 15 still at the plant.
    await store.saveDay(
      DayData(
        '2026-10-02',
        plantFilled: {
          'CO2': {abc.id: 25},
        },
      ),
    );
    r = store.stock('2026-10-02').row('CO2');
    expect(r.fill, 25);
    expect(r.closeFull, 35);
    expect(r.closeGodown, 0);
    expect(r.emptyCalcText(), '0');
    expect(r.plantLines.single.open, 40);
    expect(r.plantLines.single.close, 15);
    expect(r.plantLines.single.calcText(), '40 − 25 = 15');

    // Day 3: nothing happens; the 15 are still waiting at ABC.
    await store.saveDay(DayData('2026-10-03', filling: {'DA': 1}));
    expect(store.stock('2026-10-03').row('CO2').plantClose, 15);

    // More filled back than waiting at the plant is refused...
    expect(
      store
          .problemsIfSaved(
            DayData(
              '2026-10-04',
              plantFilled: {
                'CO2': {abc.id: 20},
              },
            ),
          )
          .single
          .message,
      'CO2 at ABC Plant: only 15 empty there, but 20 filled back (short by 5).',
    );
    // ...and so is sending empties the godown does not have.
    expect(
      store
          .problemsIfSaved(
            DayData(
              '2026-10-04',
              plantSent: {
                'CO2': {abc.id: 5},
              },
            ),
          )
          .single
          .message,
      'CO2 EMPTY: only 0 empty in godown, but 5 sent to plant (short by 5).',
    );

    // A count corrected at the plant (also to 0) is kept after reloading.
    await store.saveDay(
      DayData(
        '2026-10-04',
        openPlant: {
          'CO2': {abc.id: 0},
        },
        openEmpty: {'CO2': 0},
      ),
    );
    final day4 = store.day('2026-10-04');
    expect(day4.openPlant['CO2']![abc.id], 0);
    expect(day4.openEmpty['CO2'], 0);
    expect(store.stock('2026-10-04').row('CO2').plantClose, 0);
  });

  test('old way: plant count typed directly still works', () async {
    final plant = await store.addPlant('Sharma Plant');
    // Day 1: 20 CO2 empties, 12 come back filled, 8 left at the plant.
    await store.saveDay(
      DayData(
        '2026-10-01',
        openEmpty: {'CO2': 20},
        filling: {'CO2': 12},
        plant: {
          'CO2': {plant.id: 8},
        },
      ),
    );
    var r = store.stock('2026-10-01').row('CO2');
    expect(r.closeGodown, 0);
    expect(r.plantDelta, 8);
    expect(r.emptyCalcText(), '20 − 12 − 8 = 0');
    expect(
      r.emptyCalcText(ascii: true, labelPlant: true),
      '20 - 12 - 8 (plant) = 0',
    );
    expect(r.plantLines.single.open, 0);
    expect(r.plantLines.single.close, 8);

    // Day 2: 15 empties come back from customers; plant count carries on.
    final d2 = DayData('2026-10-02');
    d2.entries.add(entry('A', empty: {'CO2': 15}));
    await store.saveDay(d2);
    r = store.stock('2026-10-02').row('CO2');
    expect(r.closeGodown, 15);
    expect(r.plantLines.single.close, 8);
    expect(r.emptyCalcText(), '0 + 15 = 15');

    // Day 3: take 15, get 18 filled back, 5 still at the plant.
    await store.saveDay(
      DayData(
        '2026-10-03',
        filling: {'CO2': 18},
        plant: {
          'CO2': {plant.id: 5},
        },
      ),
    );
    r = store.stock('2026-10-03').row('CO2');
    expect(r.closeGodown, 0);
    expect(r.emptyCalcText(), '15 − 18 + 3 = 0');
    expect(r.plantLines.single.open, 8);
    expect(r.plantLines.single.close, 5);

    // Other gases are untouched and show no plant row.
    expect(store.stock('2026-10-03').row('O2').plantLines, isEmpty);
  });

  test('saving an empty day removes it', () async {
    await store.saveDay(DayData('2026-10-05', filling: {'O2': 1}));
    expect(store.hasData('2026-10-05'), isTrue);
    await store.saveDay(DayData('2026-10-05'));
    expect(store.hasData('2026-10-05'), isFalse);
  });

  test('renaming a company updates old entries, removing keeps them', () async {
    final c = await store.addCompany('Old Name');
    final d = DayData('2026-10-12');
    d.entries.add(
      Entry(id: '1', companyId: c.id, company: c.name, full: {'O2': 1}),
    );
    await store.saveDay(d);
    await store.renameCompany(c, 'New Name');
    expect(store.day('2026-10-12').entries.single.company, 'New Name');
    await store.removeCompany(c);
    expect(store.activeCompanies, isEmpty);
    expect(store.day('2026-10-12').entries.single.company, 'New Name');
    // Adding the same name again brings it back instead of duplicating.
    final again = await store.addCompany('new name');
    expect(again.id, c.id);
    expect(store.activeCompanies.length, 1);
  });

  group('stock never goes below zero', () {
    setUp(() async {
      await store.saveDay(
        DayData(
          '2026-10-10',
          openFull: {'O2': 5, 'DA': 2},
          openEmpty: {'O2': 3, 'DA': 4},
        ),
      );
    });

    test('supplying more full than in stock is refused', () {
      final d = DayData('2026-10-11');
      d.entries.add(entry('A', full: {'O2': 7}));
      final p = store.problemsIfSaved(d);
      expect(p.single.gas.code, 'O2');
      expect(
        p.single.message,
        'Oxygen FULL: only 5 in stock, but 7 supplied (short by 2).',
      );
      d.entries.single.full = {'O2': 5};
      expect(store.problemsIfSaved(d), isEmpty);
    });

    test('filling more than the empties in godown is refused', () {
      final p = store.problemsIfSaved(
        DayData('2026-10-11', filling: {'O2': 4}),
      );
      expect(
        p.single.message,
        'Oxygen EMPTY: only 3 empty in godown, but 4 filled (short by 1).',
      );
      // ...unless empties came back the same day
      final d = DayData('2026-10-11', filling: {'O2': 4});
      d.entries.add(entry('A', empty: {'O2': 2}));
      expect(store.problemsIfSaved(d), isEmpty);
    });

    test('DA empties given and plant empties are checked too', () async {
      expect(
        store
            .problemsIfSaved(DayData('2026-10-11', daEmptyGiven: 5))
            .single
            .message,
        'DA EMPTY: only 4 empty in godown, but 5 given to plant (short by 1).',
      );
      final plant = await store.addPlant('P');
      expect(
        store
            .problemsIfSaved(
              DayData(
                '2026-10-11',
                filling: {'O2': 2},
                plant: {
                  'O2': {plant.id: 2},
                },
              ),
            )
            .single
            .message,
        'Oxygen EMPTY: only 3 empty in godown, but 2 filled + 2 left at plant (short by 1).',
      );
    });

    test('changing an old day cannot break a later day', () async {
      final later = DayData('2026-10-12');
      later.entries.add(entry('A', full: {'O2': 5}));
      await store.saveDay(later);
      // Lowering the opening on the 10th would leave the 12th short.
      final p = store.problemsIfSaved(
        DayData(
          '2026-10-10',
          openFull: {'O2': 3, 'DA': 2},
          openEmpty: {'O2': 3, 'DA': 4},
        ),
      );
      expect(p.single.date, '2026-10-12');
      // Deleting today's filling that later sales rely on is refused too.
      await store.saveDay(DayData('2026-10-11', filling: {'DA': 1}));
      final sale = store.day('2026-10-12')
        ..entries.add(entry('B', full: {'DA': 3}));
      await store.saveDay(sale);
      expect(
        store.problemsIfSaved(DayData('2026-10-11')).single.date,
        '2026-10-12',
      );
    });

    test('old wrong days do not block unrelated saves', () async {
      await store.saveDay(
        DayData('2026-10-11', filling: {'O2': 9}),
      ); // saved without check
      expect(store.stock('2026-10-11').row('O2').closeGodown, lessThan(0));
      final d = DayData('2026-10-12');
      d.entries.add(entry('A', full: {'O2': 1}));
      expect(store.problemsIfSaved(d), isEmpty);
    });
  });
}
