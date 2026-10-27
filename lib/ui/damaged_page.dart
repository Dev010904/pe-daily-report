import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'gas_lines.dart';
import 'keys.dart';
import 'stock_guard.dart';
import 'theme.dart';
import 'widgets.dart';

/// Damaged cylinders for the day. A damaged cylinder keeps its gas: two
/// damaged Oxygen and one damaged CO2 are 3 damaged cylinders, and only 2
/// Oxygen and 1 CO2 can come back.
/// 1. At the start of the day: carried on from the day before (typed by
///    hand the first time, or to correct it).
/// 2. Declared damaged today: from the godown empties or from full stock.
/// 3. Repaired today: a damaged cylinder comes back as an empty of its own
///    gas in the godown.
class DamagedPage extends StatefulWidget {
  final AppStore store;
  final String date;
  const DamagedPage({super.key, required this.store, required this.date});

  @override
  State<DamagedPage> createState() => _DamagedPageState();
}

class _DamagedPageState extends State<DamagedPage> {
  AppStore get store => widget.store;

  /// Damaged at the start of the day (one column).
  late final GasLines _start;

  /// Columns: from empty (godown), from full.
  late final GasLines _damaged;
  late final GasLines _repaired;
  final _startKey = GlobalKey<GasLinesEditorState>();
  final _damagedKey = GlobalKey<GasLinesEditorState>();
  final _repairedKey = GlobalKey<GasLinesEditorState>();

  /// What the start would be without a hand correction (the day before).
  final Map<String, int> _auto = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final day = store.day(widget.date);
    final stock = store.stock(widget.date);
    for (final r in stock.rows) {
      if (r.autoDamagedOpen != 0) _auto[r.gas.code] = r.autoDamagedOpen;
    }
    _start = GasLines(1, {
      for (final r in stock.rows)
        if (r.damagedOpen != 0) r.gas.code: [r.damagedOpen],
    });
    _damaged = GasLines(2, {
      for (final g in kGases)
        if ((day.damagedEmpty[g.code] ?? 0) != 0 ||
            (day.damagedFull[g.code] ?? 0) != 0)
          g.code: [day.damagedEmpty[g.code] ?? 0, day.damagedFull[g.code] ?? 0],
    });
    _repaired = GasLines(1, {
      for (final e in day.repaired.entries) e.key: [e.value],
    });
    // Cursor on the empty line for a new gas, never on a saved line.
    // PC only: on the phone nothing is chosen until a box is tapped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isWide(context)) _damagedKey.currentState?.focusLast();
    });
  }

  @override
  void dispose() {
    _start.dispose();
    _damaged.dispose();
    _repaired.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  Map<String, int> get _startBy => _start.column(0);

  /// Declared damaged today (from empty + from full), by gas.
  Map<String, int> get _inBy {
    final m = _damaged.column(0);
    _damaged.column(1).forEach((k, v) => m[k] = (m[k] ?? 0) + v);
    return m;
  }

  Map<String, int> get _outBy => _repaired.column(0);

  /// Damaged at the end of the day, by gas.
  Map<String, int> get _closeBy {
    final m = Map.of(_startBy);
    _inBy.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
    _outBy.forEach((k, v) => m[k] = (m[k] ?? 0) - v);
    m.removeWhere((_, v) => v == 0);
    return m;
  }

  int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

  /// A gas can be repaired only when there are damaged ones of that gas.
  Set<String> get _notRepairable {
    final have = Map.of(_startBy);
    _inBy.forEach((k, v) => have[k] = (have[k] ?? 0) + v);
    return {
      for (final g in kGases)
        if ((have[g.code] ?? 0) <= 0 && !_repaired.usedGases.contains(g.code))
          g.code,
    };
  }

  bool get _startChanged {
    final s = _startBy;
    for (final g in kGases) {
      if ((s[g.code] ?? 0) != (_auto[g.code] ?? 0)) return true;
    }
    return false;
  }

  void _useAutomatic() {
    setState(() {
      _start.load({
        for (final e in _auto.entries) e.key: [e.value],
      });
      _dirty = true;
    });
  }

  /// End of the "at start" list: on to today's damaged cylinders.
  void _afterStart() => _damagedKey.currentState?.focusLast();

  /// End of the second list: go on to "Repaired".
  void _afterDamaged() => _repairedKey.currentState?.focusFirst();

  /// End of the last list: "Save?" (Enter = yes, Esc = no).
  Future<void> _ask() async {
    final ok = await confirm(
      context,
      title: 'Save damaged cylinders?',
      message: 'For ${fmtLong(parseDayKey(widget.date))}\n\n${_summary()}',
      yes: 'Yes, save',
    );
    if (!mounted) return;
    if (ok) {
      await _save();
    } else {
      _repairedKey.currentState?.focusLast();
    }
  }

  String _summary() {
    final start = _startBy, inBy = _inBy, out = _outBy, close = _closeBy;
    final empty = _damaged.column(0), full = _damaged.column(1);
    final lines = <String>[];
    for (final g in kGases) {
      final s = start[g.code] ?? 0, i = inBy[g.code] ?? 0, o = out[g.code] ?? 0;
      if (s == 0 && i == 0 && o == 0) continue;
      final parts = [
        if ((empty[g.code] ?? 0) > 0) '${empty[g.code]} empty',
        if ((full[g.code] ?? 0) > 0) '${full[g.code]} full',
      ];
      lines.add(
        '  ${g.label}:  $s + $i${parts.isEmpty ? '' : ' (${parts.join(' + ')})'}'
        ' − $o repaired = ${close[g.code] ?? 0}',
      );
    }
    return [
      if (lines.isEmpty)
        'No damaged cylinders.'
      else
        'Damaged cylinders:\n${lines.join('\n')}',
      '\nTotal damaged: ${_sum(close)}',
    ].join('\n');
  }

  Future<void> _save() async {
    final day = store.day(widget.date);
    final start = _startBy;
    // Only real corrections, so changes to earlier days still flow through.
    day.openDamagedGas = {
      for (final g in kGases)
        if ((start[g.code] ?? 0) != (_auto[g.code] ?? 0))
          g.code: start[g.code] ?? 0,
    };
    day.damagedEmpty = _damaged.column(0);
    day.damagedFull = _damaged.column(1);
    day.repaired = _repaired.column(0);
    if (!await stockAllowsSave(context, store, day)) return;
    await store.saveDay(day);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await confirm(
          context,
          title: 'Quit without saving?',
          message: 'The changes on this page will be lost.',
          yes: 'Quit',
        );
        if (leave) nav.pop();
      },
      child: KeyPage(
        onSave: _save,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Damaged Cylinders  ·  ${fmtLong(parseDayKey(widget.date))}',
            ),
          ),
          body: PageWidth(
            max: 660,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                OldDateBanner(date: widget.date),
                _countCard(),
                const SizedBox(height: 14),
                _heading(
                  Icons.inventory_2_outlined,
                  'Damaged at the start of this day',
                  'Comes from the day before. First time? Choose each gas and type how '
                      'many damaged cylinders of it you have now.',
                ),
                GasLinesEditor(
                  key: _startKey,
                  lines: _start,
                  titles: const ['Damaged'],
                  colors: const [AppColors.danger],
                  chooseOnly: true,
                  onChanged: _touch,
                  onEndOfList: _afterStart,
                ),
                if (_startChanged) _startNote(),
                const SizedBox(height: 16),
                _heading(
                  Icons.broken_image_outlined,
                  'Declared damaged today',
                  'Choose the gas (↑ ↓ or its first letter, Enter), then how many from '
                      'the godown empties and how many from full stock. It stays that '
                      'gas, counted as damaged.',
                ),
                GasLinesEditor(
                  key: _damagedKey,
                  lines: _damaged,
                  titles: const ['From empty', 'From full'],
                  colors: const [AppColors.empty, AppColors.full],
                  chooseOnly: true,
                  onChanged: _touch,
                  onEndOfList: _afterDamaged,
                ),
                const SizedBox(height: 16),
                _heading(
                  Icons.build_circle_outlined,
                  'Repaired today',
                  'A repaired cylinder comes back as an EMPTY of its own gas in the '
                      'godown (a damaged Oxygen only as Oxygen). Only gases that have '
                      'damaged cylinders are listed.',
                ),
                GasLinesEditor(
                  key: _repairedKey,
                  lines: _repaired,
                  titles: const ['Repaired'],
                  colors: const [AppColors.empty],
                  skipGases: _notRepairable,
                  chooseOnly: true,
                  onChanged: _touch,
                  onEndOfList: _ask,
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: PageWidth(
                    max: 660,
                    child: FilledButton.icon(
                      key: const Key('saveDamaged'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save Damaged Cylinders',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
                if (isWide(context))
                  const KeyHints([
                    ('↓ or letter', 'List of gases'),
                    ('Enter', 'Next box'),
                    ('Enter on empty gas', 'Next list / save'),
                    ('↑ / Backspace', 'Previous box'),
                    ('Ctrl+A', 'Save now'),
                    ('Esc', 'Back'),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _startNote() {
    final auto = orderedQty(_auto);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          const Icon(Icons.edit, size: 14, color: AppColors.amber),
          Text(
            'Changed by hand. From the day before: '
            '${auto.isEmpty ? 'none' : auto.map((e) => '${gasLabel(e.key)} ${e.value}').join(', ')}',
            key: const Key('damagedStartChanged'),
            style: const TextStyle(fontSize: 13.5, color: AppColors.amber),
          ),
          TextButton(
            onPressed: _useAutomatic,
            child: const Text('Use the day before'),
          ),
        ],
      ),
    );
  }

  Widget _heading(IconData icon, String title, String note) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.danger, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        Text(
          note,
          style: const TextStyle(fontSize: 14, color: AppColors.muted),
        ),
      ],
    ),
  );

  /// Damaged now, gas by gas, and the total.
  Widget _countCard() {
    final start = _sum(_startBy), inn = _sum(_inBy), out = _sum(_outBy);
    final closeBy = _closeBy;
    final close = _sum(closeBy);
    final neg = closeBy.values.any((v) => v < 0);
    final items = orderedQty(closeBy);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Damaged cylinders',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                '$start  + $inn damaged  − $out repaired  =  $close',
                key: const Key('damagedCount'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: neg ? AppColors.danger : const Color(0xFF8E1B1B),
                ),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in items)
                  QtyChip(
                    label: gasLabel(e.key),
                    qty: e.value,
                    color: AppColors.danger,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
