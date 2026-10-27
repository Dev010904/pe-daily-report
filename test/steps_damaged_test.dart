import 'package:daily_report/data/store.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppStore store;

  setUp(() async {
    store = await newStore();
  });

  group('filling step by step', () {
    test('several fillings in a day add up and every step is shown', () async {
      final plant = await store.addPlant('Ambika');
      await store.saveDay(
        DayData('2026-10-10', openFull: {'O2': 20}, openEmpty: {'O2': 40}),
      );
      final d = store.day('2026-10-11');
      // Morning: 30 sent, 11 back. Later: 10 more sent, 3 more back.
      d.addPlantSteps(sent: true, gas: 'O2', plant: plant.id, steps: [30]);
      d.addPlantSteps(sent: false, gas: 'O2', plant: plant.id, steps: [11]);
      d.addPlantSteps(sent: true, gas: 'O2', plant: plant.id, steps: [10]);
      d.addPlantSteps(sent: false, gas: 'O2', plant: plant.id, steps: [3]);
      expect(d.plantSent['O2']![plant.id], 40);
      expect(d.plantFilled['O2']![plant.id], 14);
      await store.saveDay(d);

      final r = store.stock('2026-10-11').row('O2');
      expect(r.fill, 14);
      expect(r.fillSteps, [11, 3]);
      expect(r.fillStepsText, '+11 +3');
      expect(r.closeFull, 34);
      expect(r.emptyCalcText(), '40 − 30 − 10 = 0');
      expect(r.plantLines.single.calcText(), '0 + 30 + 10 − 11 − 3 = 26');
    });

    test(
      'DA filled and DA given keep their steps; one step shows no list',
      () async {
        await store.saveDay(DayData('2026-10-10', openEmpty: {'DA': 10}));
        final d = store.day('2026-10-11')
          ..setFillingSteps('DA', [5, 7])
          ..setDaGivenSteps([4, 2]);
        await store.saveDay(d);
        final r = store.stock('2026-10-11').row('DA');
        expect(r.fill, 12);
        expect(r.fillStepsText, '+5 +7');
        expect(r.emptyCalcText(), '10 − 4 − 2 = 4');

        final one = store.day('2026-10-11')..setFillingSteps('DA', [9]);
        expect(one.fillingSteps, isEmpty);
        expect(one.fillingStepsOf('DA'), [9]);
      },
    );

    test(
      'steps are saved and read back; wrong steps fall back to the total',
      () {
        final d = DayData('2026-10-11')
          ..setFillingSteps('DA', [5, 7])
          ..setDaGivenSteps([1, 2]);
        final back = DayData.fromMeta(d.date, d.metaJson());
        expect(back.fillingStepsOf('DA'), [5, 7]);
        expect(back.daGivenStepList, [1, 2]);

        // An older app changed the total but not the steps: trust the total.
        final meta = d.metaJson()..['filling'] = {'DA': 20};
        expect(DayData.fromMeta(d.date, meta).fillingStepsOf('DA'), [20]);
      },
    );

    test('parts written by a newer app are kept when saving', () {
      final d = DayData.fromMeta('2026-10-11', {
        'filling': {'O2': 2},
        'somethingNew': {'x': 1},
      });
      expect(d.metaEmpty, isFalse);
      expect(d.metaJson()['somethingNew'], {'x': 1});
      expect(d.copy().metaJson()['somethingNew'], {'x': 1});
    });
  });

  group('damaged cylinders', () {
    setUp(() async {
      await store.saveDay(
        DayData(
          '2026-10-10',
          openFull: {'O2': 10, 'CO2': 5},
          openEmpty: {'O2': 8, 'CO2': 6, 'LPG': 3},
        ),
      );
    });

    test(
      'a damaged cylinder keeps its gas: counted as damaged Oxygen etc.',
      () async {
        final d = store.day('2026-10-11')
          ..damagedEmpty = {'O2': 2, 'LPG': 1}
          ..damagedFull = {'CO2': 1};
        expect(store.problemsIfSaved(d), isEmpty);
        await store.saveDay(d);

        final s = store.stock('2026-10-11');
        expect(s.row('O2').closeGodown, 6);
        expect(s.row('O2').emptyCalcText(), '8 − 2 = 6');
        expect(
          s.row('O2').emptyCalcText(labelPlant: true),
          '8 − 2 (damaged) = 6',
        );
        expect(s.row('LPG').closeGodown, 2);
        expect(s.row('CO2').closeFull, 4);
        expect(s.row('CO2').damagedFull, 1);
        expect(s.damagedToday, {'O2': 2, 'LPG': 1, 'CO2': 1});
        // Each gas has its own damaged count; 4 in all.
        expect(s.row('O2').damagedClose, 2);
        expect(s.row('CO2').damagedClose, 1);
        expect(s.row('LPG').damagedClose, 1);
        expect(s.damagedCloseBy, {'O2': 2, 'CO2': 1, 'LPG': 1});
        expect(s.damagedClose, 4);
        expect(s.damagedCalcText(), '0 + 4 = 4');

        // Next day starts with them, gas by gas.
        final next = store.stock('2026-10-12');
        expect(next.row('O2').damagedOpen, 2);
        expect(next.damagedOpen, 4);
        expect(next.damagedCalcText(), '4');
      },
    );

    test('a repair brings back only its own gas, as an empty', () async {
      await store.saveDay(
        store.day('2026-10-11')..damagedEmpty = {'O2': 2, 'CO2': 1},
      );
      final d = store.day('2026-10-12')..repaired = {'O2': 2};
      expect(store.problemsIfSaved(d), isEmpty);
      await store.saveDay(d);
      final s = store.stock('2026-10-12');
      expect(s.row('O2').closeGodown, 8);
      expect(
        s.row('O2').emptyCalcText(labelPlant: true),
        '6 + 2 (repaired) = 8',
      );
      expect(s.row('O2').damagedClose, 0);
      expect(s.row('CO2').damagedClose, 1);
      expect(s.damagedCalcText(), '3 − 2 = 1');

      // 3 damaged, but only 1 is CO2: 3 CO2 can't come back.
      final wrong = store.day('2026-10-12')..repaired = {'CO2': 3};
      expect(
        store.problemsIfSaved(wrong).single.message,
        'DAMAGED CO2: only 1 damaged CO2, but 3 repaired (short by 2). '
        'A damaged cylinder comes back only as its own gas.',
      );
      // And none of a gas that has no damaged ones.
      final none = store.day('2026-10-12')..repaired = {'H2': 1};
      expect(store.problemsIfSaved(none).single.gas.code, 'H2');
    });

    test('cannot damage more than there are', () async {
      final noEmpty = store.day('2026-10-11')..damagedEmpty = {'O2': 9};
      expect(
        store.problemsIfSaved(noEmpty).single.message,
        'Oxygen EMPTY: only 8 empty in godown, but 9 damaged (short by 1).',
      );

      final noFull = store.day('2026-10-11')..damagedFull = {'CO2': 6};
      expect(
        store.problemsIfSaved(noFull).single.message,
        'CO2 FULL: only 5 in stock, but 6 damaged (short by 1).',
      );
    });

    test('a later repair cannot lose the damaged it needs', () async {
      await store.saveDay(store.day('2026-10-11')..damagedEmpty = {'O2': 2});
      await store.saveDay(store.day('2026-10-12')..repaired = {'O2': 2});
      // Taking away the damaged on the 11th would break the 12th.
      final p = store.problemsIfSaved(
        store.day('2026-10-11')..damagedEmpty = {},
      );
      expect(p.single.date, '2026-10-12');
    });

    test(
      'damaged at the start of a day can be set per gas and is saved',
      () async {
        final d = store.day('2026-10-11')..openDamagedGas = {'O2': 5, 'CO2': 2};
        await store.saveDay(d);
        final s = store.stock('2026-10-11');
        expect(s.damagedOpen, 7);
        expect(s.row('O2').damagedOpen, 5);
        expect(s.damagedOpenEdited, isTrue);
        expect(store.stock('2026-10-12').damagedCloseBy, {'O2': 5, 'CO2': 2});
        final back = DayData.fromMeta(
          d.date,
          store.day('2026-10-11').metaJson(),
        );
        expect(back.openDamagedGas, {'O2': 5, 'CO2': 2});
        // A correction down to 0 is kept (the day before had some).
        await store.saveDay(
          store.day('2026-10-12')..openDamagedGas = {'O2': 0},
        );
        expect(store.stock('2026-10-12').damagedCloseBy, {'CO2': 2});
      },
    );

    test('the old count without a gas is kept in the record but not used', () {
      final d = DayData.fromMeta('2026-10-11', {
        'openDamaged': 7,
        'filling': {'O2': 1},
      });
      expect(d.metaJson()['openDamaged'], 7);
      expect(d.openDamagedGas, isEmpty);
    });
  });
}
