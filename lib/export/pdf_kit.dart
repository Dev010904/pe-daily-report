import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';

const String kBusinessName = 'PANCHAL ENTERPRISE';
const String kAppName = 'Daily Report';

/// Letterhead lines on every PDF.
const String kBusinessTagline =
    'INDUSTRIAL GAS CYLINDERS & LIQUID OXYGEN  ·  SINCE 2011';
const String kBusinessAddress =
    '9/A, Ranjana Estate, Near Panorama Chowkdi, Duniya,\n'
    'Godhra Road, Halol – 389350, Gujarat';
const String kBusinessContact =
    'Ph: +91 99790 68080,  +91 91737 71564     Email: panchalenterprise9@gmail.com';

/// Colours shared by every PDF.
abstract final class PdfC {
  static final navy = PdfColor.fromHex('#1A4070');
  static final navyDark = PdfColor.fromHex('#0E2747');
  static final blue = PdfColor.fromHex('#2B5FA8');
  static final gold = PdfColor.fromHex('#C9962B');
  static final goldDark = PdfColor.fromHex('#8C6414');
  static final ink = PdfColor.fromHex('#1B2330');
  static final head = PdfColor.fromHex('#E3EBF5');
  static final total = PdfColor.fromHex('#EEF3F9');
  static final sectionBg = PdfColor.fromHex('#EDF2F8');
  static final green = PdfColor.fromHex('#1E7B45');
  static final greenBg = PdfColor.fromHex('#E3F1E7');
  static final red = PdfColor.fromHex('#C62828');
  static final redBg = PdfColor.fromHex('#FDECEC');
  static final amber = PdfColor.fromHex('#8A5A00');
  static final amberBg = PdfColor.fromHex('#FFF1CC');
  static final grey = PdfColor.fromHex('#F4F6F9');
  static final muted = PdfColor.fromHex('#5F6875');
  static final line = PdfColor.fromHex('#B9C3CF');
  static final balBg = PdfColor.fromHex('#E5EEFA');
  static final loan = PdfColor.fromHex('#8E24AA');
  static final loanBg = PdfColor.fromHex('#F7EAFB');
}

/// The PE mark: a gas cylinder with a slanted "PE" on its body.
/// [outline] draws lines only, for the watermark.
String peMarkSvg({bool outline = false}) {
  const navy = '#1A4070';
  String part(String shape, String fill) => outline
      ? '$shape fill="none" stroke="$navy" stroke-width="3.2"/>'
      : '$shape fill="$fill"/>';
  final body = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 240">');
  if (!outline) {
    body.write(
      '<defs>'
      '<linearGradient id="b" x1="0" x2="1" y1="0" y2="0">'
      '<stop offset="0" stop-color="#0E2747"/><stop offset="0.3" stop-color="#4F7FBF"/>'
      '<stop offset="0.55" stop-color="#1F4C85"/><stop offset="1" stop-color="#0E2747"/>'
      '</linearGradient>'
      '<linearGradient id="s" x1="0" x2="1" y1="0" y2="0">'
      '<stop offset="0" stop-color="#9C7116"/><stop offset="0.3" stop-color="#F1D27A"/>'
      '<stop offset="0.55" stop-color="#D4A537"/><stop offset="1" stop-color="#9C7116"/>'
      '</linearGradient></defs>',
    );
  }
  const cyl =
      'M16 72 C16 48 31 34 50 34 C69 34 84 48 84 72 L84 214 '
      'Q84 224 74 224 L26 224 Q16 224 16 214 Z';
  body
    ..write(
      part('<rect x="37" y="5" width="26" height="5" rx="2.5"', '#0E2747'),
    )
    ..write(
      part('<rect x="44" y="10" width="12" height="15" rx="1.5"', '#8A93A0'),
    )
    ..write(
      part('<rect x="56" y="14" width="9" height="6" rx="1.5"', '#8A93A0'),
    )
    ..write(
      part('<rect x="39" y="24" width="22" height="10" rx="2"', '#0E2747'),
    )
    ..write(part('<path d="$cyl"', 'url(#b)'));
  if (outline) {
    body.write(
      '<path d="M16 72 H84" fill="none" stroke="$navy" stroke-width="3.2"/>',
    );
  } else {
    body
      ..write(
        '<path d="M16 72 C16 48 31 34 50 34 C69 34 84 48 84 72 Z" fill="url(#s)"/>',
      )
      ..write(
        '<rect x="16" y="72" width="68" height="3" fill="#9C7116" fill-opacity="0.55"/>',
      );
  }
  body
    ..write(
      part('<rect x="19" y="222" width="62" height="12" rx="3"', '#0E2747'),
    )
    // Slanted "PE" in clean, square-ended strokes.
    ..write(
      '<g fill="none" stroke="${outline ? navy : '#FFFFFF'}" stroke-width="7.4" '
      'stroke-linecap="butt" stroke-linejoin="miter" '
      'transform="translate(25.2 0) skewX(-10)">'
      '<path d="M29.9 163.5 V126.2 H37.7 A9.84 9.84 0 0 1 37.7 145.9 H26.2"/>'
      '<path d="M73.8 126.2 H59.8 V159.8 H73.8 M59.8 143 H71.3"/></g>',
    );
  if (!outline) {
    body.write(
      '<rect x="31" y="170" width="38" height="2.4" rx="1.2" fill="#D4A537"/>',
    );
  }
  body.write('</svg>');
  return body.toString();
}

/// Fonts bundled with the app (Noto Sans: ₹, − and Gujarati letters).
class PdfKit {
  final pw.Font base, bold, italic, guj, gujBold;
  PdfKit._(this.base, this.bold, this.italic, this.guj, this.gujBold);

  static PdfKit? _cache;

  static Future<PdfKit> load() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));
    return _cache = PdfKit._(
      await f('NotoSans-Regular.ttf'),
      await f('NotoSans-Bold.ttf'),
      await f('NotoSans-Italic.ttf'),
      await f('NotoSansGujarati-Regular.ttf'),
      await f('NotoSansGujarati-Bold.ttf'),
    );
  }

  pw.Document doc(String title) => pw.Document(
    title: '$kBusinessName - $title',
    author: kBusinessName,
    creator: '$kAppName app',
    theme: pw.ThemeData.withFont(
      base: base,
      bold: bold,
      italic: italic,
      boldItalic: bold,
      fontFallback: [guj, gujBold],
    ),
  );
}

const pageMargin = pw.EdgeInsets.fromLTRB(26, 22, 26, 20);

final String _watermarkSvg = peMarkSvg(outline: true);
final String _markSvg = peMarkSvg();

/// A report page set: letterhead and footer on every page, and the PE
/// cylinder watermark across the middle.
pw.MultiPage pePage({
  required PdfPageFormat format,
  required String title,
  required String detail,
  required pw.BuildListCallback build,
}) => pw.MultiPage(
  pageTheme: pw.PageTheme(
    pageFormat: format,
    margin: pageMargin,
    buildForeground: (ctx) => pw.Center(
      child: pw.Opacity(
        opacity: 0.06,
        child: pw.SvgImage(svg: _watermarkSvg, height: format.height * 0.52),
      ),
    ),
  ),
  maxPages: 5000,
  header: (ctx) => pdfHeader(title, detail),
  footer: pdfFooter,
  build: build,
);

/// Letterhead: PE mark, business name and contact on the left, the report
/// name and its date / period on the right, then a navy and gold rule.
pw.Widget pdfHeader(String title, String detail) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SvgImage(svg: _markSvg, height: 58),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  kBusinessName,
                  style: pw.TextStyle(
                    color: PdfC.navy,
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.6,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  kBusinessTagline,
                  style: pw.TextStyle(
                    color: PdfC.goldDark,
                    fontSize: 7.2,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  kBusinessAddress,
                  style: pw.TextStyle(color: PdfC.muted, fontSize: 7.2),
                ),
                pw.Text(
                  kBusinessContact,
                  style: pw.TextStyle(color: PdfC.muted, fontSize: 7.2),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.ConstrainedBox(
            constraints: const pw.BoxConstraints(maxWidth: 210),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfC.navy,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Text(
                    fixIndic(title.toUpperCase()),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  fixIndic(detail),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    color: PdfC.ink,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(height: 2, color: PdfC.navy),
      pw.SizedBox(height: 1.2),
      pw.Container(height: 0.8, color: PdfC.gold),
    ],
  ),
);

pw.Widget pdfFooter(pw.Context ctx) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 6),
  padding: const pw.EdgeInsets.only(top: 4),
  decoration: pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: PdfC.line, width: 0.5)),
  ),
  child: pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          'Panchal Enterprise, Halol  ·  $kAppName  ·  Printed ${fmtDmy(today())}',
          style: pw.TextStyle(fontSize: 7, color: PdfC.muted),
        ),
      ),
      pw.Text(
        'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: pw.TextStyle(
          fontSize: 7,
          color: PdfC.muted,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ],
  ),
);

/// Section title: navy bar on the left, light band behind.
pw.Widget section(String title) => pw.Container(
  width: double.infinity,
  margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
  padding: const pw.EdgeInsets.fromLTRB(7, 3.5, 6, 3.5),
  decoration: pw.BoxDecoration(
    color: PdfC.sectionBg,
    border: pw.Border(left: pw.BorderSide(color: PdfC.navy, width: 3)),
  ),
  child: pw.Text(
    title,
    style: pw.TextStyle(
      color: PdfC.navy,
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.7,
    ),
  ),
);

/// A table cell.
pw.Widget cell(
  String text, {
  bool bold = false,
  bool italic = false,
  double size = 8.5,
  PdfColor? color,
  pw.TextAlign align = pw.TextAlign.center,
  pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(
    horizontal: 3.5,
    vertical: 3.5,
  ),
}) => pw.Padding(
  padding: padding,
  child: pw.Text(
    fixIndic(text),
    textAlign: align,
    style: pw.TextStyle(
      fontSize: size,
      color: color ?? PdfC.ink,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
    ),
  ),
);

pw.Widget headCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.center,
  PdfColor? color,
}) =>
    cell(text, bold: true, size: 7.8, align: align, color: color ?? PdfC.navy);

/// Light band behind every other row, for easy reading across.
pw.BoxDecoration? stripe(int i) =>
    i.isOdd ? pw.BoxDecoration(color: PdfC.grey) : null;

/// Bill column of an entry: tick / cross, or "-" when no bill is needed
/// (only empties received).
pw.Widget billCell(Entry e, {double size = 11}) =>
    e.needsBill ? billMark(e.billed, size: size) : cell('-', color: PdfC.muted);

/// Green tick (bill made) or red cross (bill to be made), drawn as shapes.
pw.Widget billMark(bool billed, {double size = 11}) => pw.Center(
  child: pw.Padding(
    padding: const pw.EdgeInsets.all(2),
    child: pw.SizedBox(
      width: size,
      height: size,
      child: pw.SvgImage(
        svg: billed
            ? '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
                  '<circle cx="12" cy="12" r="12" fill="#1E7B45"/>'
                  '<path d="M6.5 12.5l3.5 3.5 7.5-8" fill="none" stroke="#FFFFFF" '
                  'stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>'
            : '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
                  '<circle cx="12" cy="12" r="12" fill="#C62828"/>'
                  '<path d="M8 8l8 8M16 8l-8 8" fill="none" stroke="#FFFFFF" '
                  'stroke-width="3" stroke-linecap="round"/></svg>',
      ),
    ),
  ),
);

/// Loan cylinders "LOAN ARGON : 10 (ABC Plant)", one per line.
String loanLines(AppStore store, PlantQty m, {String sep = '\n'}) => [
  for (final g in kGases)
    for (final p in (m[g.code] ?? const <String, int>{}).entries)
      if (p.value != 0)
        'LOAN ${g.label} : ${p.value} (${store.plantName(p.key)})',
].join(sep);

/// Our cylinders, then the loan ones; "-" when there are none.
String qtyAndLoan(
  AppStore store,
  Map<String, int> ours,
  PlantQty loan, {
  String sep = '\n',
}) {
  final parts = [
    if (orderedQty(ours).isNotEmpty) qtyLines(ours, sep: sep),
    if (loan.isNotEmpty) loanLines(store, loan, sep: sep),
  ];
  return parts.isEmpty ? '-' : parts.join(sep);
}

/// "O2 : 2" lines in the standard gas order.
String qtyLines(Map<String, int> qty, {String sep = '\n'}) =>
    orderedQty(qty).map((e) => '${gasLabel(e.key)} : ${e.value}').join(sep);

/// ₹2,500 style money.
String rs(double v) => fmtMoney(v);

pw.TableBorder get thinBorder => pw.TableBorder(
  left: pw.BorderSide(color: PdfC.line, width: 0.5),
  right: pw.BorderSide(color: PdfC.line, width: 0.5),
  top: pw.BorderSide(color: PdfC.navy, width: 0.9),
  bottom: pw.BorderSide(color: PdfC.navy, width: 0.9),
  horizontalInside: pw.BorderSide(color: PdfC.line, width: 0.4),
  verticalInside: pw.BorderSide(color: PdfC.line, width: 0.4),
);

/// Turns the finished document into bytes.
Future<List<int>> finish(pw.Document doc) async => (await doc.save()).toList();

/// Safe file-name part.
String safeName(String s) => s
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

PdfPageFormat get a4 => PdfPageFormat.a4;
PdfPageFormat get a4Landscape => PdfPageFormat.a4.landscape;

/// PDFs draw letters in typing order, but in Gujarati the "િ" vowel sign is
/// written before its consonant (and before a joined consonant group).
/// Move it there so names read correctly.
String fixIndic(String s) {
  if (!s.runes.any((r) => r == 0x0ABF)) return s;
  final r = s.runes.toList();
  bool consonant(int c) => c >= 0x0A95 && c <= 0x0AB9;
  for (var i = 0; i < r.length; i++) {
    if (r[i] != 0x0ABF || i == 0 || !consonant(r[i - 1])) continue;
    var j = i - 1;
    while (j >= 2 && r[j - 1] == 0x0ACD && consonant(r[j - 2])) {
      j -= 2;
    }
    r.removeAt(i);
    r.insert(j, 0x0ABF);
  }
  return String.fromCharCodes(r);
}
