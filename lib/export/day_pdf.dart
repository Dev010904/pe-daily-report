import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import '../ui/loan_text.dart';
import 'pdf_kit.dart';

String dayPdfFileName(List<String> dates) {
  final first = fmtDmy(parseDayKey(dates.first));
  if (dates.length == 1) return 'PE_Daily_Report_$first.pdf';
  return 'PE_Daily_Report_${first}_to_${fmtDmy(parseDayKey(dates.last))}.pdf';
}

/// Daily report: one section (page or more) per date, the same layout as
/// the paper book — stock table, then supply / empty / cash table.
Future<List<int>> buildDayPdf(AppStore store, List<String> dates) async {
  final kit = await PdfKit.load();
  final doc = kit.doc(kAppName);
  for (final date in dates) {
    final d = parseDayKey(date);
    final day = store.day(date);
    final stock = store.stock(date);
    doc.addPage(
      pePage(
        format: a4,
        title: kAppName,
        detail: '${fmtDmy(d)}  (${fmtWeekday(d)})',
        build: (ctx) => [
          section('DAILY STOCK'),
          _stockTable(store, stock),
          ?_argonRemark(store, stock),
          if (stock.hasDamaged) _damaged(stock),
          _stockNote(stock),
          if (stock.hasLoans) ...[
            section(
              'LOAN CYLINDERS (borrowed from plants, kept apart from ours)',
            ),
            _loanTable(store, stock),
          ],
          section('FULL SUPPLIED & EMPTY RECEIVED'),
          ..._supplyTable(store, day),
        ],
      ),
    );
  }
  return finish(doc);
}

pw.Widget _stockTable(AppStore store, StockDay stock) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        headCell('Gas', align: pw.TextAlign.left),
        headCell('Opening\nFull Stock'),
        headCell('Filling'),
        headCell('Sales'),
        headCell('Closing\nFull Stock'),
        headCell('Empty (Godown)'),
      ],
    ),
  ];
  for (var i = 0; i < stock.rows.length; i++) {
    final r = stock.rows[i];
    rows.add(
      pw.TableRow(
        decoration: stripe(i),
        children: [
          cell(r.gas.label, bold: true, align: pw.TextAlign.left),
          cell('${r.openFull}'),
          cell(
            r.fill <= 0
                ? '${r.fill}'
                : r.fillSteps.length > 1
                ? '${r.fillStepsText}\n= +${r.fill}'
                : '+${r.fill}',
            color: r.fill > 0 ? PdfC.green : PdfC.muted,
            bold: r.fill > 0,
          ),
          cell('${r.sales}', color: r.sales > 0 ? null : PdfC.muted),
          pw.Container(
            color: PdfC.greenBg,
            child: r.damagedFull == 0
                ? cell('${r.closeFull}', bold: true, color: PdfC.green, size: 9)
                : pw.Column(
                    children: [
                      cell(
                        '${r.closeFull}',
                        bold: true,
                        color: PdfC.green,
                        size: 9,
                        padding: const pw.EdgeInsets.only(top: 3),
                      ),
                      cell(
                        '(-${r.damagedFull} damaged)',
                        color: PdfC.red,
                        size: 6.5,
                        padding: const pw.EdgeInsets.only(bottom: 2),
                      ),
                    ],
                  ),
          ),
          cell(r.emptyCalcText(labelPlant: true), bold: true, color: PdfC.navy),
        ],
      ),
    );
    for (final l in r.plantLines) {
      // The note on the day's ARGON filling line at this plant.
      final note = r.gas.code == kArgon
          ? store.day(stock.date).fillingRemarkOf(kArgon, l.plantId)
          : '';
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfC.amberBg),
          children: [
            cell(
              '   at plant',
              italic: true,
              color: PdfC.amber,
              align: pw.TextAlign.left,
            ),
            note.isEmpty
                ? cell(
                    store.plantName(l.plantId),
                    bold: true,
                    color: PdfC.amber,
                    align: pw.TextAlign.left,
                  )
                : pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      cell(
                        store.plantName(l.plantId),
                        bold: true,
                        color: PdfC.amber,
                        align: pw.TextAlign.left,
                      ),
                      cell(
                        note,
                        italic: true,
                        bold: true,
                        color: PdfC.teal,
                        size: 7,
                        align: pw.TextAlign.left,
                      ),
                    ],
                  ),
            cell(''),
            cell(''),
            cell(''),
            cell(
              l.calcText(arrow: 'to'),
              bold: true,
              color: l.close < 0 ? PdfC.red : PdfC.amber,
            ),
          ],
        ),
      );
    }
    for (final l in r.loanLines) {
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfC.loanBg),
          children: [
            cell(
              '   loan',
              italic: true,
              color: PdfC.loan,
              align: pw.TextAlign.left,
            ),
            cell(
              store.plantName(l.plantId),
              bold: true,
              color: PdfC.loan,
              align: pw.TextAlign.left,
            ),
            cell(''),
            cell(''),
            cell(
              l.fullCalcText(ascii: true),
              bold: true,
              color: l.closeFull < 0 ? PdfC.red : PdfC.loan,
            ),
            cell(
              l.emptyCalcText(ascii: true),
              bold: true,
              color: l.closeEmpty < 0 ? PdfC.red : PdfC.loan,
            ),
          ],
        ),
      );
    }
  }
  return pw.Table(
    border: thinBorder,
    columnWidths: const {
      0: pw.FlexColumnWidth(1.3),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(1),
      3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1.2),
      5: pw.FlexColumnWidth(2.8),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: rows,
  );
}

/// The ARGON note (e.g. the ARGON SPL count), with the day it was written
/// when it came on from an earlier day. Null = none.
pw.Widget? _argonRemark(AppStore store, StockDay stock) {
  final rem = store.stockRemarkOn(stock.date, kArgon);
  if (rem == null) return null;
  final from = rem.from == stock.date
      ? ''
      : '   (written ${fmtDmy(parseDayKey(rem.from))})';
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 4),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: pw.BoxDecoration(
      color: PdfC.tealBg,
      border: pw.Border.all(color: PdfC.teal, width: 0.6),
    ),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: 'ARGON REMARK:  ',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfC.teal,
            ),
          ),
          pw.TextSpan(
            text: rem.text,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: from,
            style: pw.TextStyle(fontSize: 7.5, color: PdfC.muted),
          ),
        ],
      ),
    ),
  );
}

/// Loan cylinders, plant by plant and gas by gas: full and empty in our
/// godown, with companies, and still to give back.
pw.Widget _loanTable(AppStore store, StockDay stock) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfC.loanBg),
      children: [
        headCell('Plant', align: pw.TextAlign.left, color: PdfC.loan),
        headCell('Gas', align: pw.TextAlign.left, color: PdfC.loan),
        headCell('Full in godown', color: PdfC.loan),
        headCell('Empty in godown', color: PdfC.loan),
        headCell('With companies', align: pw.TextAlign.left, color: PdfC.loan),
        headCell('To give\nback', color: PdfC.loan),
      ],
    ),
  ];
  for (final (gas, l) in stock.loanLines) {
    final cos = store.loanCompaniesFor(gas.code, l.plantId, stock.date);
    rows.add(
      pw.TableRow(
        children: [
          cell(
            store.plantName(l.plantId),
            bold: true,
            align: pw.TextAlign.left,
          ),
          cell(gas.label, bold: true, align: pw.TextAlign.left),
          cell(
            l.fullCalcText(ascii: true),
            color: l.closeFull < 0 ? PdfC.red : null,
          ),
          cell(
            l.emptyCalcText(ascii: true),
            color: l.closeEmpty < 0 ? PdfC.red : null,
          ),
          cell(
            cos.isEmpty
                ? '-'
                : cos.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            align: pw.TextAlign.left,
          ),
          cell('${l.toReturn}', bold: true, color: PdfC.loan, size: 9.5),
        ],
      ),
    );
  }
  return pw.Table(
    border: thinBorder,
    columnWidths: const {
      0: pw.FlexColumnWidth(1.6),
      1: pw.FlexColumnWidth(1),
      2: pw.FlexColumnWidth(1.4),
      3: pw.FlexColumnWidth(1.4),
      4: pw.FlexColumnWidth(2),
      5: pw.FlexColumnWidth(0.8),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: rows,
  );
}

/// Damaged cylinders, gas by gas (each keeps its gas until repaired):
/// start + declared today - repaired.
pw.Widget _damaged(StockDay stock) {
  final today = [
    for (final r in stock.rows)
      if (r.damagedEmpty > 0 || r.damagedFull > 0)
        '${r.gas.label} ${[if (r.damagedEmpty > 0) '${r.damagedEmpty} empty', if (r.damagedFull > 0) '${r.damagedFull} full'].join(' + ')}',
  ];
  final byGas = [
    for (final r in stock.rows)
      if (r.damagedOpen != 0 || r.damagedIn != 0 || r.repaired != 0)
        '${r.gas.label}: ${r.damagedIn == 0 && r.repaired == 0 ? '${r.damagedClose}' : '${r.damagedOpen}${r.damagedIn != 0 ? ' + ${r.damagedIn}' : ''}${r.repaired != 0 ? ' - ${r.repaired}' : ''} = ${r.damagedClose}'}',
  ];
  final rep = orderedQty(stock.repairedToday);
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 4),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: pw.BoxDecoration(
      color: PdfC.redBg,
      border: pw.Border.all(color: PdfC.red, width: 0.6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(
              'DAMAGED CYLINDERS:  ',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfC.red,
              ),
            ),
            pw.Text(
              stock.damagedCalcText(ascii: true),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        if (byGas.isNotEmpty)
          pw.Text(
            'By gas:  ${byGas.join(',   ')}',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        if (today.isNotEmpty)
          pw.Text(
            'Became damaged today: ${today.join(',  ')}',
            style: const pw.TextStyle(fontSize: 7.5),
          ),
        if (rep.isNotEmpty)
          pw.Text(
            'Repaired today (back as empty of the same gas): '
            '${rep.map((e) => '${gasLabel(e.key)} ${e.value}').join(',  ')}',
            style: const pw.TextStyle(fontSize: 7.5),
          ),
      ],
    ),
  );
}

pw.Widget _stockNote(StockDay stock) {
  final plants = stock.rows.any((r) => r.plantLines.isNotEmpty);
  final damaged = stock.hasDamaged;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 3, bottom: 4),
    child: pw.Text(
      'Closing Full = Opening + Filling - Sales${damaged ? ' - damaged' : ''}.   '
      'Empty (Godown) = yesterday\'s empty'
      '${plants ? ' - sent to plant' : ''} + empty received'
      '${damaged ? ' - damaged + repaired' : ''}.'
      '${plants ? '   At plant = start + sent - filled back.' : ''}',
      style: pw.TextStyle(fontSize: 7, color: PdfC.muted),
    ),
  );
}

List<pw.Widget> _supplyTable(AppStore store, DayData day) {
  final hasCash = day.entries.any((e) => e.cash.isNotEmpty);
  // Thick line between Challan No. and Empty Received.
  pw.Widget empty(pw.Widget child, {PdfColor? bg}) => pw.Container(
    decoration: pw.BoxDecoration(
      color: bg,
      border: const pw.Border(left: pw.BorderSide(width: 2)),
    ),
    child: child,
  );
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        headCell('Bill'),
        headCell('Sr\nNo.'),
        headCell('Company Name', align: pw.TextAlign.left),
        headCell('Full Supplied', align: pw.TextAlign.left),
        headCell('Challan\nNo.'),
        empty(headCell('Empty Received', align: pw.TextAlign.left)),
        if (hasCash)
          pw.Container(
            color: PdfC.amberBg,
            child: headCell('Cash Received', align: pw.TextAlign.left),
          ),
      ],
    ),
  ];
  for (var i = 0; i < day.entries.length; i++) {
    final e = day.entries[i];
    rows.add(
      pw.TableRow(
        decoration: stripe(i),
        children: [
          billCell(e),
          cell('${i + 1}'),
          cell(
            e.remarks.isEmpty
                ? e.company
                : '${e.company}\nRemarks: ${remarksText(e.remarks, store: store)}',
            bold: true,
            align: pw.TextAlign.left,
          ),
          cell(qtyAndLoan(store, e.full, e.loanFull), align: pw.TextAlign.left),
          cell(e.challan.isEmpty ? '-' : e.challan),
          empty(
            cell(
              qtyAndLoan(store, e.empty, e.loanEmpty),
              align: pw.TextAlign.left,
            ),
          ),
          if (hasCash)
            pw.Container(
              color: e.cash.isEmpty ? null : PdfC.amberBg,
              child: cell(
                e.cash
                    .map(
                      (c) =>
                          '${c.type}: ${rs(c.amount)} (${modeLabel(c.mode)})',
                    )
                    .join('\n'),
                align: pw.TextAlign.left,
              ),
            ),
        ],
      ),
    );
  }
  if (day.entries.isEmpty) {
    return [
      pw.Table(border: thinBorder, children: rows),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(
          'No entries for this day',
          style: pw.TextStyle(
            fontStyle: pw.FontStyle.italic,
            color: PdfC.muted,
          ),
        ),
      ),
    ];
  }

  final full = sumFull(day), emp = sumEmpty(day);
  final loanFull = <String, Map<String, int>>{},
      loanEmpty = <String, Map<String, int>>{};
  for (final e in day.entries) {
    e.loanFull.forEach(
      (g, m) => m.forEach((p, v) => addPlantQty(loanFull, g, p, v)),
    );
    e.loanEmpty.forEach(
      (g, m) => m.forEach((p, v) => addPlantQty(loanEmpty, g, p, v)),
    );
  }
  final made = day.entries.where((e) => e.needsBill && e.billed).length;
  final pending = day.entries.where((e) => e.billPending).length;
  var cash = 0.0, gpay = 0.0;
  for (final e in day.entries) {
    for (final c in e.cash) {
      if (c.mode == kModeGpay) {
        gpay += c.amount;
      } else {
        cash += c.amount;
      }
    }
  }
  rows.add(
    pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        cell('$made / $pending', bold: true, size: 7.5),
        cell(''),
        cell('TOTAL', bold: true, align: pw.TextAlign.left),
        cell(
          qtyAndLoan(store, full, loanFull),
          bold: true,
          align: pw.TextAlign.left,
        ),
        cell(''),
        empty(
          cell(
            qtyAndLoan(store, emp, loanEmpty),
            bold: true,
            align: pw.TextAlign.left,
          ),
          bg: PdfC.head,
        ),
        if (hasCash)
          pw.Container(
            color: PdfC.amberBg,
            child: cell(
              'Total: ${rs(cash + gpay)}\nCash: ${rs(cash)}\nGPay: ${rs(gpay)}',
              bold: true,
              align: pw.TextAlign.left,
            ),
          ),
      ],
    ),
  );
  return [
    pw.Table(
      border: thinBorder,
      columnWidths: {
        0: const pw.FixedColumnWidth(26),
        1: const pw.FixedColumnWidth(24),
        2: const pw.FlexColumnWidth(2.4),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FixedColumnWidth(48),
        5: const pw.FlexColumnWidth(1.5),
        if (hasCash) 6: const pw.FlexColumnWidth(2.2),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    ),
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(
        children: [
          billMark(true, size: 8),
          pw.Text(
            ' bill made     ',
            style: pw.TextStyle(fontSize: 7.5, color: PdfC.muted),
          ),
          billMark(false, size: 8),
          pw.Text(
            ' bill to be made later     -  no bill needed (only empty)     (total row: made / pending)',
            style: pw.TextStyle(fontSize: 7.5, color: PdfC.muted),
          ),
        ],
      ),
    ),
  ];
}
