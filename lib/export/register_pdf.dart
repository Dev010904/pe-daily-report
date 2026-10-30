import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'company_pdf.dart';
import '../ui/loan_text.dart';
import '../ui/po_field.dart';
import 'pdf_kit.dart';

String registerPdfFileName(String from, String to) =>
    'PE_Daily_Report_${fmtDmy(parseDayKey(from))}_to_${fmtDmy(parseDayKey(to))}.pdf';

/// For long periods (a business year): month-wise totals and stock, every
/// supply / empty entry as one register, and company balances at the end.
Future<List<int>> buildRegisterPdf(
  AppStore store,
  String from,
  String to,
) async {
  final kit = await PdfKit.load();
  final doc = kit.doc('$kAppName register');
  final dates = [
    for (final d in store.savedDates)
      if (d.compareTo(from) >= 0 && d.compareTo(to) <= 0) d,
  ];
  final period = '${fmtDmy(parseDayKey(from))} to ${fmtDmy(parseDayKey(to))}';

  // ------------------------------------------------ month-wise numbers
  final months = <String>[];
  final full = <String, Map<String, int>>{};
  final empty = <String, Map<String, int>>{};
  final fill = <String, Map<String, int>>{};
  final sent = <String, Map<String, int>>{};
  final extra = <String, Map<String, int>>{};
  final cash = <String, (double, double)>{};
  var entries = 0, pending = 0;
  void add(Map<String, Map<String, int>> m, String month, Map<String, int> q) {
    final t = m[month] ??= {};
    q.forEach((k, v) => t[k] = (t[k] ?? 0) + v);
  }

  for (final d in dates) {
    final month = d.substring(0, 7);
    if (months.isEmpty || months.last != month) months.add(month);
    final day = store.day(d);
    add(fill, month, day.totalFilling);
    add(extra, month, day.extraFull);
    day.plantSent.forEach(
      (gas, byPlant) =>
          add(sent, month, {gas: byPlant.values.fold(0, (a, b) => a + b)}),
    );
    for (final e in day.entries) {
      entries++;
      if (e.billPending) pending++;
      add(full, month, e.full);
      add(empty, month, e.empty);
      for (final c in e.cash) {
        final (a, b) = cash[month] ?? (0.0, 0.0);
        cash[month] = c.mode == kModeGpay
            ? (a, b + c.amount)
            : (a + c.amount, b);
      }
    }
  }
  final gases = [
    for (final g in kGases)
      if ([
        full,
        empty,
        fill,
        sent,
        extra,
      ].any((m) => m.values.any((q) => (q[g.code] ?? 0) != 0)))
        g,
  ];
  String monthName(String m) => DateFormat('MMM yyyy').format(
    DateTime(int.parse(m.substring(0, 4)), int.parse(m.substring(5, 7))),
  );

  pw.Widget monthTable(Map<String, Map<String, int>> data) {
    final sums = <String, int>{};
    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          headCell('Month', align: pw.TextAlign.left),
          for (final g in gases) headCell(g.label),
          headCell('Total'),
        ],
      ),
    ];
    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      var t = 0;
      rows.add(
        pw.TableRow(
          decoration: stripe(i),
          children: [
            cell(monthName(m), align: pw.TextAlign.left),
            for (final g in gases)
              () {
                final v = data[m]?[g.code] ?? 0;
                t += v;
                sums[g.code] = (sums[g.code] ?? 0) + v;
                return cell(v == 0 ? '' : '$v');
              }(),
            cell('$t', bold: true),
          ],
        ),
      );
    }
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          cell('TOTAL', bold: true, align: pw.TextAlign.left),
          for (final g in gases) cell('${sums[g.code] ?? 0}', bold: true),
          cell('${sums.values.fold(0, (a, b) => a + b)}', bold: true),
        ],
      ),
    );
    return pw.Table(
      border: thinBorder,
      columnWidths: {0: const pw.FixedColumnWidth(62)},
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  doc.addPage(
    pePage(
      format: a4Landscape,
      title: 'Register',
      detail: period,
      build: (ctx) => [
        pw.Text(
          '${plural(dates.length, 'day', 'days')} with data  ·  '
          '${plural(entries, 'entry', 'entries')}  ·  $pending bills pending',
          style: pw.TextStyle(color: PdfC.muted, fontSize: 9),
        ),
        if (dates.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Text('No data in this period.'),
          )
        else ...[
          section('FULL SUPPLIED (SALES) - MONTH-WISE'),
          monthTable(full),
          section('EMPTY RECEIVED - MONTH-WISE'),
          monthTable(empty),
          section('FILLING (FILLED CYLINDERS RECEIVED) - MONTH-WISE'),
          monthTable(fill),
          if (sent.isNotEmpty) ...[
            section('EMPTY SENT TO FILLING PLANT - MONTH-WISE'),
            monthTable(sent),
          ],
          if (extra.values.any((q) => q.isNotEmpty)) ...[
            section('EXTRA FULL (EMPTY RECEIVED, FOUND FULL) - MONTH-WISE'),
            monthTable(extra),
          ],
          section('CASH RECEIVED - MONTH-WISE'),
          _cashTable(months, cash, monthName),
          section(
            'MONTH-WISE STOCK (opening on the 1st, closing on the last day)',
          ),
          _monthStock(store, months, from, to, monthName),
          ?_monthDamaged(store, months, from, to, monthName),
          section('ALL SUPPLY & EMPTY ENTRIES'),
          _register(store, dates),
        ],
      ],
    ),
  );

  addCompanyBalancePages(doc, store, to);
  return finish(doc);
}

pw.Widget _cashTable(
  List<String> months,
  Map<String, (double, double)> cash,
  String Function(String) monthName,
) {
  var tc = 0.0, tg = 0.0;
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        headCell('Month', align: pw.TextAlign.left),
        headCell('Cash'),
        headCell('GPay'),
        headCell('Total'),
      ],
    ),
    for (final m in months)
      () {
        final (c, g) = cash[m] ?? (0.0, 0.0);
        tc += c;
        tg += g;
        return pw.TableRow(
          children: [
            cell(monthName(m), align: pw.TextAlign.left),
            cell(rs(c)),
            cell(rs(g)),
            cell(rs(c + g), bold: true),
          ],
        );
      }(),
  ];
  rows.add(
    pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        cell('TOTAL', bold: true, align: pw.TextAlign.left),
        cell(rs(tc), bold: true),
        cell(rs(tg), bold: true),
        cell(rs(tc + tg), bold: true),
      ],
    ),
  );
  return pw.SizedBox(
    width: 360,
    child: pw.Table(border: thinBorder, children: rows),
  );
}

pw.Widget _monthStock(
  AppStore store,
  List<String> months,
  String from,
  String to,
  String Function(String) monthName,
) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        headCell('Month', align: pw.TextAlign.left),
        headCell('Gas', align: pw.TextAlign.left),
        headCell('Opening Full'),
        headCell('Filling'),
        headCell('Sales'),
        headCell('Closing Full'),
        headCell('Empty (Godown)\nat month end'),
        headCell('Empty at Plant\nat month end'),
      ],
    ),
  ];
  for (final m in months) {
    final y = int.parse(m.substring(0, 4)), mo = int.parse(m.substring(5, 7));
    var first = dayKey(DateTime(y, mo, 1));
    var last = dayKey(DateTime(y, mo + 1, 0));
    if (first.compareTo(from) < 0) first = from;
    if (last.compareTo(to) > 0) last = to;
    final start = store.stock(first), end = store.stock(last);
    final fill = <String, int>{}, sales = <String, int>{};
    for (final d in store.savedDates) {
      if (d.compareTo(first) < 0 || d.compareTo(last) > 0) continue;
      final day = store.day(d);
      day.totalFilling.forEach((k, v) => fill[k] = (fill[k] ?? 0) + v);
      sumFull(day).forEach((k, v) => sales[k] = (sales[k] ?? 0) + v);
    }
    var firstRow = true;
    for (final g in kGases) {
      final o = start.row(g.code).openFull, c = end.row(g.code).closeFull;
      final f = fill[g.code] ?? 0,
          s = sales[g.code] ?? 0,
          e = end.row(g.code).closeGodown;
      final at = end.row(g.code).plantClose;
      if (o == 0 && c == 0 && f == 0 && s == 0 && e == 0 && at == 0) continue;
      rows.add(
        pw.TableRow(
          decoration: firstRow
              ? pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfC.navy, width: 1),
                  ),
                )
              : null,
          children: [
            cell(
              firstRow ? monthName(m) : '',
              bold: true,
              align: pw.TextAlign.left,
            ),
            cell(g.label, bold: true, align: pw.TextAlign.left),
            cell('$o'),
            cell(f == 0 ? '0' : '+$f', color: f > 0 ? PdfC.green : PdfC.muted),
            cell('$s'),
            pw.Container(
              color: PdfC.greenBg,
              child: cell('$c', bold: true, color: PdfC.green),
            ),
            cell('$e', bold: true, color: PdfC.navy),
            cell(at == 0 ? '' : '$at', bold: true, color: PdfC.amber),
          ],
        ),
      );
      firstRow = false;
    }
  }
  return pw.Table(
    border: thinBorder,
    columnWidths: const {
      0: pw.FixedColumnWidth(62),
      1: pw.FixedColumnWidth(62),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: rows,
  );
}

/// Damaged cylinders month by month; null when there were none.
pw.Widget? _monthDamaged(
  AppStore store,
  List<String> months,
  String from,
  String to,
  String Function(String) monthName,
) {
  final rows = <pw.TableRow>[];
  for (final m in months) {
    final y = int.parse(m.substring(0, 4)), mo = int.parse(m.substring(5, 7));
    var first = dayKey(DateTime(y, mo, 1));
    var last = dayKey(DateTime(y, mo + 1, 0));
    if (first.compareTo(from) < 0) first = from;
    if (last.compareTo(to) > 0) last = to;
    final startDay = store.stock(first), endDay = store.stock(last);
    final start = startDay.damagedOpen, end = endDay.damagedClose;
    final endBy = endDay.damagedCloseBy;
    final became = <String, int>{}, repaired = <String, int>{};
    for (final d in store.savedDates) {
      if (d.compareTo(first) < 0 || d.compareTo(last) > 0) continue;
      final day = store.day(d);
      day.damagedToday.forEach((k, v) => became[k] = (became[k] ?? 0) + v);
      day.repaired.forEach((k, v) => repaired[k] = (repaired[k] ?? 0) + v);
    }
    if (start == 0 && end == 0 && became.isEmpty && repaired.isEmpty) continue;
    rows.add(
      pw.TableRow(
        decoration: stripe(rows.length),
        children: [
          cell(monthName(m), bold: true, align: pw.TextAlign.left),
          cell('$start'),
          cell(
            became.isEmpty ? '-' : qtyLines(became, sep: ',  '),
            align: pw.TextAlign.left,
            color: PdfC.red,
          ),
          cell(
            repaired.isEmpty ? '-' : qtyLines(repaired, sep: ',  '),
            align: pw.TextAlign.left,
          ),
          cell(
            endBy.isEmpty ? '$end' : '$end\n${qtyLines(endBy, sep: ', ')}',
            bold: true,
            color: PdfC.red,
          ),
        ],
      ),
    );
  }
  if (rows.isEmpty) return null;
  // One block (a few lines only), so the heading never stays alone at the
  // bottom of a page.
  // (A row cannot be split over pages.)
  return pw.Row(
    children: [
      pw.Expanded(
        child: pw.Column(
          children: [
            section('DAMAGED CYLINDERS (each keeps its gas) - MONTH-WISE'),
            pw.Table(
              border: thinBorder,
              columnWidths: const {
                0: pw.FixedColumnWidth(62),
                1: pw.FixedColumnWidth(70),
                2: pw.FlexColumnWidth(3),
                3: pw.FlexColumnWidth(3),
                4: pw.FixedColumnWidth(110),
              },
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: pw.BoxDecoration(color: PdfC.head),
                  children: [
                    headCell('Month', align: pw.TextAlign.left),
                    headCell('Damaged at start'),
                    headCell('Became damaged', align: pw.TextAlign.left),
                    headCell(
                      'Repaired (back as empty)',
                      align: pw.TextAlign.left,
                    ),
                    headCell('Damaged at end'),
                  ],
                ),
                ...rows,
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _register(AppStore store, List<String> dates) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: PdfC.head),
      children: [
        headCell('Date'),
        headCell('Bill'),
        headCell('Company Name', align: pw.TextAlign.left),
        headCell('Challan'),
        headCell('Full Supplied', align: pw.TextAlign.left),
        headCell('Empty Received', align: pw.TextAlign.left),
        headCell('Cash Received', align: pw.TextAlign.left),
      ],
    ),
  ];
  for (final d in dates) {
    for (final e in store.day(d).entries) {
      rows.add(
        pw.TableRow(
          decoration: stripe(rows.length),
          children: [
            cell(fmtDmy(parseDayKey(d))),
            billCell(e, size: 9),
            cell(
              e.remarks.isEmpty
                  ? e.company
                  : '${e.company}\nRemarks: ${remarksText(e.remarks, store: store)}',
              bold: true,
              align: pw.TextAlign.left,
            ),
            cell(challanWithPo(store, e)),
            cell(
              qtyAndLoan(store, e.full, e.loanFull, sep: ',  '),
              align: pw.TextAlign.left,
            ),
            cell(
              qtyAndLoan(store, e.empty, e.loanEmpty, sep: ',  '),
              align: pw.TextAlign.left,
            ),
            cell(
              e.cash
                  .map(
                    (c) => '${c.type} ${rs(c.amount)} (${modeLabel(c.mode)})',
                  )
                  .join(', '),
              align: pw.TextAlign.left,
              color: PdfC.amber,
            ),
          ],
        ),
      );
    }
  }
  return pw.Table(
    border: thinBorder,
    columnWidths: const {
      0: pw.FixedColumnWidth(54),
      1: pw.FixedColumnWidth(24),
      2: pw.FlexColumnWidth(2.2),
      3: pw.FixedColumnWidth(44),
      4: pw.FlexColumnWidth(2.2),
      5: pw.FlexColumnWidth(2.2),
      6: pw.FlexColumnWidth(2),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: rows,
  );
}
