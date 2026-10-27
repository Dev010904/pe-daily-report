import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../export/company_pdf.dart';
import '../export/day_pdf.dart';
import '../export/plant_pdf.dart';
import '../export/register_pdf.dart';
import '../logic/plant_report.dart';
import '../platform/deliver.dart';
import '../util/dates.dart';
import 'widgets.dart';

const _pdfMime = 'application/pdf';

/// Sends a file out: share sheet on the phone (WhatsApp etc.), download on
/// the PC. Tests replace this to capture the file instead.
Future<String> Function(List<int> bytes, String name, String mime, String text)
deliverFile = deliverFileImpl;

Future<void> _deliver(
  BuildContext context,
  Future<List<int>> Function() build,
  String name,
  String text,
) async {
  try {
    final bytes = await build();
    final how = await deliverFile(bytes, name, _pdfMime, text);
    if (how == 'downloaded' && context.mounted) {
      toast(context, 'Downloaded: $name');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Could not make PDF: $e');
  }
}

/// Daily report for one day (or a few days, one after another).
Future<void> sendDayPdf(
  BuildContext context,
  AppStore store,
  List<String> dates,
) async {
  if (dates.isEmpty) {
    toast(context, 'No saved data in these dates');
    return;
  }
  final first = fmtDmy(parseDayKey(dates.first));
  await _deliver(
    context,
    () => buildDayPdf(store, dates),
    dayPdfFileName(dates),
    dates.length == 1
        ? 'Panchal Enterprise - Daily Report $first'
        : 'Panchal Enterprise - Daily Report $first to ${fmtDmy(parseDayKey(dates.last))}',
  );
}

/// Up to a month: every day's report. Longer (a business year): register
/// with month-wise totals.
Future<void> sendRangePdf(
  BuildContext context,
  AppStore store,
  String from,
  String to,
) async {
  final dates = [
    for (final d in store.savedDates)
      if (d.compareTo(from) >= 0 && d.compareTo(to) <= 0) d,
  ];
  if (dates.isEmpty) {
    toast(context, 'No saved data in these dates');
    return;
  }
  if (daysInclusive(parseDayKey(from), parseDayKey(to)) <= 31) {
    await sendDayPdf(context, store, dates);
    return;
  }
  await _deliver(
    context,
    () => buildRegisterPdf(store, from, to),
    registerPdfFileName(from, to),
    'Panchal Enterprise - Daily Report ${fmtDmy(parseDayKey(from))} to ${fmtDmy(parseDayKey(to))}',
  );
}

/// One company's cylinder statement.
Future<void> sendCompanyStatement(
  BuildContext context,
  AppStore store,
  String companyId, {
  String? from,
  String? to,
}) async {
  final c = store.company(companyId)!;
  await _deliver(
    context,
    () => buildCompanyStatementPdf(store, companyId, from: from, to: to),
    companyStatementFileName(c.name, from: from, to: to),
    'Panchal Enterprise - ${c.name} cylinder statement',
  );
}

/// One filling plant's report: sent / filled back day-, month- or year-wise.
Future<void> sendPlantReport(
  BuildContext context,
  AppStore store,
  String plantId, {
  String? from,
  String? to,
  required PlantGroup group,
  required String period,
}) => _deliver(
  context,
  () => buildPlantReportPdf(
    store,
    plantId,
    from: from,
    to: to,
    group: group,
    period: period,
  ),
  plantReportFileName(store.plantName(plantId), period),
  'Panchal Enterprise - ${store.plantName(plantId)} filling report ($period)',
);

/// Every company's cylinders on a date.
Future<void> sendCompanySummary(
  BuildContext context,
  AppStore store,
  String date,
) => _deliver(
  context,
  () => buildCompanySummaryPdf(store, date),
  companySummaryFileName(date),
  'Panchal Enterprise - Company cylinders on ${fmtDmy(parseDayKey(date))}',
);

/// Icon for the send / download buttons.
IconData get shareIcon => kIsWeb ? Icons.download : Icons.share;
