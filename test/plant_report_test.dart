import 'package:daily_report/data/store.dart';
import 'package:daily_report/logic/plant_report.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppStore store;

  setUp(() async {
    store = await newStore();
  });

  test(
    'old DA (no plant saved) counts at Aims Oxygen; stock logic is unchanged',
    () async {
      final ambika = await store.addPlant('Ambika Plant');
      final aims = await store.addPlant('AIMS OXYGEN P. LTD.');
      await store.saveDay(
        DayData(
          '2026-09-30',
          openFull: {'DA': 10},
          openEmpty: {'DA': 20, 'O2': 30},
        ),
      );
      // Written before DA had a plant line: just DA filled and DA empty given.
      await store.saveDay(
        DayData(
          '2026-10-01',
          filling: {'DA': 5},
          daEmptyGiven: 6,
          plantSent: {
            'O2': {ambika.id: 12},
          },
        ),
      );

      expect(store.oldDaPlantId, aims.id);
      expect(store.daPlantId, aims.id);
      expect(store.daPlantOf(store.day('2026-10-01')), aims.id);

      final atAims = store.plantDays(aims.id);
      expect(atAims, hasLength(1));
      expect(atAims.single.key, '2026-10-01');
      expect(atAims.single.filled, {'DA': 5});
      expect(atAims.single.sent, {'DA': 6});
      // Ambika only has its own Oxygen, no DA.
      final atAmbika = store.plantDays(ambika.id);
      expect(atAmbika.single.sent, {'O2': 12});
      expect(atAmbika.single.filled, isEmpty);

      // DA logic as before: filled received added to full, empty given out
      // of the godown, nothing kept at the plant.
      final s = store.stock('2026-10-01');
      expect(s.row('DA').closeFull, 15);
      expect(s.row('DA').closeGodown, 14);
      expect(s.row('DA').plantLines, isEmpty);
      expect(store.emptiesAtPlant(aims.id, '2026-10-01'), isEmpty);
      expect(store.emptiesAtPlant(ambika.id, '2026-10-01'), {'O2': 12});
    },
  );

  test(
    'DA saved at another plant keeps old days at Aims, even after a rename',
    () async {
      final aims = await store.addPlant('Aims Oxygen P Ltd');
      final other = await store.addPlant('Other Gases');
      await store.saveDay(DayData('2026-09-30', openEmpty: {'DA': 20}));
      await store.saveDay(
        DayData('2026-10-01', filling: {'DA': 5}, daEmptyGiven: 6),
      );
      final d = store.day('2026-10-02')
        ..daPlant = other.id
        ..setFillingSteps('DA', [3])
        ..setDaGivenSteps([4]);
      await store.saveDay(d);
      await store.setDaPlant(other.id);

      expect(store.daPlantId, other.id); // new lines start at the last DA plant
      expect(store.oldDaPlantId, aims.id); // old days stay at Aims
      await store.renamePlant(
        store.plants.firstWhere((p) => p.id == aims.id),
        'Aims Gas',
      );
      expect(store.oldDaPlantId, aims.id);

      expect(store.plantDays(aims.id).map((p) => p.key), ['2026-10-01']);
      expect(store.plantDays(other.id).single.filled, {'DA': 3});
      expect(store.plantDays(other.id).single.sent, {'DA': 4});
      // The plant is kept in the saved day.
      expect(store.day('2026-10-02').daPlant, other.id);
    },
  );

  test('daPlant is only written while the day has DA', () {
    final d = DayData('2026-10-02', daPlant: 'p1');
    expect(d.metaJson().containsKey('daPlant'), isFalse);
    d.daEmptyGiven = 2;
    expect(d.metaJson()['daPlant'], 'p1');
    final back = DayData.fromMeta('2026-10-02', d.metaJson(), const []);
    expect(back.daPlant, 'p1');
    back.clearFilling();
    expect(back.daPlant, isNull);
  });

  test('plant report adds up by day, month and business year', () async {
    final p = await store.addPlant('Ambika Plant');
    await store.saveDay(
      DayData('2026-03-01', openEmpty: {'O2': 100, 'CO2': 100}),
    );
    Future<void> day(String date, int sent, int back) => store.saveDay(
      DayData(
        date,
        plantSent: {
          'O2': {p.id: sent},
        },
        plantFilled: {
          'O2': {p.id: back},
        },
      ),
    );
    await day('2026-03-20', 10, 0); // business year 2025-26
    await day('2026-04-02', 5, 8); // 2026-27
    await day('2026-04-15', 0, 4);
    await day('2026-05-01', 6, 6);

    final days = store.plantDays(p.id);
    expect(days.map((d) => d.key), [
      '2026-03-20',
      '2026-04-02',
      '2026-04-15',
      '2026-05-01',
    ]);
    expect(
      groupPlantDays(days, PlantGroup.day).first.key,
      '2026-05-01',
    ); // newest first

    final months = groupPlantDays(days, PlantGroup.month);
    expect(months.map((m) => m.key), ['2026-05', '2026-04', '2026-03']);
    expect(months[1].filled, {'O2': 12});
    expect(months[1].sent, {'O2': 5});

    final years = groupPlantDays(days, PlantGroup.year);
    expect(years.map((y) => y.key), ['2026', '2025']);
    expect(years.first.totalFilled, 18);
    expect(years.last.totalSent, 10);

    final april = store.plantDays(p.id, from: '2026-04-01', to: '2026-04-30');
    expect(totalOf(april).totalFilled, 12);
    expect(businessYearOf('2026-03-31'), 2025);
    expect(businessYearOf('2026-04-01'), 2026);

    // Empties at the plant: 10 + 5 - 8 - 4 + 6 - 6 = 3.
    expect(store.emptiesAtPlant(p.id, '2026-05-01'), {'O2': 3});
  });
}
