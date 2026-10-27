import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/store.dart';
import '../util/dates.dart';
import 'share.dart';
import 'keys.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Kind { month, year, custom }

/// One place to send (phone) or download (PC) a PDF for a month, a
/// business year (April - March) or any dates.
class ExportPage extends StatefulWidget {
  final AppStore store;
  const ExportPage({super.key, required this.store});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

/// Business year that contains [d]: April 1 to March 31.
int businessYearStart(DateTime d) => d.month >= 4 ? d.year : d.year - 1;

class _ExportPageState extends State<ExportPage> {
  _Kind _kind = _Kind.month;
  late DateTime _month = DateTime(today().year, today().month);
  late int _fy = businessYearStart(today());
  late DateTime _from = DateTime(today().year, today().month, 1);
  late DateTime _to = today();
  bool _busy = false;

  AppStore get store => widget.store;

  (DateTime, DateTime) get _range => switch (_kind) {
    _Kind.month => (_month, DateTime(_month.year, _month.month + 1, 0)),
    _Kind.year => (DateTime(_fy, 4, 1), DateTime(_fy + 1, 3, 31)),
    _Kind.custom => (_from, _to),
  };

  List<String> get _dates {
    final (a, b) = _range;
    final from = dayKey(a), to = dayKey(b);
    return [
      for (final d in store.savedDates)
        if (d.compareTo(from) >= 0 && d.compareTo(to) <= 0) d,
    ];
  }

  Future<void> _send() async {
    final (a, b) = _range;
    setState(() => _busy = true);
    await sendRangePdf(context, store, dayKey(a), dayKey(b));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pick(bool from) async {
    // PC: type the date (keyboard); phone: pick it on a calendar.
    final d = isWide(context)
        ? await askTypedDate(
            context,
            current: from ? _from : _to,
            title: from ? 'From date' : 'To date',
          )
        : await pickDay(
            context,
            selected: from ? _from : _to,
            first: from ? null : _from,
            title: from ? 'From date' : 'To date',
            hasData: (d) => store.hasData(dayKey(d)),
          );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = d;
      }
    });
  }

  void _prev() => setState(() {
    if (_kind == _Kind.month) _month = DateTime(_month.year, _month.month - 1);
    if (_kind == _Kind.year) _fy--;
  });

  void _next() {
    final now = today();
    setState(() {
      if (_kind == _Kind.month &&
          !DateTime(_month.year, _month.month + 1).isAfter(now)) {
        _month = DateTime(_month.year, _month.month + 1);
      }
      if (_kind == _Kind.year && _fy < businessYearStart(now)) _fy++;
    });
  }

  /// Keyboard: M / Y / D choose, ← → change month or year, F / T type the
  /// dates, Enter makes the PDF.
  KeyEventResult _onKey(KeyEvent e) {
    if (!isPress(e) || typingInTextField() || ctrlDown || altDown) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _prev();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _next();
    } else if (e is KeyDownEvent &&
        (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter)) {
      if (_dates.isNotEmpty && !_busy) _send();
    } else if (e is KeyDownEvent && letterOf(e) != null) {
      switch (letterOf(e)) {
        case 'm':
          setState(() => _kind = _Kind.month);
        case 'y':
          setState(() => _kind = _Kind.year);
        case 'd':
          setState(() => _kind = _Kind.custom);
        case 'f':
          setState(() => _kind = _Kind.custom);
          _pick(true);
        case 't':
          setState(() => _kind = _Kind.custom);
          _pick(false);
        default:
          return KeyEventResult.ignored;
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _range;
    final count = _dates.length;
    final span = daysInclusive(a, b);
    final now = today();
    return EscBack(
      autofocus: false,
      child: Focus(
        autofocus: true,
        onKeyEvent: (n, e) => _onKey(e),
        child: Scaffold(
          appBar: AppBar(title: const Text('Send / Download PDF')),
          bottomNavigationBar: isWide(context)
              ? const KeyHints([
                  ('M', 'One month'),
                  ('Y', 'Business year'),
                  ('D', 'Choose dates'),
                  ('← →', 'Month / year before / after'),
                  ('F / T', 'From / To date'),
                  ('Enter', 'Make PDF'),
                  ('Esc', 'Back'),
                ])
              : null,
          body: PageWidth(
            max: 720,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _option(
                  _Kind.month,
                  Icons.calendar_view_month,
                  'One month',
                  "Every day's report, one after another",
                ),
                if (_kind == _Kind.month)
                  _stepper(
                    DateFormat('MMMM yyyy').format(_month),
                    onPrev: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    ),
                    onNext: DateTime(_month.year, _month.month + 1).isAfter(now)
                        ? null
                        : () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month + 1,
                            ),
                          ),
                  ),
                const SizedBox(height: 10),
                _option(
                  _Kind.year,
                  Icons.date_range,
                  'Business year (April - March)',
                  'Month-wise totals and stock, all entries, cash and company balances',
                ),
                if (_kind == _Kind.year)
                  _stepper(
                    '$_fy - ${(_fy + 1) % 100 < 10 ? '0' : ''}${(_fy + 1) % 100}   (1 Apr $_fy - 31 Mar ${_fy + 1})',
                    onPrev: () => setState(() => _fy--),
                    onNext: _fy >= businessYearStart(now)
                        ? null
                        : () => setState(() => _fy++),
                  ),
                const SizedBox(height: 10),
                _option(
                  _Kind.custom,
                  Icons.edit_calendar,
                  'Choose dates',
                  'Any From and To date',
                ),
                if (_kind == _Kind.custom) ...[
                  const SizedBox(height: 8),
                  _dateBox(
                    'FROM',
                    _from,
                    () => _pick(true),
                    const Key('fromDate'),
                  ),
                  const SizedBox(height: 8),
                  _dateBox('TO', _to, () => _pick(false), const Key('toDate')),
                ],
                const SizedBox(height: 16),
                Card(
                  color: count == 0 ? AppColors.amberBg : AppColors.fullBg,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      count == 0
                          ? 'No saved data from ${fmtDmy(a)} to ${fmtDmy(b)}.'
                          : '${fmtDmy(a)} to ${fmtDmy(b)}\n'
                                '${plural(count, 'day', 'days')} with data  -  '
                                '${span <= 31 ? 'daily reports' : 'register with month-wise totals'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('sendPdf'),
                  onPressed: count == 0 || _busy ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.full,
                    minimumSize: const Size.fromHeight(58),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Icon(shareIcon),
                  label: const Text(
                    'Send / Download PDF',
                    style: TextStyle(fontSize: 19),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(_Kind k, IconData icon, String title, String sub) {
    final on = _kind == k;
    return Material(
      color: on ? AppColors.emptyBg : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: on ? AppColors.navy : AppColors.line,
          width: on ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: Key('option_${k.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _kind = k),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: on ? AppColors.navy : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Icon(icon, color: AppColors.navy),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepper(
    String label, {
    required VoidCallback onPrev,
    VoidCallback? onNext,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Previous',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Next',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );

  Widget _dateBox(String label, DateTime d, VoidCallback onTap, Key key) =>
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_month, color: AppColors.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fmtLong(d),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.edit_calendar, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );
}
