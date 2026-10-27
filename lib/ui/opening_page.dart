import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'keys.dart';
import 'stock_guard.dart';
import 'theme.dart';
import 'widgets.dart';

/// Set or correct the opening full / empty stock for a day. Normally these
/// come automatically from the previous day; a typed value overrides it.
class OpeningPage extends StatefulWidget {
  final AppStore store;
  final String date;
  const OpeningPage({super.key, required this.store, required this.date});

  @override
  State<OpeningPage> createState() => _OpeningPageState();
}

class _OpeningPageState extends State<OpeningPage> {
  AppStore get store => widget.store;
  final Map<String, TextEditingController> _full = {};
  final Map<String, TextEditingController> _empty = {};
  final Map<String, int> _autoFull = {};
  final Map<String, int> _autoEmpty = {};
  bool _hasPrevious = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final stock = store.stock(widget.date);
    _hasPrevious = stock.hasPrevious;
    for (final r in stock.rows) {
      _full[r.gas.code] = qtyController(r.openFull);
      _empty[r.gas.code] = qtyController(r.openGodown);
      _autoFull[r.gas.code] = r.autoOpenFull;
      _autoEmpty[r.gas.code] = r.autoOpenGodown;
    }
  }

  @override
  void dispose() {
    for (final c in [..._full.values, ..._empty.values]) {
      c.dispose();
    }
    for (final n in [..._fullNodes.values, ..._emptyNodes.values]) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final day = store.day(widget.date);
    day.openFull = {};
    day.openEmpty = {};
    for (final g in kGases) {
      final f = qtyOf(_full[g.code]!);
      final e = qtyOf(_empty[g.code]!);
      // Store only real corrections so later changes to earlier days still
      // flow through.
      if (f != _autoFull[g.code]) day.openFull[g.code] = f;
      if (e != _autoEmpty[g.code]) day.openEmpty[g.code] = e;
    }
    if (!await stockAllowsSave(context, store, day)) return;
    await store.saveDay(day);
    if (mounted) Navigator.pop(context);
  }

  void _resetAuto() {
    setState(() {
      for (final g in kGases) {
        final f = _autoFull[g.code]!, e = _autoEmpty[g.code]!;
        _full[g.code]!.text = f == 0 ? '' : '$f';
        _empty[g.code]!.text = e == 0 ? '' : '$e';
      }
      _dirty = true;
    });
  }

  late final Map<String, FocusNode> _fullNodes = {
    for (final g in kGases) g.code: FocusNode(debugLabel: 'openFull_${g.code}'),
  };
  late final Map<String, FocusNode> _emptyNodes = {
    for (final g in kGases)
      g.code: FocusNode(debugLabel: 'openEmpty_${g.code}'),
  };

  void _move(Map<String, FocusNode> nodes, int from, int by) {
    final i = from + by;
    if (i >= 0 && i < kGases.length) nodes[kGases[i].code]!.requestFocus();
  }

  /// After the last box: "Save opening stock?" (Enter = yes, Esc = no).
  Future<void> _ask() async {
    final ok = await confirm(
      context,
      title: 'Save opening stock?',
      message: 'For ${fmtLong(parseDayKey(widget.date))}',
      yes: 'Yes, save',
    );
    if (ok) await _save();
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    const head = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      height: 1.15,
    );
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
              'Opening Stock  ·  ${fmtLong(parseDayKey(widget.date))}',
            ),
          ),
          body: PageWidth(
            max: 640,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                OldDateBanner(date: widget.date),
                Text(
                  _hasPrevious
                      ? 'These numbers come automatically from the previous '
                            'day\'s closing. Change them only if the real count is '
                            'different.'
                      : 'Write the full and empty cylinders you have at the '
                            'start of this day. From the next day on, this will '
                            'fill automatically.',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        color: AppColors.navy,
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 15,
                        ),
                        child: const Row(
                          children: [
                            Flexible(
                              child: SizedBox(
                                width: 150,
                                child: Text('Gas', style: head),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: Text(
                                'Opening\nFULL',
                                textAlign: TextAlign.center,
                                style: head,
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: Text(
                                'Opening EMPTY\n(Godown)',
                                textAlign: TextAlign.center,
                                style: head,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < kGases.length; i++) _row(i),
                    ],
                  ),
                ),
                if (_hasPrevious) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _resetAuto,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Use automatic numbers again'),
                    ),
                  ),
                ],
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
                    max: 640,
                    child: FilledButton.icon(
                      key: const Key('saveOpening'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save Opening Stock',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
                if (wide)
                  const KeyHints([
                    ('Enter', 'Next box'),
                    ('↑ ↓', 'Row above / below'),
                    ('Backspace (empty)', 'Previous box'),
                    ('Ctrl+A', 'Save'),
                    ('Esc', 'Back'),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(int i) {
    final g = kGases[i];
    final last = i == kGases.length - 1;
    void dirty() => setState(() => _dirty = true);
    return FocusRow(
      stripe: i.isOdd ? const Color(0xFFF7F9FC) : null,
      child: Row(
        children: [
          Flexible(
            child: SizedBox(
              width: 150,
              child: Text(
                g.label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Center(
              child: QtyField(
                key: Key('openFull_${g.code}'),
                controller: _full[g.code]!,
                focusNode: _fullNodes[g.code],
                autofocus: i == 0,
                color: AppColors.full,
                onChanged: dirty,
                onEnter: () => _emptyNodes[g.code]!.requestFocus(),
                onUp: () => _move(_fullNodes, i, -1),
                onDown: () => _move(_fullNodes, i, 1),
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: Center(
              child: QtyField(
                key: Key('openEmpty_${g.code}'),
                controller: _empty[g.code]!,
                focusNode: _emptyNodes[g.code],
                color: AppColors.empty,
                onChanged: dirty,
                onEnter: last ? _ask : () => _move(_fullNodes, i, 1),
                onUp: () => _move(_emptyNodes, i, -1),
                onDown: () => _move(_emptyNodes, i, 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
