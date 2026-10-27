import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import '../logic/plant_report.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'pdf_kit.dart';

String plantReportFileName(String plant, String period) =>
    'PE_Plant_${safeName(plant)}_${safeName(period)}.pdf';

/// One filling plant: empties sent and cylinders filled back, day-wise,
/// month-wise or year-wise, with the totals and the empties left there.
Future<List<int>> buildPlantReportPdf(
  AppStore store,
  String plantId, {
  String? from,
  String? to,
  required PlantGroup group,
  required String period,
}) async {
  final kit = await PdfKit.load();
  final doc = kit.doc('Filling Plant Report');
  final days = store.plantDays(plantId, from: from, to: to);
  // Oldest first, like a register.
  final rows = groupPlantDays(days, group).reversed.toList();
  final total = totalOf(days);
  final gases = [
    for (final g in kGases)
      if (total.sent.containsKey(g.code) || total.filled.containsKey(g.code)) g,
  ];
  // Per-gas columns while they fit; otherwise one text column each.
  final perGas = gases.length <= 5;
  final now = dayKey(today());
  final end = to == null || to.compareTo(now) > 0 ? now : to;
  final left = store.emptiesAtPlant(plantId, end);
  // Loan cylinders from this plant still to give back at the end.
  final loanOut = [
    for (final (gas, l) in store.loanLinesOn(end))
      if (l.plantId == plantId && l.toReturn != 0) (gas, l),
  ];
  final loanRows = rows.where((r) => r.hasLoan).toList();

  String label(PlantDay r) => switch (group) {
    PlantGroup.day => fmtDmy(parseDayKey(r.key)),
    PlantGroup.month => DateFormat('MMM yyyy').format(
      DateTime(
        int.parse(r.key.substring(0, 4)),
        int.parse(r.key.substring(5, 7)),
      ),
    ),
    PlantGroup.year => 'Apr ${r.key} - Mar ${int.parse(r.key) + 1}',
  };
  String n(int? v) => (v ?? 0) == 0 ? '' : '$v';
  String text(Map<String, int> m) =>
      orderedQty(m).isEmpty ? '-' : qtyLines(m, sep: ',  ');
  final first = switch (group) {
    PlantGroup.day => 'Date',
    PlantGroup.month => 'Month',
    PlantGroup.year => 'Business year',
  };

  final table = <pw.TableRow>[];
  if (perGas) {
    table.add(
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          headCell(first),
          for (final g in gases) ...[
            headCell('${g.label}\nEmpty sent'),
            headCell('${g.label}\nFilled back', color: PdfC.green),
          ],
          pw.Container(
            color: PdfC.balBg,
            child: headCell('Total\nEmpty sent', color: PdfC.navy),
          ),
          pw.Container(
            color: PdfC.balBg,
            child: headCell('Total\nFilled back', color: PdfC.green),
          ),
        ],
      ),
    );
    for (final r in rows) {
      table.add(
        pw.TableRow(
          decoration: stripe(table.length),
          children: [
            cell(label(r)),
            for (final g in gases) ...[
              cell(n(r.sent[g.code])),
              cell(n(r.filled[g.code]), bold: true, color: PdfC.green),
            ],
            pw.Container(
              color: PdfC.balBg,
              child: cell('${r.totalSent}', bold: true, color: PdfC.navy),
            ),
            pw.Container(
              color: PdfC.balBg,
              child: cell('${r.totalFilled}', bold: true, color: PdfC.green),
            ),
          ],
        ),
      );
    }
    table.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          cell('TOTAL', bold: true, align: pw.TextAlign.left),
          for (final g in gases) ...[
            cell('${total.sent[g.code] ?? 0}', bold: true),
            cell('${total.filled[g.code] ?? 0}', bold: true, color: PdfC.green),
          ],
          cell('${total.totalSent}', bold: true, color: PdfC.navy, size: 9.5),
          cell(
            '${total.totalFilled}',
            bold: true,
            color: PdfC.green,
            size: 9.5,
          ),
        ],
      ),
    );
  } else {
    table.add(
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          headCell(first),
          headCell('Empty sent', align: pw.TextAlign.left),
          headCell('Filled back', align: pw.TextAlign.left, color: PdfC.green),
          headCell('Total\nsent'),
          headCell('Total\nfilled', color: PdfC.green),
        ],
      ),
    );
    for (final r in rows) {
      table.add(
        pw.TableRow(
          decoration: stripe(table.length),
          children: [
            cell(label(r)),
            cell(text(r.sent), align: pw.TextAlign.left),
            cell(text(r.filled), align: pw.TextAlign.left, color: PdfC.green),
            cell('${r.totalSent}', bold: true),
            cell('${r.totalFilled}', bold: true, color: PdfC.green),
          ],
        ),
      );
    }
    table.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfC.head),
        children: [
          cell('TOTAL', bold: true, align: pw.TextAlign.left),
          cell(text(total.sent), bold: true, align: pw.TextAlign.left),
          cell(
            text(total.filled),
            bold: true,
            align: pw.TextAlign.left,
            color: PdfC.green,
          ),
          cell('${total.totalSent}', bold: true, size: 9.5),
          cell(
            '${total.totalFilled}',
            bold: true,
            color: PdfC.green,
            size: 9.5,
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pePage(
      format: perGas && gases.length > 3 ? a4Landscape : a4,
      title: 'Filling Plant Report',
      detail: '${store.plantName(plantId)}\n$period',
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
                'Empty cylinders at the plant on ${fmtDmy(parseDayKey(end))}:  ',
                style: pw.TextStyle(fontSize: 9.5, color: PdfC.navy),
              ),
              pw.Expanded(
                child: pw.Text(
                  orderedQty(left).isEmpty
                      ? 'None'
                      : qtyLines(left, sep: ',  '),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfC.navy,
                  ),
                ),
              ),
              pw.Text(
                '${left.values.fold(0, (a, b) => a + b)} cylinders',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfC.navy,
                ),
              ),
            ],
          ),
        ),
        if (rows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(
              'Nothing sent or filled at this plant in this period.',
              style: pw.TextStyle(
                fontStyle: pw.FontStyle.italic,
                color: PdfC.muted,
              ),
            ),
          )
        else
          pw.Table(
            border: thinBorder,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: {0: const pw.FixedColumnWidth(70)},
            children: table,
          ),
        if (loanRows.isNotEmpty || loanOut.isNotEmpty) ...[
          section('LOAN CYLINDERS FROM THIS PLANT'),
          if (loanRows.isNotEmpty)
            pw.Table(
              border: thinBorder,
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: {0: const pw.FixedColumnWidth(70)},
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: pw.BoxDecoration(color: PdfC.loanBg),
                  children: [
                    headCell(first, color: PdfC.loan),
                    headCell(
                      'Loan taken (full)',
                      align: pw.TextAlign.left,
                      color: PdfC.loan,
                    ),
                    headCell(
                      'Given back (empty + full)',
                      align: pw.TextAlign.left,
                      color: PdfC.loan,
                    ),
                  ],
                ),
                for (final r in loanRows)
                  pw.TableRow(
                    children: [
                      cell(label(r)),
                      cell(
                        text(r.loanIn),
                        align: pw.TextAlign.left,
                        color: PdfC.loan,
                        bold: true,
                      ),
                      cell(text(r.loanBack), align: pw.TextAlign.left),
                    ],
                  ),
              ],
            ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 4),
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(color: PdfC.loanBg),
            child: pw.Text(
              loanOut.isEmpty
                  ? 'No loan cylinders from this plant to give back on ${fmtDmy(parseDayKey(end))}.'
                  : 'Still to give back on ${fmtDmy(parseDayKey(end))}:  ${loanOut.map((x) {
                      final cos = store.loanCompaniesFor(x.$1.code, plantId, end);
                      final where = [if (x.$2.closeFull != 0) '${x.$2.closeFull} full in godown', if (x.$2.closeEmpty != 0) '${x.$2.closeEmpty} empty in godown', for (final e in cos.entries) '${e.value} with ${e.key}'].join(', ');
                      return '${x.$1.label} ${x.$2.toReturn} ($where)';
                    }).join(';  ')}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfC.loan,
              ),
            ),
          ),
        ],
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Empty sent = taken out of the godown to the plant. Filled back = filled cylinders '
            'received from the plant. DA is swapped at the plant (DA empty given / DA filled '
            'received), so no DA empties wait there.',
            style: pw.TextStyle(fontSize: 7.5, color: PdfC.muted),
          ),
        ),
      ],
    ),
  );
  return finish(doc);
}
