import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'gas_lines.dart';
import 'keys.dart';
import 'stock_guard.dart';
import 'theme.dart';
import 'widgets.dart';

/// Extra full cylinders for the day: cylinders that came back from
/// companies as "empty" but were found full enough to count as full. Not
/// by company or entry: just the gas and how many. They are taken off the
/// godown empties and added to full stock.
class ExtraFullPage extends StatefulWidget {
  final AppStore store;
  final String date;
  const ExtraFullPage({super.key, required this.store, required this.date});

  @override
  State<ExtraFullPage> createState() => _ExtraFullPageState();
}

class _ExtraFullPageState extends State<ExtraFullPage> {
  AppStore get store => widget.store;
  late final GasLines _lines;
  final _linesKey = GlobalKey<GasLinesEditorState>();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final day = store.day(widget.date);
    _lines = GasLines(1, {
      for (final e in day.extraFull.entries) e.key: [e.value],
    });
    // Cursor on the empty line for a new gas, never on a saved line.
    // PC only: on the phone nothing is chosen until a box is tapped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isWide(context)) _linesKey.currentState?.focusLast();
    });
  }

  @override
  void dispose() {
    _lines.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  /// End of the list: "Save?" (Enter = yes, Esc = no).
  Future<void> _ask() async {
    final m = orderedQty(_lines.column(0));
    final ok = await confirm(
      context,
      title: 'Save extra full cylinders?',
      message:
          'For ${fmtLong(parseDayKey(widget.date))}\n\n'
          '${m.isEmpty ? 'None.' : m.map((e) => '  ${gasLabel(e.key)}: ${e.value}  (empty −${e.value}, full +${e.value})').join('\n')}',
      yes: 'Yes, save',
    );
    if (!mounted) return;
    if (ok) {
      await _save();
    } else {
      _linesKey.currentState?.focusLast();
    }
  }

  Future<void> _save() async {
    final day = store.day(widget.date);
    day.extraFull = _lines.column(0);
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
              'Extra Full Cylinders  ·  ${fmtLong(parseDayKey(widget.date))}',
            ),
          ),
          body: PageWidth(
            max: 660,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                OldDateBanner(date: widget.date),
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.fullBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.full.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.published_with_changes, color: AppColors.full),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Empty cylinders received from companies that were '
                          'found FULL when checked. Choose the gas and how '
                          'many: they are taken off the godown empties and '
                          'added to full stock.',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
                GasLinesEditor(
                  key: _linesKey,
                  lines: _lines,
                  titles: const ['Found full'],
                  colors: const [AppColors.full],
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
                      key: const Key('saveExtraFull'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save Extra Full Cylinders',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
                if (isWide(context))
                  const KeyHints([
                    ('↓ or letter', 'List of gases'),
                    ('Enter', 'Next box'),
                    ('Enter on empty gas', 'Save'),
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
}
