import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/store.dart';
import '../logic/plant_report.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'filling_page.dart';
import 'keys.dart';
import 'share.dart';
import 'theme.dart';
import 'widgets.dart';

int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

String _gasText(Map<String, int> m, {String none = '-'}) {
  final o = orderedQty(m);
  return o.isEmpty
      ? none
      : o.map((e) => '${gasLabel(e.key)} ${e.value}').join(',   ');
}

Widget _chips(Map<String, int> m, Color color, {String none = 'None'}) {
  final items = orderedQty(m);
  if (items.isEmpty) {
    return Text(
      none,
      style: const TextStyle(fontSize: 15, color: AppColors.muted),
    );
  }
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final e in items)
        QtyChip(label: gasLabel(e.key), qty: e.value, color: color),
    ],
  );
}

/// One plant in the list: filled this month (up to the date) and the
/// empties waiting there on the date.
class _PlantSum {
  final NamedItem plant;
  final PlantDay month;
  final Map<String, int> atPlant;

  /// Loan cylinders from this plant still to give back, by gas.
  final Map<String, int> loanOut;
  const _PlantSum(this.plant, this.month, this.atPlant, this.loanOut);
}

/// Loan cylinders from [plantId] still to give back at the end of [date].
Map<String, int> _loanOut(AppStore store, String plantId, String date) => {
  for (final (gas, l) in store.loanLinesOn(date))
    if (l.plantId == plantId && l.toReturn != 0) gas.code: l.toReturn,
};

List<_PlantSum> _plantSums(AppStore store, String date) {
  final d = parseDayKey(date);
  final from = dayKey(DateTime(d.year, d.month, 1));
  final out = <_PlantSum>[];
  for (final p in store.plants) {
    final month = totalOf(store.plantDays(p.id, from: from, to: date));
    final at = store.emptiesAtPlant(p.id, date);
    final loan = _loanOut(store, p.id, date);
    // A removed plant stays listed while it has history.
    if (!p.active &&
        at.isEmpty &&
        loan.isEmpty &&
        store.plantDays(p.id).isEmpty) {
      continue;
    }
    out.add(_PlantSum(p, month, at, loan));
  }
  out.sort(
    (a, b) => a.plant.name.toLowerCase().compareTo(b.plant.name.toLowerCase()),
  );
  return out;
}

/// Filling plants: how many cylinders each plant filled this month and the
/// empties waiting there. Opens a plant's day / month / year report.
class PlantsList extends StatelessWidget {
  final AppStore store;
  final String date;
  final bool wide;
  final FocusNode? listFocus;
  final ValueChanged<NamedItem> onOpen;

  const PlantsList({
    super.key,
    required this.store,
    required this.date,
    required this.onOpen,
    this.wide = false,
    this.listFocus,
  });

  @override
  Widget build(BuildContext context) {
    final list = _plantSums(store, date);
    final d = parseDayKey(date);
    final monthName = DateFormat('MMMM yyyy').format(d);
    final filled = <String, int>{}, at = <String, int>{};
    for (final s in list) {
      s.month.filled.forEach((k, v) => filled[k] = (filled[k] ?? 0) + v);
      s.atPlant.forEach((k, v) => at[k] = (at[k] ?? 0) + v);
    }
    final summary = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amberLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filled back in $monthName (up to ${fmtShort(d)})',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B4A00),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            plural(_sum(filled), 'cylinder', 'cylinders'),
            key: const Key('plantsFilledTotal'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          _chips(filled, AppColors.full, none: 'Nothing filled yet this month'),
          const SizedBox(height: 10),
          Text(
            'Empty cylinders at the plants on ${fmtShort(d)}:  ${_sum(at)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B4A00),
            ),
          ),
          const SizedBox(height: 6),
          _chips(at, AppColors.empty, none: 'None'),
        ],
      ),
    );
    final empty = const Padding(
      padding: EdgeInsets.all(28),
      child: Text(
        'No filling plants yet.\nAdd one on the Filling / Plant page.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: AppColors.muted),
      ),
    );

    if (!wide) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          summary,
          const SizedBox(height: 12),
          if (list.isEmpty) empty,
          for (final s in list) ...[
            Card(
              child: InkWell(
                key: Key('plant_${s.plant.id}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => onOpen(s.plant),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.plant.name +
                                  (s.plant.active ? '' : ' (removed)'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _chips(
                              s.month.filled,
                              AppColors.full,
                              none: 'Nothing filled this month',
                            ),
                            if (s.loanOut.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Loan to give back: ${_gasText(s.loanOut)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.loan,
                                ),
                              ),
                            ],
                            if (s.atPlant.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Empty at plant: ${_gasText(s.atPlant)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.empty,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          Text(
                            '${s.month.totalFilled}',
                            key: Key('plantFilled_${s.plant.id}'),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppColors.full,
                            ),
                          ),
                          const Text(
                            'filled',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      );
    }

    const h = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    final mon = DateFormat('MMM').format(d);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            summary,
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AppColors.navy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        const Flexible(
                          child: SizedBox(
                            width: 260,
                            child: Text('Filling Plant', style: h),
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: Text(
                            'Filled\nin $mon',
                            textAlign: TextAlign.center,
                            style: h,
                          ),
                        ),
                        const SizedBox(
                          width: 92,
                          child: Text(
                            'Empty\nat plant',
                            textAlign: TextAlign.center,
                            style: h,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(child: Text('Gas-wise', style: h)),
                      ],
                    ),
                  ),
                  if (list.isEmpty) empty,
                  KeyList(
                    focusNode: listFocus,
                    itemCount: list.length,
                    onOpen: (i) => onOpen(list[i].plant),
                    itemBuilder: (context, i, selected) {
                      final s = list[i];
                      return Container(
                        key: Key('plantRow_${s.plant.id}'),
                        decoration: BoxDecoration(
                          color: selected
                              ? kSelectBg
                              : (i.isOdd
                                    ? const Color(0xFFF7F9FC)
                                    : Colors.white),
                          border: Border(
                            left: BorderSide(
                              color: selected
                                  ? kSelectLine
                                  : Colors.transparent,
                              width: 5,
                            ),
                            top: const BorderSide(color: Color(0xFFE6EAF0)),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: SizedBox(
                                width: 260,
                                child: Text(
                                  s.plant.name +
                                      (s.plant.active ? '' : ' (removed)'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 92,
                              child: Text(
                                '${s.month.totalFilled}',
                                key: Key('plantFilled_${s.plant.id}'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.full,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 92,
                              child: Text(
                                '${_sum(s.atPlant)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.empty,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Filled: ${_gasText(s.month.filled)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.full,
                                    ),
                                  ),
                                  if (s.atPlant.isNotEmpty)
                                    Text(
                                      'At plant: ${_gasText(s.atPlant)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.empty,
                                      ),
                                    ),
                                  if (s.loanOut.isNotEmpty)
                                    Text(
                                      'Loan to give back: ${_gasText(s.loanOut)}',
                                      key: Key('plantLoan_${s.plant.id}'),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.loan,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _View { day, month, year, dates }

/// One filling plant: empties sent and cylinders filled back, day-wise for
/// a month, month-wise for a business year (April - March), or year-wise.
/// Enter on a year shows its months, on a month its days, on a day opens
/// that day's filling.
class PlantPage extends StatefulWidget {
  final AppStore store;
  final String plantId;
  const PlantPage({super.key, required this.store, required this.plantId});

  @override
  State<PlantPage> createState() => _PlantPageState();
}

class _PlantPageState extends State<PlantPage> {
  AppStore get store => widget.store;
  _View _view = _View.day;
  DateTime _month = DateTime(today().year, today().month);
  int _fy = businessYearOf(dayKey(today()));
  DateTime? _from;
  DateTime? _to;
  final _listKey = GlobalKey<KeyListState>();
  final _listFocus = FocusNode(debugLabel: 'plantRows');
  final _scroll = ScrollController();

  @override
  void dispose() {
    _listFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  (String?, String?) get _range => switch (_view) {
    _View.day => (
      dayKey(_month),
      dayKey(DateTime(_month.year, _month.month + 1, 0)),
    ),
    _View.month => (
      dayKey(DateTime(_fy, 4, 1)),
      dayKey(DateTime(_fy + 1, 3, 31)),
    ),
    _View.year => (null, null),
    _View.dates => (dayKey(_from!), dayKey(_to!)),
  };

  PlantGroup get _group => switch (_view) {
    _View.month => PlantGroup.month,
    _View.year => PlantGroup.year,
    _ => PlantGroup.day,
  };

  static String _fyText(int y) => 'April $y - March ${y + 1}';

  String get _periodText => switch (_view) {
    _View.day => DateFormat('MMMM yyyy').format(_month),
    _View.month => _fyText(_fy),
    _View.year => 'All years',
    _View.dates => '${fmtDmy(_from!)} to ${fmtDmy(_to!)}',
  };

  String _rowLabel(PlantDay r) => switch (_group) {
    PlantGroup.day => fmtLong(parseDayKey(r.key)),
    PlantGroup.month => DateFormat('MMMM yyyy').format(
      DateTime(
        int.parse(r.key.substring(0, 4)),
        int.parse(r.key.substring(5, 7)),
      ),
    ),
    PlantGroup.year => _fyText(int.parse(r.key)),
  };

  /// Changes what is shown and puts the highlight back on the first row.
  void _set(VoidCallback f) {
    setState(f);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listKey.currentState?.select(0);
    });
  }

  bool get _canNext {
    final now = today();
    return switch (_view) {
      _View.day => !DateTime(_month.year, _month.month + 1).isAfter(now),
      _View.month => _fy < businessYearOf(dayKey(now)),
      _ => false,
    };
  }

  void _prev() {
    if (_view == _View.day) {
      _set(() => _month = DateTime(_month.year, _month.month - 1));
    }
    if (_view == _View.month) _set(() => _fy--);
  }

  void _next() {
    if (!_canNext) return;
    if (_view == _View.day) {
      _set(() => _month = DateTime(_month.year, _month.month + 1));
    }
    if (_view == _View.month) _set(() => _fy++);
  }

  /// One level up: days -> months of that year -> years.
  void _up() {
    if (_view == _View.day) {
      _set(() {
        _fy = businessYearOf(dayKey(_month));
        _view = _View.month;
      });
    } else if (_view == _View.month) {
      _set(() => _view = _View.year);
    } else if (_view == _View.dates) {
      _set(() => _view = _View.day);
    }
  }

  Future<void> _open(PlantDay r) async {
    switch (_group) {
      case PlantGroup.day:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FillingPage(store: store, date: r.key),
          ),
        );
      case PlantGroup.month:
        _set(() {
          _month = DateTime(
            int.parse(r.key.substring(0, 4)),
            int.parse(r.key.substring(5, 7)),
          );
          _view = _View.day;
        });
      case PlantGroup.year:
        _set(() {
          _fy = int.parse(r.key);
          _view = _View.month;
        });
    }
  }

  Future<void> _pickDates() async {
    // PC: type the dates (keyboard); phone: pick them on a calendar.
    final typed = isWide(context);
    final from = typed
        ? await askTypedDate(
            context,
            current: _from ?? today(),
            title: 'From date',
          )
        : await pickDay(
            context,
            selected: _from ?? today(),
            title: 'From date',
            hasData: (d) => store.hasData(dayKey(d)),
          );
    if (from == null || !mounted) return;
    final to = typed
        ? await askTypedDate(context, current: today(), title: 'To date')
        : await pickDay(
            context,
            selected: today(),
            first: from,
            title: 'To date',
            hasData: (d) => store.hasData(dayKey(d)),
          );
    if (to == null || !mounted) return;
    if (to.isBefore(from)) {
      toast(context, 'The "to" date is before the "from" date.');
      return;
    }
    _set(() {
      _from = from;
      _to = to;
      _view = _View.dates;
    });
  }

  void _pdf() {
    final (from, to) = _range;
    sendPlantReport(
      context,
      store,
      widget.plantId,
      from: from,
      to: to,
      group: _group,
      period: _periodText,
    );
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (!isPress(e) || typingInTextField()) return KeyEventResult.ignored;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
      _prev();
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown) {
      _next();
    } else if (k == LogicalKeyboardKey.backspace && e is KeyDownEvent) {
      _up();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.plants.where((x) => x.id == widget.plantId).firstOrNull;
        if (p == null) {
          return const Scaffold(body: Center(child: Text('Plant not found')));
        }
        final wide = isWide(context);
        final (from, to) = _range;
        final days = store.plantDays(p.id, from: from, to: to);
        final rows = groupPlantDays(days, _group);
        final total = totalOf(days);
        final now = store.emptiesAtPlant(p.id, dayKey(today()));
        return KeyPage(
          letters: {
            'd': () => _set(() => _view = _View.day),
            'm': () => _set(() => _view = _View.month),
            'y': () => _set(() => _view = _View.year),
            'c': _pickDates,
            'p': _pdf,
          },
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: Scaffold(
              appBar: AppBar(
                title: Text(p.name, overflow: TextOverflow.ellipsis),
                actions: [
                  TextButton.icon(
                    key: const Key('plantPdf'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: _pdf,
                    icon: Icon(shareIcon),
                    label: const Text(
                      'PDF',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: wide
                  ? const KeyHints([
                      ('↑ ↓', 'Move'),
                      ('Enter', 'Open'),
                      ('Backspace', 'Up a level'),
                      ('D', 'Day-wise'),
                      ('M', 'Month-wise'),
                      ('Y', 'Year-wise'),
                      ('C', 'Choose dates'),
                      ('← →', 'Before / after'),
                      ('P', 'PDF'),
                      ('Esc', 'Back'),
                    ])
                  : null,
              body: PageWidth(
                max: 900,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  children: [
                    _nowCard(now),
                    if (_loanCard(p.id) case final card?) ...[
                      const SizedBox(height: 12),
                      card,
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('Day-wise (D)', _View.day),
                        _chip('Month-wise (M)', _View.month),
                        _chip('Year-wise (Y)', _View.year),
                        ChoiceChip(
                          key: const Key('plantDates'),
                          label: Text(
                            _view == _View.dates
                                ? '${fmtShort(_from!)} - ${fmtShort(_to!)}  (C)'
                                : 'Choose dates (C)',
                          ),
                          selected: _view == _View.dates,
                          onSelected: (_) => _pickDates(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _periodBar(),
                    const SizedBox(height: 10),
                    _totalCard(total),
                    const SizedBox(height: 12),
                    if (wide) _head(),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nothing sent or filled at this plant in this period.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    KeyList(
                      key: _listKey,
                      focusNode: _listFocus,
                      autofocus: true,
                      itemCount: rows.length,
                      onOpen: (i) => _open(rows[i]),
                      itemBuilder: (context, i, selected) => wide
                          ? _wideRow(rows[i], i, selected)
                          : _card(rows[i]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, _View v) => ChoiceChip(
    key: Key('plantView_${v.name}'),
    label: Text(label),
    selected: _view == v,
    onSelected: (_) => _set(() => _view = v),
  );

  Widget _periodBar() {
    final nav = _view == _View.day || _view == _View.month;
    return Row(
      children: [
        if (nav)
          IconButton(
            tooltip: 'Before (←)',
            onPressed: _prev,
            icon: const Icon(Icons.chevron_left, size: 28),
          ),
        Expanded(
          child: Text(
            _periodText,
            key: const Key('plantPeriod'),
            textAlign: nav ? TextAlign.center : TextAlign.start,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        if (nav)
          IconButton(
            tooltip: 'After (→)',
            onPressed: _canNext ? _next : null,
            icon: const Icon(Icons.chevron_right, size: 28),
          ),
      ],
    );
  }

  Widget _nowCard(Map<String, int> now) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.amberBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.amberLine),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EMPTY CYLINDERS AT THIS PLANT NOW',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: Color(0xFF6B4A00),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          plural(_sum(now), 'cylinder', 'cylinders'),
          key: const Key('plantNow'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        _chips(now, AppColors.empty),
        const SizedBox(height: 6),
        const Text(
          'Empty sent are added, filled back are taken off. DA is swapped at '
          'the plant, so no DA empties wait there.',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ],
    ),
  );

  /// Loan cylinders from this plant now: still to give back, gas by gas,
  /// and where they are. Null when there are none.
  Widget? _loanCard(String plantId) {
    final now = dayKey(today());
    final lines = [
      for (final (gas, l) in store.loanLinesOn(now))
        if (l.plantId == plantId && l.toReturn != 0) (gas, l),
    ];
    if (lines.isEmpty) return null;
    final total = lines.fold(0, (a, x) => a + x.$2.toReturn);
    return Container(
      key: const Key('plantLoanCard'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.loanBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.loan.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LOAN CYLINDERS FROM THIS PLANT, STILL TO GIVE BACK',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.loan,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            plural(total, 'cylinder', 'cylinders'),
            key: const Key('plantLoanTotal'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.loan,
            ),
          ),
          for (final (gas, l) in lines) ...[
            const SizedBox(height: 6),
            Text(
              '${gas.label}:  ${l.toReturn}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            Text(
              [
                if (l.closeFull != 0) '${l.closeFull} full in godown',
                if (l.closeEmpty != 0) '${l.closeEmpty} empty in godown',
                for (final e
                    in store.loanCompaniesFor(gas.code, plantId, now).entries)
                  '${e.value} with ${e.key}',
              ].join(',  '),
              style: const TextStyle(fontSize: 14, color: Color(0xFF6A3A78)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totalCard(PlantDay t) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line(
            'Filled back',
            t.totalFilled,
            AppColors.full,
            const Key('plantTotalFilled'),
          ),
          const SizedBox(height: 6),
          _chips(t.filled, AppColors.full),
          const Divider(height: 18),
          _line(
            'Empty sent',
            t.totalSent,
            AppColors.empty,
            const Key('plantTotalSent'),
          ),
          const SizedBox(height: 6),
          _chips(t.sent, AppColors.empty),
          if (t.hasLoan) ...[
            const Divider(height: 18),
            _line(
              'Loan taken',
              t.totalLoanIn,
              AppColors.loan,
              const Key('plantTotalLoanIn'),
            ),
            const SizedBox(height: 6),
            _chips(t.loanIn, AppColors.loan),
            const SizedBox(height: 8),
            _line(
              'Loan given back',
              t.totalLoanBack,
              AppColors.loan,
              const Key('plantTotalLoanBack'),
            ),
            const SizedBox(height: 6),
            _chips(t.loanBack, AppColors.loan),
          ],
        ],
      ),
    ),
  );

  Widget _line(String label, int n, Color color, Key key) => Row(
    children: [
      Flexible(
        child: Text(
          '$label in this period:  ',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
      Text(
        '$n',
        key: key,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    ],
  );

  static const _h = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );

  String get _firstCol => switch (_group) {
    PlantGroup.day => 'Date',
    PlantGroup.month => 'Month',
    PlantGroup.year => 'Business year',
  };

  Widget _head() => Container(
    decoration: const BoxDecoration(
      color: AppColors.navy,
      borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      children: [
        SizedBox(width: 220, child: Text(_firstCol, style: _h)),
        const SizedBox(
          width: 80,
          child: Text('Filled\nback', textAlign: TextAlign.center, style: _h),
        ),
        const SizedBox(
          width: 80,
          child: Text('Empty\nsent', textAlign: TextAlign.center, style: _h),
        ),
        const SizedBox(width: 14),
        const Expanded(child: Text('Gas-wise', style: _h)),
      ],
    ),
  );

  Widget _wideRow(PlantDay r, int i, bool selected) => Container(
    key: Key('plantRow_${r.key}'),
    decoration: BoxDecoration(
      color: selected
          ? kSelectBg
          : (i.isOdd ? const Color(0xFFF7F9FC) : Colors.white),
      border: Border(
        left: BorderSide(
          color: selected ? kSelectLine : Colors.transparent,
          width: 5,
        ),
        top: const BorderSide(color: Color(0xFFE6EAF0)),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: 220,
          child: Text(
            _rowLabel(r),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          width: 80,
          child: Text(
            '${r.totalFilled}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.full,
            ),
          ),
        ),
        SizedBox(
          width: 80,
          child: Text(
            '${r.totalSent}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.empty,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.filled.isNotEmpty)
                Text(
                  'Filled: ${_gasText(r.filled)}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.full,
                  ),
                ),
              if (r.sent.isNotEmpty)
                Text(
                  'Sent: ${_gasText(r.sent)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.empty,
                  ),
                ),
              if (r.loanIn.isNotEmpty)
                Text(
                  'Loan taken: ${_gasText(r.loanIn)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.loan,
                  ),
                ),
              if (r.loanBack.isNotEmpty)
                Text(
                  'Loan given back: ${_gasText(r.loanBack)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.loan,
                  ),
                ),
              if (r.remarks.isNotEmpty) _remarks(r),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _card(PlantDay r) => Card(
    key: Key('plantRow_${r.key}'),
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _rowLabel(r),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${r.totalFilled} filled',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.full,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 8),
          if (r.filled.isNotEmpty)
            _cardRow('Filled back', AppColors.full, r.filled),
          if (r.filled.isNotEmpty && r.sent.isNotEmpty)
            const SizedBox(height: 6),
          if (r.sent.isNotEmpty)
            _cardRow('Empty sent', AppColors.empty, r.sent),
          if (r.loanIn.isNotEmpty) ...[
            const SizedBox(height: 6),
            _cardRow('Loan taken', AppColors.loan, r.loanIn),
          ],
          if (r.loanBack.isNotEmpty) ...[
            const SizedBox(height: 6),
            _cardRow('Loan back', AppColors.loan, r.loanBack),
          ],
          if (r.remarks.isNotEmpty) ...[const SizedBox(height: 6), _remarks(r)],
        ],
      ),
    ),
  );

  /// Notes on the day's filling lines (ARGON).
  Widget _remarks(PlantDay r) => Text(
    'Remarks: ${r.remarks.entries.map((e) => '${gasLabel(e.key)}: ${e.value}').join(',  ')}',
    key: Key('plantRemarks_${r.key}'),
    style: const TextStyle(
      fontSize: 14,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w800,
      color: AppColors.groupAr,
    ),
  );

  Widget _cardRow(String label, Color color, Map<String, int> m) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 90,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ),
      Expanded(child: _chips(m, color)),
    ],
  );
}
