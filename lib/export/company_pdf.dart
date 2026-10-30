import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import '../ui/po_field.dart';
import 'pdf_kit.dart';

String companyStatementFileName(String company, {String? from, String? to}) {
  final range = from == null && to == null
      ? fmtDmy(today())
      : '${from == null ? 'start' : fmtDmy(parseDayKey(from))}_to_${to == null ? fmtDmy(today()) : fmtDmy(parseDayKey(to))}';
  return 'PE_Company_${safeName(company)}_$range.pdf';
}

String companySummaryFileName(String date) =>
    'PE_Companies_Cylinders_${fmtDmy(parseDayKey(date))}.pdf';

/// One company: every supply / empty return with the balance after it.
Future<List<int>> buildCompanyStatementPdf(
  AppStore store,
  String companyId, {
  String? from,
  String? to,
}) async {
  final kit = await PdfKit.load();
  final led = store.ledger(companyId, from: from, to: to);
  final doc = kit.doc('Cylinder Statement');
  final gases = led.gases;
  final hasCash = led.lines.any((l) => l.entry.cash.isNotEmpty);
  // Per-gas columns while they fit; otherwise one text column each.
  final perGas = gases.length <= 4;
  final period = from == null && to == null
      ? 'All dates up to ${fmtDmy(today())}'
      : '${from == null ? 'Start' : fmtDmy(parseDayKey(from))} to ${to == null ? fmtDmy(today()) : fmtDmy(parseDayKey(to))}';

  String bal(Map<String, int> m) =>
      orderedQty(m).isEmpty ? 'None' : qtyLines(m, sep: ',  ');

  final rows = <pw.TableRow>[];
  if (perGas) {
    rows.add(
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          headCell('Date'),
          headCell('Challan'),
          headCell('Bill'),
          for (final g in gases) ...[
            headCell('${g.label}\nSupplied', color: PdfC.green),
            headCell('${g.label}\nEmpty'),
            pw.Container(
              color: PdfC.balBg,
              child: headCell('${g.label}\nStock', color: PdfC.navy),
            ),
          ],
          if (hasCash) headCell('Cash Received', align: pw.TextAlign.left),
        ],
      ),
    );
    rows.add(
      pw.TableRow(
        children: [
          cell('At start', italic: true, bold: true, align: pw.TextAlign.left),
          cell(''),
          cell(''),
          for (final g in gases) ...[
            cell(''),
            cell(''),
            pw.Container(
              color: PdfC.balBg,
              child: cell(
                '${led.start[g.code] ?? 0}',
                bold: true,
                color: PdfC.navy,
              ),
            ),
          ],
          if (hasCash) cell(''),
        ],
      ),
    );
    for (final l in led.lines) {
      final e = l.entry;
      rows.add(
        pw.TableRow(
          decoration: stripe(rows.length),
          children: [
            cell(fmtDmy(parseDayKey(l.date))),
            cell(challanWithPo(store, e)),
            billCell(e, size: 9),
            for (final g in gases) ...[
              cell(
                (e.full[g.code] ?? 0) == 0 ? '' : '${e.full[g.code]}',
                color: PdfC.green,
                bold: true,
              ),
              cell((e.empty[g.code] ?? 0) == 0 ? '' : '${e.empty[g.code]}'),
              pw.Container(
                color: PdfC.balBg,
                child: cell(
                  '${l.after[g.code] ?? 0}',
                  bold: true,
                  color: (l.after[g.code] ?? 0) < 0 ? PdfC.red : PdfC.navy,
                ),
              ),
            ],
            if (hasCash)
              cell(
                e.cash
                    .map(
                      (c) =>
                          '${c.type}: ${rs(c.amount)} (${modeLabel(c.mode)})',
                    )
                    .join('\n'),
                align: pw.TextAlign.left,
                color: PdfC.amber,
              ),
          ],
        ),
      );
    }
    final sup = led.supplied, rec = led.received;
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          cell('TOTAL / NOW', bold: true, align: pw.TextAlign.left),
          cell(''),
          cell(''),
          for (final g in gases) ...[
            cell('${sup[g.code] ?? 0}', bold: true, color: PdfC.green),
            cell('${rec[g.code] ?? 0}', bold: true),
            cell(
              '${led.end[g.code] ?? 0}',
              bold: true,
              color: PdfC.navy,
              size: 9.5,
            ),
          ],
          if (hasCash)
            cell(
              'Total: ${rs(led.lines.fold(0.0, (a, l) => a + l.entry.totalCash))}',
              bold: true,
              align: pw.TextAlign.left,
            ),
        ],
      ),
    );
  } else {
    rows.add(
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          headCell('Date'),
          headCell('Challan'),
          headCell('Bill'),
          headCell('Supplied', align: pw.TextAlign.left, color: PdfC.green),
          headCell('Empty Received', align: pw.TextAlign.left),
          headCell('Stock after', align: pw.TextAlign.left, color: PdfC.navy),
          if (hasCash) headCell('Cash Received', align: pw.TextAlign.left),
        ],
      ),
    );
    rows.add(
      pw.TableRow(
        children: [
          cell('Start', italic: true, bold: true),
          cell(''),
          cell(''),
          cell(''),
          cell(''),
          cell(
            bal(led.start),
            bold: true,
            color: PdfC.navy,
            align: pw.TextAlign.left,
          ),
          if (hasCash) cell(''),
        ],
      ),
    );
    for (final l in led.lines) {
      final e = l.entry;
      rows.add(
        pw.TableRow(
          decoration: stripe(rows.length),
          children: [
            cell(fmtDmy(parseDayKey(l.date))),
            cell(challanWithPo(store, e)),
            billCell(e, size: 9),
            cell(
              e.full.isEmpty
                  ? (e.hasLoan ? 'loan only' : '-')
                  : qtyLines(e.full, sep: ', '),
              color: PdfC.green,
              align: pw.TextAlign.left,
            ),
            cell(
              e.empty.isEmpty ? '-' : qtyLines(e.empty, sep: ', '),
              align: pw.TextAlign.left,
            ),
            cell(
              bal(l.after),
              bold: true,
              color: PdfC.navy,
              align: pw.TextAlign.left,
            ),
            if (hasCash)
              cell(
                e.cash
                    .map(
                      (c) =>
                          '${c.type}: ${rs(c.amount)} (${modeLabel(c.mode)})',
                    )
                    .join('\n'),
                align: pw.TextAlign.left,
                color: PdfC.amber,
              ),
          ],
        ),
      );
    }
  }

  doc.addPage(
    pePage(
      format: perGas && gases.length > 2
          ? a4Landscape
          : (perGas ? a4 : a4Landscape),
      title: 'Cylinder Statement',
      detail: '${led.company.name}\n$period',
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.only(bottom: 6),
          decoration: pw.BoxDecoration(
            color: PdfC.balBg,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            children: [
              pw.Text(
                'Cylinder stock at the company at the end of this period:  ',
                style: pw.TextStyle(fontSize: 9.5, color: PdfC.navy),
              ),
              pw.Expanded(
                child: pw.Text(
                  bal(led.end),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfC.navy,
                  ),
                ),
              ),
              pw.Text(
                '${led.totalEnd} cylinders',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfC.navy,
                ),
              ),
            ],
          ),
        ),
        if (led.lines.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(
              'No supply or empty received in this period.',
              style: pw.TextStyle(
                fontStyle: pw.FontStyle.italic,
                color: PdfC.muted,
              ),
            ),
          ),
        pw.Table(
          border: thinBorder,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const pw.FixedColumnWidth(56),
            1: const pw.FixedColumnWidth(46),
            2: const pw.FixedColumnWidth(24),
          },
          children: rows,
        ),
        ..._loanPart(store, companyId, from: from, to: to),
        ..._poPart(store, companyId),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Stock at the company = starting stock + cylinders supplied - empty cylinders received.',
            style: pw.TextStyle(fontSize: 7.5, color: PdfC.muted),
          ),
        ),
      ],
    ),
  );
  return finish(doc);
}

/// Loan cylinders (borrowed from plants) with this company in the period:
/// each supply / empty back and what they have after it. Empty when none.
/// The company's purchase orders: ordered, supplied and left, gas by gas.
List<pw.Widget> _poPart(AppStore store, String companyId) {
  final lines = store.poLines(companyId: companyId);
  if (lines.isEmpty) return const [];
  return [
    section('PURCHASE ORDERS'),
    pw.Table(
      border: thinBorder,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1),
        4: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: PdfC.head),
          children: [
            headCell('PO No.', align: pw.TextAlign.left),
            headCell('Gas', align: pw.TextAlign.left),
            headCell('Ordered'),
            headCell('Supplied', color: PdfC.green),
            headCell('Left'),
          ],
        ),
        for (var i = 0; i < lines.length; i++)
          pw.TableRow(
            decoration: stripe(i),
            children: [
              cell(lines[i].po.number, bold: true, align: pw.TextAlign.left),
              cell(gasLabel(lines[i].gas), align: pw.TextAlign.left),
              cell('${lines[i].ordered}'),
              cell('${lines[i].supplied}', bold: true, color: PdfC.green),
              cell(
                poLeftText(lines[i].left),
                bold: true,
                color: lines[i].done ? PdfC.red : PdfC.navy,
              ),
            ],
          ),
      ],
    ),
  ];
}

List<pw.Widget> _loanPart(
  AppStore store,
  String companyId, {
  String? from,
  String? to,
}) {
  final bal = <String, Map<String, int>>{};
  final rows = <pw.TableRow>[];
  PlantQty? start;
  void apply(Entry e) {
    e.loanFull.forEach(
      (g, m) => m.forEach((p, v) => addPlantQty(bal, g, p, v)),
    );
    e.loanEmpty.forEach(
      (g, m) => m.forEach((p, v) => addPlantQty(bal, g, p, -v)),
    );
    for (final m in bal.values) {
      m.removeWhere((_, v) => v == 0);
    }
    bal.removeWhere((_, m) => m.isEmpty);
  }

  for (final d in store.companyEntries(companyId)) {
    if (to != null && d.date.compareTo(to) > 0) break;
    if (from != null && d.date.compareTo(from) < 0) {
      apply(d.entry);
      continue;
    }
    start ??= {for (final g in bal.entries) g.key: Map.of(g.value)};
    if (!d.entry.hasLoan) continue;
    apply(d.entry);
    rows.add(
      pw.TableRow(
        decoration: stripe(rows.length),
        children: [
          cell(fmtDmy(parseDayKey(d.date))),
          cell(challanWithPo(store, d.entry)),
          cell(
            d.entry.loanFull.isEmpty ? '-' : loanLines(store, d.entry.loanFull),
            align: pw.TextAlign.left,
            color: PdfC.loan,
          ),
          cell(
            d.entry.loanEmpty.isEmpty
                ? '-'
                : loanLines(store, d.entry.loanEmpty),
            align: pw.TextAlign.left,
          ),
          cell(
            bal.isEmpty ? 'None' : loanLines(store, bal),
            bold: true,
            align: pw.TextAlign.left,
          ),
        ],
      ),
    );
  }
  start ??= {for (final g in bal.entries) g.key: Map.of(g.value)};
  if (rows.isEmpty && bal.isEmpty) return const [];
  return [
    section(
      'LOAN CYLINDERS WITH THIS COMPANY (borrowed from plants, to get back)',
    ),
    pw.Table(
      border: thinBorder,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FixedColumnWidth(56),
        1: pw.FixedColumnWidth(46),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: PdfC.loanBg),
          children: [
            headCell('Date', color: PdfC.loan),
            headCell('Challan', color: PdfC.loan),
            headCell(
              'Loan supplied',
              align: pw.TextAlign.left,
              color: PdfC.loan,
            ),
            headCell(
              'Loan empty back',
              align: pw.TextAlign.left,
              color: PdfC.loan,
            ),
            headCell(
              'Loan with them after',
              align: pw.TextAlign.left,
              color: PdfC.loan,
            ),
          ],
        ),
        pw.TableRow(
          children: [
            cell('At start', italic: true, bold: true),
            cell(''),
            cell(''),
            cell(''),
            cell(
              start.isEmpty ? 'None' : loanLines(store, start),
              bold: true,
              align: pw.TextAlign.left,
            ),
          ],
        ),
        ...rows,
      ],
    ),
  ];
}

/// Every company and how many cylinders of each gas they have on [date].
Future<List<int>> buildCompanySummaryPdf(AppStore store, String date) async {
  final kit = await PdfKit.load();
  final doc = kit.doc('Company Cylinders');
  addCompanyBalancePages(doc, store, date);
  return finish(doc);
}

void addCompanyBalancePages(pw.Document doc, AppStore store, String date) {
  final bal = store.balancesOn(date);
  final companies = [
    for (final c in store.companies)
      if (c.active || (bal[c.id]?.isNotEmpty ?? false)) c,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final gases = [
    for (final g in kGases)
      if (companies.any((c) => (bal[c.id]?[g.code] ?? 0) != 0)) g,
  ];
  final sums = <String, int>{};
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        headCell('Sr'),
        headCell('Company Name', align: pw.TextAlign.left),
        for (final g in gases) headCell(g.label),
        headCell('Total'),
      ],
    ),
  ];
  for (var i = 0; i < companies.length; i++) {
    final c = companies[i];
    final b = bal[c.id] ?? const <String, int>{};
    var total = 0;
    rows.add(
      pw.TableRow(
        decoration: stripe(i),
        children: [
          cell('${i + 1}'),
          cell(
            c.name + (c.active ? '' : ' (removed)'),
            bold: true,
            align: pw.TextAlign.left,
          ),
          for (final g in gases)
            () {
              final v = b[g.code] ?? 0;
              total += v;
              sums[g.code] = (sums[g.code] ?? 0) + v;
              return cell(v == 0 ? '' : '$v', color: v < 0 ? PdfC.red : null);
            }(),
          pw.Container(
            color: PdfC.balBg,
            child: cell('$total', bold: true, color: PdfC.navy),
          ),
        ],
      ),
    );
  }
  rows.add(
    pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        cell(''),
        cell('TOTAL', bold: true, align: pw.TextAlign.left),
        for (final g in gases) cell('${sums[g.code] ?? 0}', bold: true),
        cell(
          '${sums.values.fold(0, (a, b) => a + b)}',
          bold: true,
          color: PdfC.navy,
        ),
      ],
    ),
  );
  final d = parseDayKey(date);
  doc.addPage(
    pePage(
      format: gases.length > 7 ? a4Landscape : a4,
      title: 'Company-wise Cylinder Stock',
      detail: 'On ${fmtDmy(d)}  (${fmtWeekday(d)})',
      build: (ctx) => [
        if (companies.isEmpty)
          pw.Text('No companies yet.')
        else
          pw.Table(
            border: thinBorder,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(3),
              for (var i = 0; i < gases.length; i++)
                2 + i: const pw.FixedColumnWidth(46),
              2 + gases.length: const pw.FixedColumnWidth(50),
            },
            children: rows,
          ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Stock at each company = starting stock + cylinders supplied - empty cylinders received.',
            style: pw.TextStyle(fontSize: 7.5, color: PdfC.muted),
          ),
        ),
      ],
    ),
  );
}
