import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'gas_lines.dart';
import 'keys.dart';
import 'stock_guard.dart';
import 'theme.dart';
import 'widgets.dart';

/// Loan cylinders for the day: cylinders borrowed from a filling plant when
/// ours are short. They come FULL (ready to supply), go out to companies
/// like ours (written in the entry, under "Loan cylinders"), come back
/// empty, and are given back to their plant. They are counted apart from
/// our own cylinders, plant by plant and gas by gas.
class LoanPage extends StatefulWidget {
  final AppStore store;
  final String date;
  const LoanPage({super.key, required this.store, required this.date});

  @override
  State<LoanPage> createState() => _LoanPageState();
}

/// One plant + gas line.
class _Line {
  String gas;
  String? plantId;

  /// Already had loan cylinders (plant and gas can't be changed).
  final bool fixed;
  List<int> taken;
  List<int> backEmpty;
  List<int> backFull;
  final takenAdd = TextEditingController();
  final backEmptyAdd = TextEditingController();
  final backFullAdd = TextEditingController();
  final gasNode = FocusNode(debugLabel: 'loanGas');
  final takenNode = FocusNode(debugLabel: 'loanTaken');
  final backEmptyNode = FocusNode(debugLabel: 'loanBackEmpty');
  final backFullNode = FocusNode(debugLabel: 'loanBackFull');

  _Line(
    this.gas,
    this.plantId, {
    required this.fixed,
    List<int>? taken,
    List<int>? backEmpty,
    List<int>? backFull,
  }) : taken = taken ?? [],
       backEmpty = backEmpty ?? [],
       backFull = backFull ?? [];

  List<int> get takenAll => StepsField.withPending(taken, takenAdd);
  List<int> get backEmptyAll => StepsField.withPending(backEmpty, backEmptyAdd);
  List<int> get backFullAll => StepsField.withPending(backFull, backFullAdd);

  bool get used =>
      takenAll.isNotEmpty || backEmptyAll.isNotEmpty || backFullAll.isNotEmpty;

  void dispose() {
    for (final c in [takenAdd, backEmptyAdd, backFullAdd]) {
      c.dispose();
    }
    for (final n in [gasNode, takenNode, backEmptyNode, backFullNode]) {
      n.dispose();
    }
  }
}

int _sum(List<int> l) => l.fold(0, (a, b) => a + b);
List<int> _one(int v) => v == 0 ? [] : [v];

class _LoanPageState extends State<LoanPage> {
  AppStore get store => widget.store;
  final List<_Line> _lines = [];
  final _addNode = FocusNode(debugLabel: 'addLoanLine');
  bool _dirty = false;

  /// The day's loan lines as worked out from what is saved (start of day,
  /// supplied and empty received in the entries, with companies).
  final Map<String, LoanLine> _stock = {};

  static String _key(String gas, String plant) => '$gas|$plant';

  @override
  void initState() {
    super.initState();
    final day = store.day(widget.date);
    for (final (gas, l) in store.loanLinesOn(widget.date)) {
      _stock[_key(gas.code, l.plantId)] = l;
      _lines.add(
        _Line(
          gas.code,
          l.plantId,
          fixed: true,
          taken: _one(day.loanIn[gas.code]?[l.plantId] ?? 0),
          backEmpty: _one(day.loanBackEmpty[gas.code]?[l.plantId] ?? 0),
          backFull: _one(day.loanBackFull[gas.code]?[l.plantId] ?? 0),
        ),
      );
    }
    final order = {for (var i = 0; i < kGases.length; i++) kGases[i].code: i};
    _lines.sort((a, b) {
      final n = store
          .plantName(a.plantId!)
          .toLowerCase()
          .compareTo(store.plantName(b.plantId!).toLowerCase());
      return n != 0 ? n : order[a.gas]!.compareTo(order[b.gas]!);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lines.isEmpty) {
        _addNode.requestFocus();
      } else if (isWide(context)) {
        _lines.first.takenNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _addNode.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);
  void _focus(FocusNode n) => focusSoon(n);

  bool _taken(_Line? me, String gas, String? plantId) =>
      plantId != null &&
      _lines.any((o) => o != me && o.gas == gas && o.plantId == plantId);

  void _alreadyListed(String gas, String plantId) => toast(
    context,
    '${store.plantName(plantId)} - ${gasLabel(gas)} is already in the list. Write it there.',
  );

  Future<void> _pickPlant(_Line l) async {
    final item = await pickNamed(
      context,
      title: 'Loan from which plant?',
      items: store.activePlants,
      addLabel: 'Add new filling plant',
      onAdd: store.addPlant,
    );
    if (item == null || !mounted) return;
    if (_taken(l, l.gas, item.id)) {
      _alreadyListed(l.gas, item.id);
      return;
    }
    setState(() {
      l.plantId = item.id;
      _dirty = true;
    });
    _focus(l.gasNode);
  }

  void _addLine() {
    final plants = store.activePlants;
    final line = _Line(
      kGases.first.code,
      plants.length == 1 ? plants.first.id : null,
      fixed: false,
    );
    if (line.plantId != null) {
      final free = kGases.where((g) => !_taken(null, g.code, line.plantId));
      if (free.isEmpty) {
        line.plantId = null;
      } else {
        line.gas = free.first.code;
      }
    }
    setState(() {
      _lines.add(line);
      _dirty = true;
    });
    if (line.plantId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickPlant(line);
      });
    } else {
      _focus(line.gasNode);
    }
  }

  void _afterLine(int i) {
    if (i + 1 < _lines.length) {
      _focus(_lines[i + 1].takenNode);
    } else {
      _finish();
    }
  }

  /// Last box: "Save loan cylinders?" (Enter = yes, Esc = no, A = add line).
  Future<void> _finish() async {
    final r = await askChoice(
      context,
      title: 'Save loan cylinders?',
      message: 'For ${fmtLong(parseDayKey(widget.date))}',
      yes: 'Yes, save',
      more: const {'a': 'Add plant / gas line'},
    );
    if (!mounted) return;
    if (r == 'yes') {
      await _save();
    } else if (r == 'a') {
      _addLine();
    }
  }

  Future<void> _save() async {
    for (final l in _lines) {
      if (l.plantId == null && l.used) {
        toast(context, 'Choose the plant for ${gasLabel(l.gas)}');
        return;
      }
    }
    final day = store.day(widget.date);
    day.loanIn = {};
    day.loanBackEmpty = {};
    day.loanBackFull = {};
    for (final l in _lines) {
      final id = l.plantId;
      if (id == null) continue;
      addPlantQty(day.loanIn, l.gas, id, _sum(l.takenAll));
      addPlantQty(day.loanBackEmpty, l.gas, id, _sum(l.backEmptyAll));
      addPlantQty(day.loanBackFull, l.gas, id, _sum(l.backFullAll));
    }
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
              'Loan Cylinders  ·  ${fmtLong(parseDayKey(widget.date))}',
            ),
          ),
          body: PageWidth(
            max: 700,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                OldDateBanner(date: widget.date),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.loanBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.loan.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'Cylinders borrowed from a filling plant when ours are short. They '
                    'come FULL and can be supplied at once (in the entry, under "Loan '
                    'cylinders"). Write here what was taken from the plant and what was '
                    'given back to it. They are counted apart from our own cylinders.',
                    style: TextStyle(fontSize: 14.5),
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                OutlinedButton.icon(
                  key: const Key('addLoanLine'),
                  focusNode: _addNode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.loan,
                    side: const BorderSide(color: AppColors.loan),
                    backgroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Loan from a plant (plant / gas)',
                    style: TextStyle(fontSize: 16),
                  ),
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
                    max: 700,
                    child: FilledButton.icon(
                      key: const Key('saveLoan'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save Loan Cylinders',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
                if (isWide(context))
                  const KeyHints([
                    ('Number + Enter', 'Add it (+)'),
                    ('Enter on empty box', 'Next'),
                    ('Backspace', 'Take last off'),
                    ('↑', 'Previous box'),
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

  Widget _lineCard(int i) {
    final l = _lines[i];
    final s = l.plantId == null ? null : _stock[_key(l.gas, l.plantId!)];
    final taken = _sum(l.takenAll),
        backE = _sum(l.backEmptyAll),
        backF = _sum(l.backFullAll);
    final openF = s?.openFull ?? 0, supplied = s?.supplied ?? 0;
    final openE = s?.openEmpty ?? 0, emptyBack = s?.emptyBack ?? 0;
    final atCos = s?.atCompanies ?? 0;
    final closeF = openF + taken - supplied - backF;
    final closeE = openE + emptyBack - backE;
    final toReturn = closeF + closeE + atCos;
    String calc(int open, List<(String, int)> parts, int close) {
      final moves = parts.where((p) => p.$2 != 0);
      if (moves.isEmpty) return '$close';
      return '$open ${moves.map((p) => '${p.$1} ${p.$2}').join(' ')} = $close';
    }

    final cos = l.plantId == null
        ? const <String, int>{}
        : store.loanCompaniesFor(l.gas, l.plantId!, widget.date);

    return Container(
      key: ObjectKey(l),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.loan.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (l.fixed) ...[
                const Icon(
                  Icons.factory_outlined,
                  color: AppColors.loan,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    store.plantName(l.plantId!),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.loan,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    gasLabel(l.gas),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
              ] else ...[
                Expanded(
                  child: InkWell(
                    key: Key('loanPlant$i'),
                    onTap: () => _pickPlant(l),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Plant',
                        isDense: true,
                      ),
                      child: Text(
                        l.plantId == null
                            ? 'Choose'
                            : store.plantName(l.plantId!),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: l.plantId == null
                              ? AppColors.loan
                              : const Color(0xFF1B2330),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: GasPickField(
                    key: Key('loanGas$i'),
                    value: l.gas,
                    focusNode: l.gasNode,
                    onPicked: (v) {
                      if (_taken(l, v, l.plantId)) {
                        _alreadyListed(v, l.plantId!);
                        return;
                      }
                      setState(() {
                        l.gas = v;
                        _dirty = true;
                      });
                      _focus(l.takenNode);
                    },
                  ),
                ),
                ExcludeFocus(
                  child: IconButton(
                    key: Key('loanDel$i'),
                    tooltip: 'Remove',
                    onPressed: () => setState(() {
                      _lines.removeAt(i).dispose();
                      _dirty = true;
                    }),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          _row(
            'Taken from plant',
            'full, ready to supply',
            AppColors.loan,
            StepsField(
              fieldKey: Key('loanTaken$i'),
              steps: l.taken,
              controller: l.takenAdd,
              focusNode: l.takenNode,
              color: AppColors.loan,
              onChanged: (v) {
                l.taken = v;
                _touch();
              },
              onNext: () => _focus(l.backEmptyNode),
            ),
          ),
          _row(
            'Given back empty',
            'to the plant',
            AppColors.empty,
            StepsField(
              fieldKey: Key('loanBackEmpty$i'),
              steps: l.backEmpty,
              controller: l.backEmptyAdd,
              focusNode: l.backEmptyNode,
              color: AppColors.empty,
              onChanged: (v) {
                l.backEmpty = v;
                _touch();
              },
              onNext: () => _focus(l.backFullNode),
            ),
          ),
          _row(
            'Given back full',
            'not supplied',
            AppColors.full,
            StepsField(
              fieldKey: Key('loanBackFull$i'),
              steps: l.backFull,
              controller: l.backFullAdd,
              focusNode: l.backFullNode,
              color: AppColors.full,
              onChanged: (v) {
                l.backFull = v;
                _touch();
              },
              onNext: () => _afterLine(i),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            key: Key('loanStatus$i'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.loanBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _info(
                  'Full in godown',
                  calc(openF, [
                    ('+', taken),
                    ('− supplied', supplied),
                    ('− back', backF),
                  ], closeF),
                  bad: closeF < 0,
                ),
                _info(
                  'Empty in godown',
                  calc(openE, [
                    ('+ came back', emptyBack),
                    ('− back', backE),
                  ], closeE),
                  bad: closeE < 0,
                ),
                _info(
                  'With companies',
                  cos.isEmpty
                      ? '$atCos'
                      : '$atCos   (${cos.entries.map((e) => '${e.key} ${e.value}').join(', ')})',
                ),
                const SizedBox(height: 2),
                Text(
                  'Still to give back to the plant:  $toReturn',
                  key: Key('loanToReturn$i'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.loan,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value, {bool bad = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: bad ? AppColors.danger : const Color(0xFF1B2330),
            ),
          ),
        ),
      ],
    ),
  );

  /// Label close to its value (not pushed to the far edge).
  Widget _row(String title, String? note, Color color, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (note != null)
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ),
        Flexible(child: value),
      ],
    ),
  );
}
