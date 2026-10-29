import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/ledger.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'entry_page.dart';
import 'gas_lines.dart';
import 'keys.dart';
import 'loan_text.dart';
import 'share.dart';
import 'stock_guard.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Period { all, thisMonth, lastMonth, custom }

/// One company: cylinders with them now, and every supply / empty return
/// with the balance after it.
class CompanyPage extends StatefulWidget {
  final AppStore store;
  final String companyId;
  const CompanyPage({super.key, required this.store, required this.companyId});

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  _Period _period = _Period.all;
  DateTime? _from;
  DateTime? _to;

  AppStore get store => widget.store;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setPeriod(_Period p) => setState(() => _period = p);

  (String?, String?) get _range {
    final now = today();
    return switch (_period) {
      _Period.all => (null, null),
      _Period.thisMonth => (dayKey(DateTime(now.year, now.month, 1)), null),
      _Period.lastMonth => (
        dayKey(DateTime(now.year, now.month - 1, 1)),
        dayKey(DateTime(now.year, now.month, 0)),
      ),
      _Period.custom => (
        _from == null ? null : dayKey(_from!),
        _to == null ? null : dayKey(_to!),
      ),
    };
  }

  Future<void> _pickCustom() async {
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
    if (to == null) return;
    if (to.isBefore(from)) {
      if (mounted) toast(context, 'The "to" date is before the "from" date.');
      return;
    }
    setState(() {
      _period = _Period.custom;
      _from = from;
      _to = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.company(widget.companyId);
        if (c == null) {
          return const Scaffold(body: Center(child: Text('Company not found')));
        }
        final (from, to) = _range;
        final led = store.ledger(c.id, from: from, to: to);
        final now = store.ledger(c.id);
        final loanNow = store.loanWithCompany(c.id, dayKey(today()));
        void editStart() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StartingBalancePage(store: store, company: c),
          ),
        );
        return KeyScroll(
          controller: _scroll,
          child: KeyPage(
            autofocus: true,
            letters: {
              'e': editStart,
              'p': () => sendCompanyStatement(
                context,
                store,
                c.id,
                from: from,
                to: to,
              ),
              'a': () => _setPeriod(_Period.all),
              'm': () => _setPeriod(_Period.thisMonth),
              'l': () => _setPeriod(_Period.lastMonth),
              'd': _pickCustom,
            },
            child: Scaffold(
              bottomNavigationBar: isWide(context)
                  ? const KeyHints([
                      ('↑ ↓', 'Scroll'),
                      ('A', 'All'),
                      ('M', 'This month'),
                      ('L', 'Last month'),
                      ('D', 'Choose dates'),
                      ('E', 'Change starting stock'),
                      ('P', 'PDF'),
                      ('Esc', 'Back'),
                    ])
                  : null,
              appBar: AppBar(
                title: Text(c.name, overflow: TextOverflow.ellipsis),
                actions: [
                  TextButton.icon(
                    key: const Key('companyPdf'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => sendCompanyStatement(
                      context,
                      store,
                      c.id,
                      from: from,
                      to: to,
                    ),
                    icon: Icon(shareIcon),
                    label: const Text(
                      'PDF',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              body: PageWidth(
                max: 820,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  children: [
                    Card(
                      color: AppColors.emptyBg,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CYLINDER STOCK AT THIS COMPANY NOW',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              plural(now.totalEnd, 'cylinder', 'cylinders'),
                              key: const Key('companyTotal'),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _Balance(now.end, big: true),
                            const SizedBox(height: 6),
                            const Text(
                              'Supplied cylinders are added, empty cylinders received are taken off.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                            if (loanNow.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                key: const Key('companyLoan'),
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.loanBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.loan.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'LOAN CYLINDERS WITH THEM (get them back for the plant)',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        color: AppColors.loan,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      loanText(store, loanNow, sep: ',   '),
                                      key: const Key('companyLoanText'),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.loan,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const Divider(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Starting stock (before the app)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _Balance(c.opening),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  key: const Key('editOpeningBalance'),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StartingBalancePage(
                                        store: store,
                                        company: c,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Change (E)'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('All (A)', _Period.all),
                        _chip('This month (M)', _Period.thisMonth),
                        _chip('Last month (L)', _Period.lastMonth),
                        ChoiceChip(
                          label: Text(
                            _period == _Period.custom && _from != null
                                ? '${fmtShort(_from!)} - ${fmtShort(_to!)}  (D)'
                                : 'Choose dates (D)',
                          ),
                          selected: _period == _Period.custom,
                          onSelected: (_) => _pickCustom(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (led.lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No supply or empty received in this period.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    // Newest first on the phone.
                    for (final l in led.lines.reversed) ...[
                      _LineCard(
                        line: l,
                        loanFull: loanText(store, l.entry.loanFull),
                        loanEmpty: loanText(store, l.entry.loanEmpty),
                        remarks: remarksText(l.entry.remarks, store: store),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EntryPage(
                              store: store,
                              date: l.date,
                              entryId: l.entry.id,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            from == null
                                ? 'Starting stock'
                                : 'Stock on ${fmtShort(parseDayKey(from))} (start)',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _Balance(led.start),
                        ],
                      ),
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

  Widget _chip(String label, _Period p) => ChoiceChip(
    label: Text(label),
    selected: _period == p,
    onSelected: (_) => setState(() => _period = p),
  );
}

class _Balance extends StatelessWidget {
  final Map<String, int> balance;
  final bool big;
  const _Balance(this.balance, {this.big = false});

  @override
  Widget build(BuildContext context) {
    final items = orderedQty(balance);
    if (items.isEmpty) {
      return Text(
        'None',
        style: TextStyle(fontSize: big ? 18 : 15, color: AppColors.muted),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in items)
          QtyChip(
            label: gasLabel(e.key),
            qty: e.value,
            color: e.value < 0 ? AppColors.danger : AppColors.navy,
          ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  final LedgerLine line;
  final VoidCallback onTap;

  /// Loan cylinders in the entry, as text ("-" when none).
  final String loanFull;
  final String loanEmpty;

  /// Line remarks as text ("" when none).
  final String remarks;
  const _LineCard({
    required this.line,
    required this.onTap,
    this.loanFull = '-',
    this.loanEmpty = '-',
    this.remarks = '',
  });

  @override
  Widget build(BuildContext context) {
    final e = line.entry;
    final full = orderedQty(e.full);
    final empty = orderedQty(e.empty);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BillMark(billed: e.billed, needed: e.needsBill, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fmtLong(parseDayKey(line.date)),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'Challan ${e.challan.isEmpty ? '-' : e.challan}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (full.isNotEmpty)
                _row('Supplied', AppColors.full, [
                  for (final x in full)
                    QtyChip(
                      label: gasLabel(x.key),
                      qty: x.value,
                      color: AppColors.full,
                    ),
                ]),
              if (empty.isNotEmpty) ...[
                const SizedBox(height: 6),
                _row('Empty back', AppColors.empty, [
                  for (final x in empty)
                    QtyChip(
                      label: gasLabel(x.key),
                      qty: x.value,
                      color: AppColors.empty,
                    ),
                ]),
              ],
              for (final (label, text) in [
                ('Loan supplied', loanFull),
                ('Loan empty back', loanEmpty),
              ])
                if (text != '-') ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.loan,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.loan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              if (remarks.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Remarks:  $remarks',
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ],
              if (e.cash.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  e.cash
                      .map(
                        (c) =>
                            '${c.type} ${fmtMoney(c.amount)} (${modeLabel(c.mode)})',
                      )
                      .join('   '),
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const Divider(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 84,
                    child: Text(
                      'Stock after',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ),
                  Expanded(child: _Balance(line.after)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, Color color, List<Widget> chips) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 84,
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
      Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
    ],
  );
}

/// Cylinders a company already had before the app was used.
class StartingBalancePage extends StatefulWidget {
  final AppStore store;
  final NamedItem company;
  const StartingBalancePage({
    super.key,
    required this.store,
    required this.company,
  });

  @override
  State<StartingBalancePage> createState() => _StartingBalancePageState();
}

/// Same way of typing as an entry: type the gas, Enter, type how many,
/// Enter. Only the gases this company has are listed, so a number can
/// never go into the wrong gas's row.
class _StartingBalancePageState extends State<StartingBalancePage> {
  late final GasLines _lines = GasLines(1, {
    for (final e in widget.company.opening.entries) e.key: [e.value],
  });
  final _linesKey = GlobalKey<GasLinesEditorState>();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The empty line for a new gas (↑ goes to the saved ones), so typing
      // a gas name never replaces a saved line by mistake.
      if (mounted) _linesKey.currentState?.focusLast();
    });
  }

  @override
  void dispose() {
    _lines.dispose();
    super.dispose();
  }

  Map<String, int> get _opening => _lines.column(0);

  /// End of List: show what will be saved, then Enter = yes, Esc = no.
  Future<void> _ask() async {
    final o = orderedQty(_opening);
    final total = o.fold(0, (a, e) => a + e.value);
    final ok = await confirm(
      context,
      title: 'Save starting stock?',
      message:
          '${widget.company.name}:\n'
          '${o.isEmpty ? 'No cylinders' : o.map((e) => '${gasLabel(e.key)}  ${e.value}').join('\n')}'
          '\n\nTotal: $total cylinders',
      yes: 'Yes, save',
    );
    if (ok) {
      await _save();
    } else {
      _linesKey.currentState?.focusLast();
    }
  }

  Future<void> _save() async {
    final opening = _opening;
    final problems = widget.store.problemsIfOpening(widget.company.id, opening);
    if (problems.isNotEmpty) {
      await showStockProblems(context, problems, sameDay: true);
      return;
    }
    await widget.store.setCompanyOpening(widget.company, opening);
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
            title: Text('Starting Stock  ·  ${widget.company.name}'),
          ),
          body: PageWidth(
            max: 640,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                Text(
                  widget.company.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cylinders this company already had with them before you '
                  'started using the app. Type the gas name, press Enter, type '
                  'how many, press Enter. Press Enter on an empty line to finish.',
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                GasLinesEditor(
                  key: _linesKey,
                  lines: _lines,
                  titles: const ['Cylinders'],
                  colors: const [AppColors.navy],
                  onChanged: () => setState(() => _dirty = true),
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
                    max: 640,
                    child: FilledButton.icon(
                      key: const Key('saveStartingBalance'),
                      onPressed: _ask,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save Starting Stock',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
                if (isWide(context))
                  const KeyHints([
                    ('Enter', 'Next box'),
                    ('Enter on empty gas', 'Finish & save'),
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
