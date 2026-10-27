import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../models/vehicle.dart';
import '../util/dates.dart';
import 'keys.dart';
import 'pick_field.dart';
import 'theme.dart';
import 'widgets.dart';

// ------------------------------------------------------------- status look

const Color _soon = Color(0xFFE65100);

/// Red when expired or expiring today, orange within the alert days, green
/// otherwise.
Color paperColor(int daysLeft) => daysLeft <= 0
    ? AppColors.danger
    : (daysLeft <= kPaperAlertDays ? _soon : AppColors.full);

/// "URGENT – RENEW · expired 2 days ago", "RENEW SOON · expires in 6 days"...
String paperAlertText(int daysLeft) {
  if (daysLeft < 0) {
    return 'URGENT – RENEW  ·  expired ${-daysLeft} ${-daysLeft == 1 ? 'day' : 'days'} ago';
  }
  if (daysLeft == 0) return 'URGENT – RENEW  ·  expires TODAY';
  return 'RENEW SOON  ·  ${daysLeft == 1 ? '1 day' : '$daysLeft days'} left';
}

/// A coloured label with the paper's state.
class PaperStatus extends StatelessWidget {
  final VehiclePaper paper;
  final bool big;
  const PaperStatus(this.paper, {super.key, this.big = false});

  @override
  Widget build(BuildContext context) {
    final d = paper.daysLeft();
    final c = paperColor(d);
    final text = d <= kPaperAlertDays ? paperAlertText(d) : paper.statusText();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: d <= 0 ? 1 : 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: big ? 14.5 : 13,
          fontWeight: FontWeight.w900,
          color: d <= 0 ? Colors.white : c,
        ),
      ),
    );
  }
}

/// "01-10-2026 to 30-09-2027" (or "till 30-09-2027").
String paperDates(VehiclePaper p) {
  final till = fmtDmy(parseDayKey(p.till));
  return p.from == null
      ? 'till $till'
      : '${fmtDmy(parseDayKey(p.from!))} to $till';
}

/// One paper to renew, for the Dashboard and the daily reminder.
class PaperAlertRow extends StatelessWidget {
  final PaperAlert alert;
  final bool selected;
  final int index;
  const PaperAlertRow(
    this.alert, {
    super.key,
    this.selected = false,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final d = alert.daysLeft;
    final c = paperColor(d);
    final name = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: alert.vehicle.number,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          TextSpan(
            text: '   ${alert.paper.type}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    final when = Text(
      '${d < 0 ? 'Expired on' : 'Expires on'} ${fmtLong(parseDayKey(alert.paper.till))}',
      style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
    );
    final status = Text(
      paperAlertText(d),
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c),
    );
    // Narrow (phone): the state goes under the name, so the vehicle
    // number stays on one line.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return _frame(
      selected,
      c,
      d,
      Row(
        children: [
          Icon(
            d < 0 ? Icons.warning_rounded : Icons.event_busy,
            color: c,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [name, when, if (narrow) status],
            ),
          ),
          if (!narrow) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: status),
            ),
          ],
        ],
      ),
    );
  }

  Widget _frame(bool selected, Color c, int d, Widget child) {
    return Container(
      key: Key('paperAlert_${alert.vehicle.id}_${alert.paper.id}'),
      decoration: BoxDecoration(
        color: selected
            ? kSelectBg
            : (d < 0
                  ? AppColors.danger.withValues(alpha: 0.06)
                  : (index.isOdd ? const Color(0xFFF7F9FC) : Colors.white)),
        border: Border(
          left: BorderSide(color: selected ? kSelectLine : c, width: 5),
          top: const BorderSide(color: Color(0xFFE6EAF0)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: child,
    );
  }
}

DateTime? _shownOn;

/// Once a day (the first time the app is opened that day): a box with every
/// paper to renew. Returns true when the person chose to open the vehicles.
Future<bool> showPaperReminder(BuildContext context, AppStore store) async {
  final alerts = store.paperAlerts();
  final now = today();
  if (alerts.isEmpty || (_shownOn != null && sameDay(_shownOn!, now))) {
    return false;
  }
  _shownOn = now;
  final urgent = alerts.where((a) => a.daysLeft <= 0).length;
  final r = await askChoice(
    context,
    title: urgent > 0
        ? 'URGENT: vehicle papers to renew'
        : 'Vehicle papers to renew',
    yes: 'OK',
    no: 'Later',
    more: const {'v': 'Open Vehicles'},
    extra: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < alerts.length; i++)
            PaperAlertRow(alerts[i], index: i),
        ],
      ),
    ),
  );
  return r == 'v';
}

// ------------------------------------------------------------ all vehicles

/// The delivery vehicles and their papers. N = new vehicle, Enter = open,
/// Del = remove.
class VehiclesPage extends StatefulWidget {
  final AppStore store;
  const VehiclesPage({super.key, required this.store});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  AppStore get store => widget.store;
  final _listFocus = FocusNode(debugLabel: 'vehicles');

  @override
  void dispose() {
    _listFocus.dispose();
    super.dispose();
  }

  Future<void> _open(Vehicle v, {bool addFirst = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VehiclePage(store: store, vehicleId: v.id, addFirst: addFirst),
      ),
    );
    if (mounted) _listFocus.requestFocus();
  }

  Future<void> _add() async {
    final number = await askText(
      context,
      title: 'New vehicle',
      hint: 'Vehicle number, e.g. GJ 01 AB 1234',
      ok: 'Add',
    );
    if (number == null || number.trim().isEmpty || !mounted) return;
    final same = store.vehicleWithNumber(number);
    if (same != null) {
      toast(context, '${same.number} is already in the list.');
      return;
    }
    final v = await store.addVehicle(number);
    if (mounted) await _open(v, addFirst: true);
  }

  Future<void> _remove(Vehicle v) async {
    final ok = await confirm(
      context,
      title: 'Remove ${v.number}?',
      message: 'The vehicle and all its papers will be removed.',
      yes: 'Remove',
      danger: true,
    );
    if (ok) await store.removeVehicle(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.vehicles;
        final wide = isWide(context);
        return KeyPage(
          letters: {'n': _add},
          child: Scaffold(
            appBar: AppBar(title: const Text('Vehicles & Papers')),
            floatingActionButton: wide
                ? null
                : FloatingActionButton.extended(
                    key: const Key('addVehicle'),
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add vehicle'),
                  ),
            bottomNavigationBar: wide
                ? const KeyHints([
                    ('↑ ↓', 'Move'),
                    ('Enter', 'Open'),
                    ('N', 'New vehicle'),
                    ('Del', 'Remove'),
                    ('Esc', 'Back'),
                  ])
                : null,
            body: PageWidth(
              max: 820,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  const Text(
                    'Add each delivery vehicle and its papers (PUC, insurance ...) with '
                    'their dates. From $kPaperAlertDays days before a paper runs out, the '
                    'Dashboard reminds you every day until it is renewed.',
                    style: TextStyle(fontSize: 14.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No vehicles yet. Press N (or the button) to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: AppColors.muted),
                      ),
                    ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: KeyList(
                      focusNode: _listFocus,
                      autofocus: true,
                      itemCount: list.length,
                      onOpen: (i) => _open(list[i]),
                      onDelete: (i) => _remove(list[i]),
                      itemBuilder: (context, i, selected) =>
                          _vehicleRow(list[i], i, selected),
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ExcludeFocus(
                        child: OutlinedButton.icon(
                          key: const Key('addVehicle'),
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: const Text('Add vehicle (N)'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _vehicleRow(Vehicle v, int i, bool selected) {
    final papers = v.byExpiry;
    return Container(
      key: Key('vehicle_${v.id}'),
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
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_shipping, color: AppColors.navy, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.number,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                if (papers.isEmpty)
                  const Text(
                    'No papers yet',
                    style: TextStyle(fontSize: 14, color: AppColors.muted),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final p in papers)
                        // Wraps on a narrow phone instead of running off.
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 2,
                          children: [
                            Text(
                              '${p.type}: ',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            PaperStatus(p),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- one vehicle

/// One vehicle's papers. Enter / R = renewed (new dates), E = change,
/// N = add paper, Del = remove paper, C = change the number.
class VehiclePage extends StatefulWidget {
  final AppStore store;
  final String vehicleId;

  /// Open "Add paper" straight away (a vehicle just added).
  final bool addFirst;
  const VehiclePage({
    super.key,
    required this.store,
    required this.vehicleId,
    this.addFirst = false,
  });

  @override
  State<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  AppStore get store => widget.store;
  final _listKey = GlobalKey<KeyListState>();
  final _listFocus = FocusNode(debugLabel: 'papers');

  @override
  void initState() {
    super.initState();
    if (widget.addFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _paper(null);
      });
    }
  }

  @override
  void dispose() {
    _listFocus.dispose();
    super.dispose();
  }

  List<VehiclePaper> _papers() =>
      store.vehicle(widget.vehicleId)?.byExpiry ?? const [];

  VehiclePaper? get _selected {
    final list = _papers();
    final i = _listKey.currentState?.selected ?? 0;
    return list.isEmpty ? null : list[i.clamp(0, list.length - 1)];
  }

  Future<void> _paper(VehiclePaper? p, {bool renew = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaperPage(
          store: store,
          vehicleId: widget.vehicleId,
          paperId: p?.id,
          renew: renew,
        ),
      ),
    );
    if (mounted) _listFocus.requestFocus();
  }

  Future<void> _remove(VehiclePaper p) async {
    final v = store.vehicle(widget.vehicleId);
    if (v == null) return;
    final ok = await confirm(
      context,
      title: 'Remove ${p.type}?',
      message:
          '${p.type} of ${v.number} will be removed (no more reminders for it).',
      yes: 'Remove',
      danger: true,
    );
    if (!ok) return;
    v.papers.removeWhere((x) => x.id == p.id);
    await store.saveVehicle(v);
  }

  Future<void> _changeNumber() async {
    final v = store.vehicle(widget.vehicleId);
    if (v == null) return;
    final number = await askText(
      context,
      title: 'Vehicle number',
      initial: v.number,
      hint: 'e.g. GJ 01 AB 1234',
    );
    if (number == null || number.trim().isEmpty || !mounted) return;
    final same = store.vehicleWithNumber(number, except: v.id);
    if (same != null) {
      toast(context, '${same.number} is already in the list.');
      return;
    }
    v.number = number.trim().toUpperCase();
    await store.saveVehicle(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final v = store.vehicle(widget.vehicleId);
        if (v == null) {
          return const Scaffold(body: Center(child: Text('Vehicle not found')));
        }
        final papers = v.byExpiry;
        final wide = isWide(context);
        return KeyPage(
          letters: {
            'n': () => _paper(null),
            'r': () {
              final p = _selected;
              if (p != null) _paper(p, renew: true);
            },
            'e': () {
              final p = _selected;
              if (p != null) _paper(p);
            },
            'c': _changeNumber,
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(v.number),
              actions: [
                IconButton(
                  key: const Key('changeNumber'),
                  tooltip: 'Change number (C)',
                  onPressed: _changeNumber,
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
            floatingActionButton: wide
                ? null
                : FloatingActionButton.extended(
                    key: const Key('addPaper'),
                    onPressed: () => _paper(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add paper'),
                  ),
            bottomNavigationBar: wide
                ? const KeyHints([
                    ('↑ ↓', 'Move'),
                    ('Enter / R', 'Renewed: new dates'),
                    ('E', 'Change'),
                    ('N', 'Add paper'),
                    ('Del', 'Remove'),
                    ('C', 'Change number'),
                    ('Esc', 'Back'),
                  ])
                : null,
            body: PageWidth(
              max: 820,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  if (papers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No papers yet. Press N (or the button) to add PUC, insurance ...',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: AppColors.muted),
                      ),
                    ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: KeyList(
                      key: _listKey,
                      focusNode: _listFocus,
                      autofocus: !widget.addFirst,
                      itemCount: papers.length,
                      onOpen: (i) => _paper(papers[i], renew: true),
                      onDelete: (i) => _remove(papers[i]),
                      itemBuilder: (context, i, selected) =>
                          _paperRow(papers[i], i, selected, wide),
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ExcludeFocus(
                        child: OutlinedButton.icon(
                          key: const Key('addPaper'),
                          onPressed: () => _paper(null),
                          icon: const Icon(Icons.add),
                          label: const Text('Add paper (N)'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _paperRow(VehiclePaper p, int i, bool selected, bool wide) {
    final buttons = ExcludeFocus(
      child: Wrap(
        spacing: 4,
        children: [
          FilledButton.tonal(
            key: Key('renew_${p.id}'),
            onPressed: () => _paper(p, renew: true),
            child: const Text('Renewed'),
          ),
          IconButton(
            key: Key('editPaper_${p.id}'),
            tooltip: 'Change',
            onPressed: () => _paper(p),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: Key('removePaper_${p.id}'),
            tooltip: 'Remove',
            onPressed: () => _remove(p),
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
          ),
        ],
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.type,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          paperDates(p),
          style: const TextStyle(fontSize: 14.5, color: Color(0xFF39424F)),
        ),
        const SizedBox(height: 4),
        PaperStatus(p),
      ],
    );
    return Container(
      key: Key('paper_${p.id}'),
      decoration: BoxDecoration(
        color: selected
            ? kSelectBg
            : (i.isOdd ? const Color(0xFFF7F9FC) : Colors.white),
        border: Border(
          left: BorderSide(
            color: selected ? kSelectLine : paperColor(p.daysLeft()),
            width: 5,
          ),
          top: const BorderSide(color: Color(0xFFE6EAF0)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: wide
          ? Row(
              children: [
                Expanded(child: info),
                buttons,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 6), buttons],
            ),
    );
  }
}

// ------------------------------------------------------- add / renew paper

class _TypeChoice {
  final String name;
  final bool isNew;
  _TypeChoice(this.name, {this.isNew = false});
  String get label => isNew ? 'Use "$name"' : name;
}

/// Add a paper, change it, or (renew) write the new dates after renewing.
/// Renewing replaces the dates; the old ones are not kept, and the reminder
/// countdown starts again from the new last day.
class PaperPage extends StatefulWidget {
  final AppStore store;
  final String vehicleId;

  /// Null = a new paper.
  final String? paperId;
  final bool renew;
  const PaperPage({
    super.key,
    required this.store,
    required this.vehicleId,
    this.paperId,
    this.renew = false,
  });

  @override
  State<PaperPage> createState() => _PaperPageState();
}

class _PaperPageState extends State<PaperPage> {
  AppStore get store => widget.store;
  late final Vehicle _v = store.vehicle(widget.vehicleId)!;
  VehiclePaper? _p;
  final _type = TextEditingController();
  final _from = TextEditingController();
  final _till = TextEditingController();
  final _typeNode = FocusNode(debugLabel: 'paperType');
  final _fromNode = FocusNode(debugLabel: 'paperFrom');
  final _tillNode = FocusNode(debugLabel: 'paperTill');
  bool _dirty = false;

  bool get _isNew => _p == null;

  @override
  void initState() {
    super.initState();
    for (final p in _v.papers) {
      if (p.id == widget.paperId) _p = p;
    }
    final p = _p;
    if (p != null) {
      _type.text = p.type;
      if (widget.renew) {
        // Suggest the next period: from the day after the old one ran out
        // (or today if that is long gone), as long as the old one was.
        final oldTill = parseDayKey(p.till);
        final t = today();
        var from = oldTill.add(const Duration(days: 1));
        if (from.isBefore(t)) from = t;
        final len = p.from == null
            ? null
            : daysBetween(parseDayKey(p.from!), oldTill);
        final till = len == null || len < 1
            ? DateTime(from.year + 1, from.month, from.day - 1)
            : from.add(Duration(days: len));
        _from.text = fmtDmy(from);
        _till.text = fmtDmy(till);
        _dirty = true;
      } else {
        _from.text = p.from == null ? '' : fmtDmy(parseDayKey(p.from!));
        _till.text = fmtDmy(parseDayKey(p.till));
      }
    }
    for (final (c, n) in [(_from, _fromNode), (_till, _tillNode)]) {
      n.addListener(() {
        if (n.hasFocus) {
          c.selection = TextSelection(
            baseOffset: 0,
            extentOffset: c.text.length,
          );
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_isNew ? _typeNode : (widget.renew ? _tillNode : _fromNode))
          .requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in [_type, _from, _till]) {
      c.dispose();
    }
    for (final n in [_typeNode, _fromNode, _tillNode]) {
      n.dispose();
    }
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  List<_TypeChoice> _typeOptions(String text) {
    final t = text.trim().toLowerCase();
    final all = store.paperTypes;
    if (t.isEmpty || all.any((x) => x.toLowerCase() == t)) {
      return [
        for (final x in all)
          if (t.isNotEmpty && x.toLowerCase() == t) _TypeChoice(x),
        for (final x in all)
          if (x.toLowerCase() != t) _TypeChoice(x),
      ];
    }
    return [
      for (final x in all)
        if (x.toLowerCase().startsWith(t)) _TypeChoice(x),
      for (final x in all)
        if (!x.toLowerCase().startsWith(t) && x.toLowerCase().contains(t))
          _TypeChoice(x),
      _TypeChoice(text.trim(), isNew: true),
    ];
  }

  DateTime? _date(TextEditingController c) =>
      parseTypedDate(c.text, allowFuture: true);

  Future<void> _pick(TextEditingController c, String title) async {
    final d = await pickDay(
      context,
      selected: _date(c) ?? today(),
      hasData: (_) => false,
      first: DateTime(2000),
      last: DateTime(2100),
      title: title,
    );
    if (d == null) return;
    setState(() {
      c.text = fmtDmy(d);
      _dirty = true;
    });
  }

  /// Checks the boxes; null when something is wrong (and says what).
  VehiclePaper? _check() {
    final type = _type.text.trim();
    if (type.isEmpty) {
      toast(context, 'Choose or type the paper (PUC, Insurance ...)');
      _typeNode.requestFocus();
      return null;
    }
    final till = _date(_till);
    if (till == null) {
      toast(context, 'Type the last valid date, like 30-10-2027');
      _tillNode.requestFocus();
      return null;
    }
    DateTime? from;
    if (_from.text.trim().isNotEmpty) {
      from = _date(_from);
      if (from == null) {
        toast(
          context,
          'Type the from date like 01-11-2026 (or leave it empty)',
        );
        _fromNode.requestFocus();
        return null;
      }
      if (from.isAfter(till)) {
        toast(context, 'The from date is after the till date.');
        _fromNode.requestFocus();
        return null;
      }
    }
    final same = _v.papers.where(
      (x) => x.id != _p?.id && x.type.toLowerCase() == type.toLowerCase(),
    );
    if (same.isNotEmpty) {
      toast(context, '${_v.number} already has $type. Use Renewed on it (R).');
      return null;
    }
    return VehiclePaper(
      id: _p?.id ?? newId(),
      type: type,
      from: from == null ? null : dayKey(from),
      till: dayKey(till),
    );
  }

  /// Last box: "Save?" (Enter = yes, Esc = no).
  Future<void> _ask() async {
    final p = _check();
    if (p == null) return;
    final ok = await confirm(
      context,
      title: widget.renew ? 'Save the renewed ${p.type}?' : 'Save ${p.type}?',
      message:
          '${_v.number}\n${p.type}: ${paperDates(p)}\n\n'
          '${p.daysLeft() <= kPaperAlertDays ? paperAlertText(p.daysLeft()) : 'Reminder from ${fmtLong(parseDayKey(p.till).subtract(const Duration(days: kPaperAlertDays)))}'}',
      yes: 'Yes, save',
    );
    if (ok) {
      await _save(p);
    } else {
      _tillNode.requestFocus();
    }
  }

  Future<void> _save([VehiclePaper? ready]) async {
    final p = ready ?? _check();
    if (p == null) return;
    // Renewing replaces the dates: nothing of the old period is kept.
    final i = _v.papers.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      _v.papers[i] = p;
    } else {
      _v.papers.add(p);
    }
    await store.saveVehicle(_v);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final till = _date(_till);
    final preview = till == null
        ? null
        : VehiclePaper(id: '', type: '', till: dayKey(till));
    final title = _isNew
        ? 'Add paper'
        : (widget.renew ? 'Renewed: ${_p!.type}' : 'Change ${_p!.type}');
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
          appBar: AppBar(title: Text('$title  ·  ${_v.number}')),
          body: PageWidth(
            max: 620,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if (widget.renew)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.fullBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Write the dates of the NEW ${_p!.type}. They replace the old ones '
                      '(${paperDates(_p!)}), and the reminder starts again '
                      '$kPaperAlertDays days before the new last day.',
                      style: const TextStyle(fontSize: 14.5),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('Paper'),
                        if (widget.renew)
                          Text(
                            _p!.type,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        else
                          PickField<_TypeChoice>(
                            controller: _type,
                            focusNode: _typeNode,
                            options: _typeOptions,
                            onPicked: (o) {
                              _type.text = o.name;
                              _touch();
                              _fromNode.requestFocus();
                            },
                            label: (o) => o.label,
                            special: (o) => o.isNew,
                            title: 'Papers',
                            listWidth: 320,
                            field: (context, submit) => TextField(
                              key: const Key('paperType'),
                              controller: _type,
                              focusNode: _typeNode,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _touch(),
                              onSubmitted: (_) => submit(),
                              onEditingComplete: () {},
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'PUC, Insurance, Fitness ...',
                                suffixIcon: Icon(Icons.arrow_drop_down),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        _label('Valid from  (can be left empty)'),
                        _dateField(
                          _from,
                          _fromNode,
                          const Key('paperFrom'),
                          'Valid from',
                          onEnter: () {
                            if (_from.text.trim().isNotEmpty &&
                                _date(_from) == null) {
                              toast(context, 'Type the date like 01-11-2026');
                              return;
                            }
                            _tillNode.requestFocus();
                          },
                        ),
                        const SizedBox(height: 14),
                        _label('Valid till  (last valid day)'),
                        _dateField(
                          _till,
                          _tillNode,
                          const Key('paperTill'),
                          'Valid till',
                          onEnter: _ask,
                        ),
                        if (preview != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PaperStatus(preview, big: true),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reminder on the Dashboard from '
                            '${fmtLong(till!.subtract(const Duration(days: kPaperAlertDays)))}, every day until renewed.',
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                    max: 620,
                    child: FilledButton.icon(
                      key: const Key('savePaper'),
                      onPressed: _ask,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text('Save', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
                if (wide)
                  const KeyHints([
                    ('Enter', 'Next box'),
                    ('Date', 'dd-mm-yyyy'),
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

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.muted,
      ),
    ),
  );

  Widget _dateField(
    TextEditingController c,
    FocusNode n,
    Key key,
    String title, {
    required VoidCallback onEnter,
  }) => TextField(
    key: key,
    controller: c,
    focusNode: n,
    keyboardType: TextInputType.datetime,
    textInputAction: TextInputAction.next,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-./ ]'))],
    onChanged: (_) => _touch(),
    onSubmitted: (_) {
      if (!onTopPage(context)) {
        reclaimDialogFocus();
        return;
      }
      onEnter();
    },
    onEditingComplete: () {},
    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
    decoration: InputDecoration(
      isDense: true,
      hintText: 'dd-mm-yyyy',
      suffixIcon: ExcludeFocus(
        child: IconButton(
          tooltip: 'Calendar',
          onPressed: () => _pick(c, title),
          icon: const Icon(Icons.calendar_month),
        ),
      ),
    ),
  );
}
