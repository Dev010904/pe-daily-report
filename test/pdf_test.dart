import 'dart:io';

import 'package:daily_report/data/store.dart';
import 'package:daily_report/export/company_pdf.dart';
import 'package:daily_report/export/day_pdf.dart';
import 'package:daily_report/export/plant_pdf.dart';
import 'package:daily_report/logic/plant_report.dart';
import 'package:daily_report/export/register_pdf.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Builds every PDF from sample data, checks they are real PDFs and saves
/// them to build/test_output so they can be looked at.
Future<AppStore> sample() async {
  final store = await newStore();
  final plant = await store.addPlant('Ambika Gases');
  final a = await store.addCompany('Patel Steel Works');
  final b = await store.addCompany('Shree Ganesh Fabricators & Co.');
  final g = await store.addCompany('શ્રી અંબિકા એન્જિનિયરિંગ');
  await store.setCompanyOpening(store.company(b.id)!, {'DA': 4});
  await store.saveDay(
    DayData(
      '2026-04-01',
      openFull: {
        'O2': 40,
        'CO2': 30,
        'AR_COMM': 12,
        'DA': 10,
        'N2_COMM': 8,
        'LC': 2,
      },
      openEmpty: {'O2': 20, 'CO2': 25, 'DA': 12},
    ),
  );
  for (var i = 0; i < 200; i++) {
    final date = DateTime(2026, 4, 2).add(Duration(days: i));
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    // Day 3 is written the old way (plant count typed); the rest send
    // empties to the plant and get them back filled.
    final oldWay = i == 3;
    final o2Sent = i % 5 == 0 ? 6 : (i % 5 == 1 ? 2 : 4);
    final d = DayData(
      key,
      filling: oldWay ? {'O2': 4, 'CO2': 2, 'DA': 1} : {'DA': 1},
      daEmptyGiven: i % 7 == 0 ? 2 : 0,
      plantSent: oldWay
          ? null
          : {
              'O2': {plant.id: o2Sent},
              if (i.isEven) 'CO2': {plant.id: 2},
            },
      plantFilled: oldWay
          ? null
          : {
              'O2': {plant.id: 4},
              if (i.isEven) 'CO2': {plant.id: 2},
            },
      plant: oldWay
          ? {
              'CO2': {plant.id: 4},
            }
          : null,
    );
    // 8 Apr: filled back in two goes, and some cylinders became damaged;
    // 9 Apr: one damaged cylinder repaired into CO2.
    if (i == 6) {
      d.plantFilledSteps = {
        'O2': {
          plant.id: [3, 1],
        },
      };
      d.damagedEmpty = {'CO2': 1};
      d.damagedFull = {'O2': 1};
    }
    if (i == 7) d.repaired = {'CO2': 1};
    // 12 Apr: 20 ARGON on loan from the plant; 10 go to Patel the same day,
    // 4 come back empty on the 14th and go back to the plant on the 16th.
    if (i == 10) {
      d.loanIn = {
        'AR_COMM': {plant.id: 20},
      };
    }
    if (i == 14) {
      d.loanBackEmpty = {
        'AR_COMM': {plant.id: 4},
      };
    }
    d.entries.addAll([
      entry(
          a.name,
          companyId: a.id,
          full: {'O2': 2, 'CO2': 1},
          empty: {'O2': 2, 'CO2': 1},
          billed: i.isEven,
        )
        ..challan = '${1000 + i * 3}'
        ..loanFull = i == 10
            ? {
                'AR_COMM': {plant.id: 10},
              }
            : {}
        ..loanEmpty = i == 12
            ? {
                'AR_COMM': {plant.id: 4},
              }
            : {},
      entry(
        b.name,
        companyId: b.id,
        full: {'O2': 1, 'DA': 1},
        empty: {'O2': 1, 'DA': 1},
        cash: i % 10 == 0
            ? [CashItem(type: 'Payment', amount: 2500, mode: kModeGpay)]
            : null,
      )..challan = '${1001 + i * 3}',
      entry(g.name, companyId: g.id, full: {'O2': 1}, empty: {'O2': 1})
        ..challan = '${1002 + i * 3}',
    ]);
    expect(
      store.problemsIfSaved(d).map((p) => p.message),
      isEmpty,
      reason: key,
    );
    await store.saveDay(d);
  }
  return store;
}

void main() {
  late AppStore store;
  final out = Directory('build/test_output')..createSync(recursive: true);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    store = await sample();
  });

  void save(String name, List<int> bytes) {
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    File('${out.path}/$name').writeAsBytesSync(bytes);
  }

  test('daily report PDF (one day and a month)', () async {
    save('day.pdf', await buildDayPdf(store, ['2026-04-05']));
    save('day_plant.pdf', await buildDayPdf(store, ['2026-04-08']));
    final month = store.savedDates
        .where((d) => d.startsWith('2026-05'))
        .toList();
    save('month.pdf', await buildDayPdf(store, month));
    expect(dayPdfFileName(['2026-04-05']), 'PE_Daily_Report_05-04-2026.pdf');
  });

  test('business year register PDF', () async {
    final sw = Stopwatch()..start();
    save('year.pdf', await buildRegisterPdf(store, '2026-04-01', '2027-03-31'));
    save(
      'year_small.pdf',
      await buildRegisterPdf(store, '2026-04-01', '2026-05-10'),
    );
    // ignore: avoid_print
    print('year PDF built in ${sw.elapsedMilliseconds} ms');
    expect(
      registerPdfFileName('2026-04-01', '2027-03-31'),
      'PE_Daily_Report_01-04-2026_to_31-03-2027.pdf',
    );
  });

  test('day, company and plant PDFs with loan cylinders', () async {
    final a = store.activeCompanies.firstWhere(
      (c) => c.name.startsWith('Patel'),
    );
    final plant = store.activePlants.single;
    save(
      'day_loan.pdf',
      await buildDayPdf(store, ['2026-04-12', '2026-04-14', '2026-04-16']),
    );
    save(
      'company_loan.pdf',
      await buildCompanyStatementPdf(
        store,
        a.id,
        from: '2026-04-01',
        to: '2026-04-30',
      ),
    );
    save(
      'plant_loan.pdf',
      await buildPlantReportPdf(
        store,
        plant.id,
        from: '2026-04-01',
        to: '2026-04-30',
        group: PlantGroup.day,
        period: 'April 2026',
      ),
    );
    save(
      'plant_loan_months.pdf',
      await buildPlantReportPdf(
        store,
        plant.id,
        group: PlantGroup.month,
        period: 'All',
      ),
    );
    final l = store.stock('2026-04-16').row('AR_COMM').loanLines.single;
    expect(l.closeFull, 10);
    expect(l.closeEmpty, 0);
    expect(l.atCompanies, 6);
    expect(l.toReturn, 16);
  });

  test('company statement and summary PDFs', () async {
    final b = store.activeCompanies.firstWhere(
      (c) => c.name.startsWith('Shree'),
    );
    save(
      'company.pdf',
      await buildCompanyStatementPdf(
        store,
        b.id,
        from: '2026-04-01',
        to: '2026-04-30',
      ),
    );
    save('companies.pdf', await buildCompanySummaryPdf(store, '2026-10-18'));
    expect(
      companyStatementFileName(b.name, from: '2026-04-01', to: '2026-04-30'),
      'PE_Company_Shree_Ganesh_Fabricators_Co_01-04-2026_to_30-04-2026.pdf',
    );
  });
}
