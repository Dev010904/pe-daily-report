import 'dart:math';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'gas_lines.dart';
import 'keys.dart';
import 'stock_guard.dart';
import 'theme.dart';
import 'widgets.dart';

/// Filling for the day. Empties go from the godown to a filling plant
/// ("sent"), and filled cylinders come back from that plant ("filled
/// back"). Each can happen several times a day: every number typed is added
/// as a step (+11, later +3 = 14), nothing has to be added up by hand.
/// The app keeps count of the empties waiting at each plant:
/// at plant = start of day + sent − filled back.
/// DA has a line like the others, at the plant it is swapped at. Its logic
/// stays its own: the empties are swapped for filled ones at once, so no
/// DA empties stay at the plant.
class FillingPage extends StatefulWidget {
  final AppStore store;
  final String date;
  const FillingPage({super.key, required this.store, required this.date});

  @override
  State<FillingPage> createState() => _FillingPageState();
}

/// One plant + gas line.
class _Line {
  String gas;
  String? plantId;

  /// Came from saved data (plant and gas can't be changed any more).
  final bool fixed;

  /// Corrected count at the plant at the start of the day; null = automatic.
  int? openFix;
  List<int> sent;
  List<int> filled;
  final TextEditingController sentAdd = TextEditingController();
  final TextEditingController filledAdd = TextEditingController();

  /// ARGON lines only: a note (e.g. how many were ARGON SPL).
  final TextEditingController remark;
  final FocusNode gasNode = FocusNode(debugLabel: 'plantGas');
  final FocusNode sentNode = FocusNode(debugLabel: 'plantSent');
  final FocusNode filledNode = FocusNode(debugLabel: 'plantFilled');
  final FocusNode remarkNode = FocusNode(debugLabel: 'plantRemark');

  _Line(
    this.gas,
    this.plantId, {
    required this.fixed,
    this.openFix,
    List<int>? sent,
    List<int>? filled,
    String remark = '',
  }) : sent = sent ?? [],
       filled = filled ?? [],
       remark = TextEditingController(text: remark);

  bool get isDa => gas == 'DA';
  bool get hasRemark => gas == kArgon;
  String get remarkText => hasRemark ? remark.text.trim() : '';

  List<int> get sentAll => StepsField.withPending(sent, sentAdd);
  List<int> get filledAll => StepsField.withPending(filled, filledAdd);

  void dispose() {
    sentAdd.dispose();
    filledAdd.dispose();
    remark.dispose();
    gasNode.dispose();
    sentNode.dispose();
    filledNode.dispose();
    remarkNode.dispose();
  }
}

int _sum(List<int> l) => l.fold(0, (a, b) => a + b);

class _FillingPageState extends State<FillingPage> {
  AppStore get store => widget.store;

  /// Empties at each plant at the start of the day, carried on from the
  /// day before: gas -> plant -> qty.
  final PlantQty _auto = {};
  final List<_Line> _lines = [];
  final _addNode = FocusNode(debugLabel: 'addPlantLine');
  final Map<String, FocusNode> _oldFillNodes = {};

  /// Filling written before plant tracking (taken from godown empties).
  final Map<String, TextEditingController> _oldFill = {};
  bool _dirty = false;

  static final List<Gas> _plantGases = kGases
      .where((g) => g.canKeepAtPlant)
      .toList();

  @override
  void initState() {
    super.initState();
    final day = store.day(widget.date);
    final stock = store.stock(widget.date);
    for (final r in stock.rows) {
      for (final l in r.plantLines) {
        if (l.autoOpen != 0) (_auto[r.gas.code] ??= {})[l.plantId] = l.autoOpen;
      }
    }

    // gas -> plant -> steps
    final sent = <String, Map<String, List<int>>>{};
    final filled = <String, Map<String, List<int>>>{};
    for (final g in _plantGases) {
      for (final id in {...?day.plantSent[g.code]?.keys}) {
        (sent[g.code] ??= {})[id] = day.sentStepsOf(g.code, id);
      }
      for (final id in {...?day.plantFilled[g.code]?.keys}) {
        (filled[g.code] ??= {})[id] = day.filledStepsOf(g.code, id);
      }
    }
    final fill = Map.of(day.filling);
    // A day written the old way (plant count typed directly): turn the
    // change in the count into "sent" / "filled back". Same totals.
    if (day.plant != null) {
      for (final r in stock.rows) {
        if (!r.gas.canKeepAtPlant) continue;
        for (final l in r.plantLines) {
          final change = l.close - l.open;
          if (change > 0) (sent[r.gas.code] ??= {})[l.plantId] = [change];
          if (change < 0) {
            (filled[r.gas.code] ??= {})[l.plantId] = [-change];
            final left = max(0, (fill[r.gas.code] ?? 0) + change);
            if (left == 0) {
              fill.remove(r.gas.code);
            } else {
              fill[r.gas.code] = left;
            }
          }
        }
      }
    }

    for (final g in _plantGases) {
      final ids = {
        ...?_auto[g.code]?.keys,
        ...?day.openPlant[g.code]?.keys,
        ...?sent[g.code]?.keys,
        ...?filled[g.code]?.keys,
        // A line with only a note on it.
        for (final k in day.fillingRemarks.keys)
          if (k.startsWith('${g.code}|')) k.substring(g.code.length + 1),
      };
      for (final id in ids) {
        _lines.add(
          _Line(
            g.code,
            id,
            fixed: true,
            openFix: day.openPlant[g.code]?[id],
            sent: sent[g.code]?[id],
            filled: filled[g.code]?[id],
            remark: day.fillingRemarkOf(g.code, id),
          ),
        );
      }
    }
    // DA: one line, at the plant it was swapped at (old days: the usual DA
    // plant). With no DA yet, an empty line at the usual DA plant.
    final daFill = day.fillingStepsOf('DA'), daGiven = day.daGivenStepList;
    final daPlant = daFill.isEmpty && daGiven.isEmpty
        ? store.daPlantId
        : store.daPlantOf(day);
    if (daPlant != null || daFill.isNotEmpty || daGiven.isNotEmpty) {
      _lines.add(
        _Line(
          'DA',
          daPlant,
          fixed: daPlant != null,
          sent: daGiven,
          filled: daFill,
        ),
      );
    }

    // Group by plant name, gases in the usual order.
    final order = {for (var i = 0; i < kGases.length; i++) kGases[i].code: i};
    String name(_Line l) =>
        l.plantId == null ? '' : store.plantName(l.plantId!).toLowerCase();
    _lines.sort((a, b) {
      final n = name(a).compareTo(name(b));
      return n != 0 ? n : order[a.gas]!.compareTo(order[b.gas]!);
    });

    for (final g in _plantGases) {
      final v = fill[g.code] ?? 0;
      if (v > 0) {
        _oldFill[g.code] = qtyController(v);
        _oldFillNodes[g.code] = FocusNode(debugLabel: 'oldFill');
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_lines.isEmpty ? _addNode : _lines.first.sentNode).requestFocus();
    });
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _addNode.dispose();
    for (final n in _oldFillNodes.values) {
      n.dispose();
    }
    for (final c in _oldFill.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  int _autoOpen(_Line l) =>
      l.plantId == null ? 0 : (_auto[l.gas]?[l.plantId] ?? 0);
  int _open(_Line l) => l.openFix ?? _autoOpen(l);
  int _left(_Line l) => _open(l) + _sum(l.sentAll) - _sum(l.filledAll);

  bool _used(_Line l) => l.sentAll.isNotEmpty || l.filledAll.isNotEmpty;

  /// Enter on an empty "filled back": the ARGON note, else the next line.
  void _afterFilled(int i) {
    final l = _lines[i];
    if (l.hasRemark) {
      _focus(l.remarkNode);
    } else {
      _afterLine(i);
    }
  }

  /// DA is swapped at one plant a day: another line can take DA only while
  /// the DA line there is still empty (then that one is left unused).
  /// Other gases: one line per plant.
  bool _taken(_Line? me, String gas, String? plantId) => gas == 'DA'
      ? _lines.any((o) => o != me && o.isDa && _used(o))
      : plantId != null &&
            _lines.any((o) => o != me && o.gas == gas && o.plantId == plantId);

  void _alreadyListed(String gas, String? plantId) {
    if (gas == 'DA') {
      final at = _lines.firstWhere((o) => o.isDa && _used(o)).plantId;
      toast(
        context,
        'DA is already in the list${at == null ? '' : ' (${store.plantName(at)})'}. Write it there.',
      );
      return;
    }
    toast(
      context,
      '${store.plantName(plantId!)} - ${gasLabel(gas)} is already in the list. Write it there.',
    );
  }

  Future<void> _pickPlant(_Line l) async {
    final item = await pickNamed(
      context,
      title: 'Choose Filling Plant',
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

  void _focus(FocusNode n) => focusSoon(n);

  /// Enter on an empty "filled back": next line, then the old filling.
  void _afterLine(int i) {
    if (i + 1 < _lines.length) {
      _focus(_lines[i + 1].sentNode);
    } else if (_oldFillNodes.isNotEmpty) {
      _focus(_oldFillNodes.values.first);
    } else {
      _finish();
    }
  }

  /// Last box: "Save filling?" (Enter = yes, Esc = no, A = add a plant line).
  Future<void> _finish() async {
    final r = await askChoice(
      context,
      title: 'Save filling?',
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

  void _addLine() {
    final plants = store.activePlants;
    String? plantId = plants.length == 1 ? plants.first.id : null;
    var gas = _plantGases.first.code;
    if (plantId != null) {
      final free = _plantGases.where((g) => !_taken(null, g.code, plantId));
      if (free.isEmpty) {
        plantId = null;
      } else {
        gas = free.first.code;
      }
    }
    final line = _Line(gas, plantId, fixed: false);
    setState(() {
      _lines.add(line);
      _dirty = true;
    });
    if (plantId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickPlant(line);
      });
    } else {
      _focus(line.gasNode);
    }
  }

  Future<void> _editOpen(_Line l) async {
    final auto = _autoOpen(l);
    final c = qtyController(_open(l));
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${gasLabel(l.gas)} empty at ${store.plantName(l.plantId!)}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'How many empty cylinders were already at this plant at the '
              'start of this day? Change it only if the real count is different.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 14),
            Center(
              child: QtyField(
                key: const Key('plantOpenQty'),
                controller: c,
                color: AppColors.amber,
                autofocus: true,
                // Enter saves the corrected count.
                onEnter: () => Navigator.pop(ctx, qtyOf(c)),
              ),
            ),
          ],
        ),
        actions: [
          if (l.openFix != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: Text('Automatic ($auto)'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('plantOpenSave'),
            onPressed: () => Navigator.pop(ctx, qtyOf(c)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (r == null || !mounted) return;
    setState(() {
      l.openFix = (r == -1 || r == auto) ? null : r;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    for (final l in _lines) {
      final used =
          l.sentAll.isNotEmpty ||
          l.filledAll.isNotEmpty ||
          l.openFix != null ||
          l.remarkText.isNotEmpty;
      if (l.plantId == null && used) {
        toast(context, 'Choose the plant name for ${gasLabel(l.gas)}');
        return;
      }
    }
    if (_lines.where((l) => l.isDa && _used(l)).length > 1) {
      toast(
        context,
        'DA is written on two plant lines. DA is swapped at one plant a day: '
        'keep it on one line.',
      );
      return;
    }
    final day = store.day(widget.date);
    day.plant = null; // old way is replaced by sent / filled back
    day.clearFilling();
    for (final e in _oldFill.entries) {
      if (qtyOf(e.value) > 0) day.filling[e.key] = qtyOf(e.value);
    }
    day.openPlant = {};
    String? daPlant;
    for (final l in _lines) {
      final id = l.plantId;
      if (id == null) continue;
      if (l.isDa) {
        // Same DA logic as always: filled back = DA filled received (to
        // full stock), empty sent = DA empty given (out of the godown).
        if (_used(l)) {
          day.setFillingSteps('DA', l.filledAll);
          day.setDaGivenSteps(l.sentAll);
          day.daPlant = daPlant = id;
        }
        continue;
      }
      day.addPlantSteps(sent: true, gas: l.gas, plant: id, steps: l.sentAll);
      day.addPlantSteps(sent: false, gas: l.gas, plant: id, steps: l.filledAll);
      if (l.remarkText.isNotEmpty) {
        day.fillingRemarks[fillingRemarkKey(l.gas, id)] = l.remarkText;
      }
      if (l.openFix != null && l.openFix != _autoOpen(l)) {
        (day.openPlant[l.gas] ??= {})[id] = l.openFix!;
      }
    }

    if (!await stockAllowsSave(context, store, day)) return;
    await store.saveDay(day);
    if (daPlant != null) await store.setDaPlant(daPlant);
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
              'Filling / Plant  ·  ${fmtLong(parseDayKey(widget.date))}',
            ),
          ),
          body: PageWidth(
            max: 660,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                OldDateBanner(date: widget.date),
                _plantCard(),
                if (_oldFill.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _oldFillCard(),
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
                    max: 660,
                    child: FilledButton.icon(
                      key: const Key('saveFilling'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save Filling',
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

  // ------------------------------------------------------------ plants

  Widget _plantCard() {
    return Card(
      color: AppColors.amberBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.amberLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.factory, color: AppColors.amber),
                SizedBox(width: 8),
                Text(
                  'Filling Plant',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Type a number and press Enter to add it. Filled again later? '
              'Just add the new number, the app adds them up.',
              style: TextStyle(fontSize: 14.5),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _lines.length; i++) _lineCard(i),
            OutlinedButton.icon(
              key: const Key('addPlantLine'),
              focusNode: _addNode,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.amber,
                side: const BorderSide(color: AppColors.amber),
                backgroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: _addLine,
              icon: const Icon(Icons.add),
              label: const Text(
                'Add plant / gas',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    final open = _open(l);
    final left = _left(l);
    final sent = l.sentAll, filled = l.filledAll;
    final calc = StringBuffer('$open');
    for (final x in sent) {
      calc.write(' + $x');
    }
    for (final x in filled) {
      calc.write(' − $x');
    }
    if (sent.isNotEmpty || filled.isNotEmpty) calc.write(' = $left');
    final canDelete = !l.fixed || l.isDa || _autoOpen(l) == 0;

    return Container(
      // Each line keeps its own boxes when a line above is removed.
      key: ObjectKey(l),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amberLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (l.fixed) ...[
                const Icon(
                  Icons.factory_outlined,
                  color: AppColors.amber,
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
                    color: AppColors.navy,
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
                    key: Key('plantPick$i'),
                    onTap: () => _pickPlant(l),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Plant',
                        isDense: true,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.plantId == null
                                  ? 'Choose'
                                  : store.plantName(l.plantId!),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: l.plantId == null
                                    ? AppColors.amber
                                    : const Color(0xFF1B2330),
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: GasPickField(
                    key: Key('plantGas$i'),
                    value: l.gas,
                    focusNode: l.gasNode,
                    // DA stays listed: picking it when another line has DA
                    // says where it is.
                    onPicked: (v) {
                      if (_taken(l, v, l.plantId)) {
                        _alreadyListed(v, l.plantId);
                        return;
                      }
                      setState(() {
                        l.gas = v;
                        _dirty = true;
                      });
                      _focus(l.sentNode);
                    },
                  ),
                ),
              ],
              if (canDelete)
                ExcludeFocus(
                  child: IconButton(
                    key: Key('plantDel$i'),
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
          ),
          const SizedBox(height: 4),
          if (!l.isDa)
            _row(
              'At plant (start of day)',
              null,
              AppColors.muted,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$open',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.amber,
                    ),
                  ),
                  if (l.openFix != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.edit, size: 13, color: AppColors.amber),
                    ),
                  ExcludeFocus(
                    child: IconButton(
                      key: Key('plantOpenEdit$i'),
                      tooltip: 'Correct the count at the plant',
                      visualDensity: VisualDensity.compact,
                      onPressed: l.plantId == null ? null : () => _editOpen(l),
                      icon: const Icon(Icons.edit_note, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          _row(
            'Empty sent',
            'taken out of godown',
            AppColors.empty,
            StepsField(
              fieldKey: Key('plantSent$i'),
              steps: l.sent,
              controller: l.sentAdd,
              focusNode: l.sentNode,
              color: AppColors.empty,
              onChanged: (s) {
                l.sent = s;
                _touch();
              },
              onNext: () => _focus(l.filledNode),
            ),
          ),
          _row(
            'Filled back',
            'added to full stock',
            AppColors.full,
            StepsField(
              fieldKey: Key('plantFilled$i'),
              steps: l.filled,
              controller: l.filledAdd,
              focusNode: l.filledNode,
              color: AppColors.full,
              onChanged: (s) {
                l.filled = s;
                _touch();
              },
              onNext: () => _afterFilled(i),
            ),
          ),
          if (l.hasRemark)
            // Phone: the box under its label, so the note fits.
            MediaQuery.sizeOf(context).width < 560
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Remarks  (e.g. ARGON SPL)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.groupAr,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _remarkBox(i, l),
                      ],
                    ),
                  )
                : _row(
                    'Remarks',
                    'e.g. ARGON SPL',
                    AppColors.groupAr,
                    _remarkBox(i, l),
                  ),
          const SizedBox(height: 6),
          if (l.isDa)
            Container(
              key: Key('plantLeft$i'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.amberBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'DA is swapped at the plant: filled back = DA filled received, '
                'empty sent = DA empty given. No DA empties stay at the plant.',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF6B4A00)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: left < 0
                    ? AppColors.danger.withValues(alpha: 0.08)
                    : AppColors.amberBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 170,
                    child: Text(
                      left < 0
                          ? 'More filled back than sent!'
                          : 'Empty still at plant',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: left < 0
                            ? AppColors.danger
                            : const Color(0xFF6B4A00),
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      calc.toString(),
                      key: Key('plantLeft$i'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: left < 0 ? AppColors.danger : AppColors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The ARGON line's note; Enter goes on to the next line.
  Widget _remarkBox(int i, _Line l) => TextField(
    key: Key('plantRemark$i'),
    controller: l.remark,
    focusNode: l.remarkNode,
    maxLength: 80,
    textCapitalization: TextCapitalization.characters,
    textInputAction: TextInputAction.next,
    onChanged: (_) => _touch(),
    onSubmitted: (_) {
      if (!onTopPage(context)) {
        reclaimDialogFocus();
        return;
      }
      _afterLine(i);
    },
    onEditingComplete: () {},
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    decoration: const InputDecoration(
      isDense: true,
      counterText: '',
      hintText: 'Remarks',
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    ),
  );

  /// Label close to its value (not pushed to the far edge).
  Widget _row(String title, String? note, Color color, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 170,
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

  // ------------------------------------------------------ old entries

  Widget _oldFillCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Filled (old entry)',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const Text(
            'Written before plant tracking. These were taken out of the '
            'godown empties.',
            style: TextStyle(fontSize: 13.5, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          for (final e in _oldFill.entries)
            _row(
              gasLabel(e.key),
              'filled',
              AppColors.full,
              Align(
                alignment: Alignment.centerLeft,
                child: QtyField(
                  key: Key('fill_${e.key}'),
                  controller: e.value,
                  color: AppColors.full,
                  onChanged: _touch,
                  focusNode: _oldFillNodes[e.key],
                  onEnter: () {
                    final keys = _oldFillNodes.keys.toList();
                    final at = keys.indexOf(e.key);
                    if (at + 1 < keys.length) {
                      _focus(_oldFillNodes[keys[at + 1]]!);
                    } else {
                      _finish();
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
