import 'package:daily_report/data/store.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppStore store;
  late String abc, sharma, patel, mehta;

  setUp(() async {
    store = await newStore();
    abc = (await store.addPlant('ABC Plant')).id;
    sharma = (await store.addCompany('Sharma Steel')).id;
    patel = (await store.addCompany('Patel Works')).id;
    mehta = (await store.addCompany('Mehta Fab')).id;
    await store.saveDay(
      DayData(
        '2026-10-01',
        openFull: {'AR_COMM': 5},
        openEmpty: {'AR_COMM': 3},
      ),
    );
  });

  Entry loanTo(
    String companyId,
    String name, {
    int full = 0,
    int empty = 0,
    Map<String, int>? ours,
  }) => entry(name, companyId: companyId, full: ours, empty: const {})
    ..loanFull = full == 0
        ? {}
        : {
            'AR_COMM': {abc: full},
          }
    ..loanEmpty = empty == 0
        ? {}
        : {
            'AR_COMM': {abc: empty},
          };

  test(
    '20 ARGON on loan from ABC: 10 + 5 + 3 supplied, 2 left in the godown',
    () async {
      final d = store.day('2026-10-02')
        ..loanIn = {
          'AR_COMM': {abc: 20},
        };
      d.entries.addAll([
        loanTo(sharma, 'Sharma Steel', full: 10),
        loanTo(patel, 'Patel Works', full: 5),
        loanTo(mehta, 'Mehta Fab', full: 3, ours: {'AR_COMM': 2}),
      ]);
      expect(store.problemsIfSaved(d), isEmpty);
      await store.saveDay(d);

      final s = store.stock('2026-10-02');
      final r = s.row('AR_COMM');
      // Our own cylinders are not mixed with the loan ones.
      expect(r.sales, 2);
      expect(r.closeFull, 3);
      final l = r.loanLines.single;
      expect(l.plantId, abc);
      expect(l.fullCalcText(), '0 + 20 − 18 = 2');
      expect(l.closeFull, 2);
      expect(l.atCompanies, 18);
      expect(l.toReturn, 20);
      expect(s.loanToReturn, 20);
      expect(store.loanCompaniesFor('AR_COMM', abc, '2026-10-02'), {
        'Sharma Steel': 10,
        'Patel Works': 5,
        'Mehta Fab': 3,
      });
      expect(store.loanWithCompany(sharma, '2026-10-02'), {
        'AR_COMM': {abc: 10},
      });
      // A bill is needed for loan cylinders supplied.
      expect(d.entries.first.needsBill, isTrue);
    },
  );

  test(
    'loan empties come back mixed with ours, then go back to the plant',
    () async {
      final d2 = store.day('2026-10-02')
        ..loanIn = {
          'AR_COMM': {abc: 20},
        };
      d2.entries.add(loanTo(sharma, 'Sharma Steel', full: 10));
      await store.saveDay(d2);

      // Sharma gives back 4 loan empties and 2 of ours (they had 0 of ours,
      // so ours needs a starting stock: give them 2 of ours first).
      final d3 = store.day('2026-10-03');
      d3.entries.add(
        entry('Sharma Steel', companyId: sharma, full: {'AR_COMM': 2}),
      );
      d3.entries.add(
        loanTo(sharma, 'Sharma Steel', empty: 4)..empty = {'AR_COMM': 2},
      );
      expect(store.problemsIfSaved(d3), isEmpty);
      await store.saveDay(d3);
      var l = store.stock('2026-10-03').row('AR_COMM').loanLines.single;
      expect(l.emptyCalcText(), '0 + 4 = 4');
      expect(l.atCompanies, 6);
      expect(store.stock('2026-10-03').row('AR_COMM').received, 2);

      // Back to ABC: the 4 empties and the 10 full ones not supplied.
      final d4 = store.day('2026-10-04')
        ..loanBackEmpty = {
          'AR_COMM': {abc: 4},
        }
        ..loanBackFull = {
          'AR_COMM': {abc: 10},
        };
      expect(store.problemsIfSaved(d4), isEmpty);
      await store.saveDay(d4);
      l = store.stock('2026-10-04').row('AR_COMM').loanLines.single;
      expect(l.closeEmpty, 0);
      expect(l.closeFull, 0);
      expect(l.toReturn, 6); // still with Sharma Steel

      // The plant report shows what was taken and given back.
      final days = store.plantDays(abc);
      expect(days.map((p) => p.key), ['2026-10-02', '2026-10-04']);
      expect(days.first.loanIn, {'AR_COMM': 20});
      expect(days.last.loanBack, {'AR_COMM': 14});
    },
  );

  test('nothing about loan cylinders can go below zero', () async {
    final d2 = store.day('2026-10-02')
      ..loanIn = {
        'AR_COMM': {abc: 20},
      };
    d2.entries.add(loanTo(sharma, 'Sharma Steel', full: 10));
    await store.saveDay(d2);

    final tooMany = store.day('2026-10-03');
    tooMany.entries.add(loanTo(patel, 'Patel Works', full: 11));
    expect(
      store.problemsIfSaved(tooMany).single.message,
      'ARGON LOAN from ABC Plant: only 10 loan cylinders full in godown, '
      'but 11 supplied (short by 1).',
    );

    final notTheirs = store.day('2026-10-03');
    notTheirs.entries.add(loanTo(patel, 'Patel Works', empty: 1));
    expect(
      store.problemsIfSaved(notTheirs).single.message,
      'Patel Works – ARGON LOAN from ABC Plant: they have only 0 loan cylinders, '
      'but 1 loan empty received (short by 1).',
    );

    final noEmpties = store.day('2026-10-03')
      ..loanBackEmpty = {
        'AR_COMM': {abc: 1},
      };
    expect(
      store.problemsIfSaved(noEmpties).single.message,
      'ARGON LOAN from ABC Plant: only 0 loan empties in godown, '
      'but 1 given back empty (short by 1).',
    );

    // Taking the loan away on the 2nd would break the supply already made.
    final p = store.problemsIfSaved(store.day('2026-10-02')..loanIn = {});
    expect(p, isNotEmpty);
  });

  test('loan parts are saved, and parts from a newer app are kept', () {
    final e = Entry.fromJson('e1', {
      'company': 'X',
      'full': {},
      'empty': {},
      'loanFull': {
        'AR_COMM': {'p1': 3},
      },
      'future': 'keep me',
      'date': '2026-10-02',
    });
    expect(e.loanFull, {
      'AR_COMM': {'p1': 3},
    });
    final j = e.toJson();
    expect(j['future'], 'keep me');
    expect(j.containsKey('date'), isFalse);
    expect(j['loanFull'], {
      'AR_COMM': {'p1': 3},
    });

    final d = DayData.fromMeta('2026-10-02', {
      'loanIn': {
        'AR_COMM': {'p1': 20},
      },
      'loanBackEmpty': {
        'AR_COMM': {'p1': 4},
      },
    });
    expect(d.loanIn, {
      'AR_COMM': {'p1': 20},
    });
    expect(d.metaJson()['loanBackEmpty'], {
      'AR_COMM': {'p1': 4},
    });
    expect(d.metaEmpty, isFalse);
  });
}
