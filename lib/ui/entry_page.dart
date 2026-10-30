import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../models/purchase_order.dart';
import '../util/dates.dart';
import 'gas_lines.dart';
import 'keys.dart';
import 'loan_text.dart';
import 'pick_field.dart';
import 'po_field.dart';
import 'stock_guard.dart';
import 'theme.dart';
import 'widgets.dart';

/// Add or edit one row of the day's register, Tally voucher style:
/// Company → Challan No. → Bill (Y/N, only when full is supplied) → gas
/// lines (gas, full, empty) → Enter on an empty gas = End of List → cash
/// lines (type, amount, Cash/GPay) → Enter on an empty cash type →
/// "Save? Yes / No". Up arrow or Backspace in an empty box goes back.
/// While loan cylinders (borrowed from a plant) are out, a "Loan cylinders"
/// list comes after the gas lines: loan full supplied / loan empty back,
/// kept apart from our own cylinders.
/// A company with purchase orders (Settings > Companies) gets a "PO No."
/// box after Bill: each gas supplied counts against that PO when it has
/// the gas, else against the company's PO for that gas.
class EntryPage extends StatefulWidget {
  final AppStore store;
  final String date;
  final String? entryId;

  /// Open with the cursor in Challan No. (from the dashboard alert).
  final bool focusChallan;

  const EntryPage({
    super.key,
    required this.store,
    required this.date,
    this.entryId,
    this.focusChallan = false,
  });

  @override
  State<EntryPage> createState() => _EntryPageState();
}

/// A company in the pop-up list, or "create new", or the hint row.
class _CompanyChoice {
  final NamedItem? item;
  final String? newName;
  const _CompanyChoice({this.item, this.newName});
  static const hint = _CompanyChoice();
  bool get isHint => item == null && newName == null;
  String get label =>
      item?.name ?? (newName != null ? 'Create new company: "$newName"' : '');
}

class _CashLine {
  String? type;
  final TextEditingController amount;
  String mode;
  final FocusNode typeNode = FocusNode(debugLabel: 'cashType');
  final FocusNode amountNode = FocusNode(debugLabel: 'cashAmount');
  final FocusNode modeNode = FocusNode(debugLabel: 'cashMode');
  _CashLine({this.type, String amount = '', this.mode = kModeCash})
    : amount = TextEditingController(text: amount) {
    markField(modeNode);
  }

  void dispose() {
    amount.dispose();
    typeNode.dispose();
    amountNode.dispose();
    modeNode.dispose();
  }
}

class _EntryPageState extends State<EntryPage> {
  AppStore get store => widget.store;

  String? _entryId;
  String? _companyId;
  String _company = '';
  int _sort = 0;
  int _srNo = 0;
  final _companyText = TextEditingController();
  final _companyNode = FocusNode(debugLabel: 'company');
  final _challan = TextEditingController();
  final _challanNode = FocusNode(debugLabel: 'challan');
  bool _billed = false;
  final _billNode = FocusNode(debugLabel: 'bill');

  /// The PO chosen (PO id, or kNoPo); null while the company has none.
  String? _po;

  /// The PO box was changed (else a saved entry keeps its PO links).
  bool _poTouched = false;
  Map<String, String> _oldPo = const {};
  Map<String, String> _oldPoNo = const {};
  final _poNode = FocusNode(debugLabel: 'po');
  late final GasLines _lines;
  final _linesKey = GlobalKey<GasLinesEditorState>();

  /// Loan cylinders in this entry; null when there are none out at all.
  GasLines? _loan;
  final _loanKey = GlobalKey<GasLinesEditorState>();
  final List<_CashLine> _cash = [];
  bool _dirty = false;
  String? _saved;

  bool get _isNew => _entryId == null;

  @override
  void initState() {
    super.initState();
    _entryId = widget.entryId;
    final day = store.day(widget.date);
    Entry? e;
    if (_entryId != null) {
      final i = day.entries.indexWhere((x) => x.id == _entryId);
      if (i >= 0) {
        e = day.entries[i];
        _srNo = i + 1;
      }
    } else {
      _srNo = day.entries.length + 1;
    }
    _lines = GasLines(2, {
      for (final g in kGases)
        if ((e?.full[g.code] ?? 0) != 0 || (e?.empty[g.code] ?? 0) != 0)
          g.code: [e!.full[g.code] ?? 0, e.empty[g.code] ?? 0],
    });
    _loan = _loanLines(e);
    if (e != null) {
      _lines.setRemarks(e.remarks);
      _loan?.setRemarks(e.remarks);
    }
    markField(_billNode);
    if (e != null) {
      _companyId = e.companyId;
      _company = e.company;
      _companyText.text = e.company;
      _sort = e.sort;
      _challan.text = e.challan;
      _billed = e.billed;
      _oldPo = e.po;
      _oldPoNo = e.poNo;
      _po = _savedPo(e);
      for (final c in e.cash) {
        _cash.add(
          _CashLine(
            type: c.type,
            amount: fmtAmountPlain(c.amount),
            mode: c.mode,
          ),
        );
      }
    }
    _cashBlank();
    _companyNode.addListener(_companyFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (widget.focusChallan ? _challanNode : _companyNode).requestFocus();
    });
  }

  @override
  void dispose() {
    _companyText.dispose();
    _companyNode.dispose();
    _challan.dispose();
    _challanNode.dispose();
    _billNode.dispose();
    _poNode.dispose();
    _lines.dispose();
    _loan?.dispose();
    for (final c in _cash) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch() => setState(() {
    _dirty = true;
    _saved = null;
  });

  void _focus(FocusNode n) => focusSoon(n);

  // ------------------------------------------------------------- company

  void _companyFocus() {
    if (_companyNode.hasFocus) {
      _companyText.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _companyText.text.length,
      );
    } else if (_companyText.text != _company) {
      _companyText.text = _company;
    }
  }

  List<_CompanyChoice> _companyOptions(String text) {
    final all = store.activeCompanies;
    final t = text.trim().toLowerCase();
    if (t.isEmpty || text == _company) {
      final current = all.where((c) => c.id == _companyId);
      return [
        if (current.isEmpty) _CompanyChoice.hint,
        ...current.map((c) => _CompanyChoice(item: c)),
        for (final c in all)
          if (c.id != _companyId) _CompanyChoice(item: c),
      ];
    }
    final starts = <NamedItem>[], has = <NamedItem>[];
    for (final c in all) {
      final n = c.name.toLowerCase();
      if (n.startsWith(t)) {
        starts.add(c);
      } else if (n.contains(t)) {
        has.add(c);
      }
    }
    final exact = all.any((c) => c.name.toLowerCase() == t);
    return [
      ...[...starts, ...has].map((c) => _CompanyChoice(item: c)),
      if (!exact) _CompanyChoice(newName: text.trim()),
    ];
  }

  /// A "create new company?" question is open: a second Enter must not
  /// ask again.
  bool _askingCompany = false;

  Future<void> _companyPicked(_CompanyChoice o) async {
    if (_askingCompany) return;
    if (o.isHint) {
      _companyText.text = _company;
      return;
    }
    NamedItem? item = o.item;
    if (item == null) {
      _askingCompany = true;
      final ok = await confirm(
        context,
        title: 'New company?',
        message: 'Create a new company named "${o.newName}"?',
        yes: 'Yes, create',
      );
      _askingCompany = false;
      if (!mounted) return;
      if (!ok) {
        _companyText.text = _company;
        _focus(_companyNode);
        return;
      }
      // The cursor moves on at once, so nothing typed meanwhile is lost.
      _focus(_challanNode);
      item = await store.addCompany(o.newName!);
      if (!mounted) return;
    }
    final changed = item.id != _companyId;
    setState(() {
      _companyId = item!.id;
      _company = item.name;
      _companyText.text = item.name;
      if (changed) {
        _po = store.defaultPo(item.id);
        _poTouched = !_isNew;
      }
    });
    _touch();
    _focus(_challanNode);
  }

  // ----------------------------------------------------- purchase order

  /// The PO in the box (a new entry starts with the company's current one).
  String get _poNow =>
      _po ?? (_isNew ? (store.defaultPo(_companyId) ?? kNoPo) : kNoPo);

  /// The company has purchase orders: the PO box is shown.
  bool get _showPo => store.hasPos(_companyId);

  /// A saved entry's PO: the one its first gas went to (if still there),
  /// "No PO" when it was saved without one.
  String? _savedPo(Entry e) {
    for (final g in kGases) {
      final id = e.po[g.code];
      if (id != null && store.po(id) != null) return id;
    }
    return store.hasPos(e.companyId) ? kNoPo : null;
  }

  /// Gases with full cylinders in this entry (own + loan).
  Map<String, int> get _fullAll {
    final m = Map.of(_full);
    _loanFull.forEach((gas, byPlant) {
      for (final v in byPlant.values) {
        m[gas] = (m[gas] ?? 0) + v;
      }
    });
    m.removeWhere((_, v) => v == 0);
    return m;
  }

  /// Which PO each gas goes to. A saved entry whose PO box was not
  /// changed keeps what it had.
  Map<String, String> _poLinks() {
    final gases = [
      for (final g in kGases)
        if (_fullAll.containsKey(g.code)) g.code,
    ];
    final auto = store.poLinksFor(
      _companyId,
      gases,
      chosen: _poNow,
      exceptEntry: _entryId,
    );
    if (_isNew || _poTouched) return auto;
    return {
      for (final g in gases)
        if (_oldPo[g] != null)
          g: _oldPo[g]!
        else if (auto[g] != null)
          g: auto[g]!,
    };
  }

  Map<String, String> _poNumbers(Map<String, String> links) => {
    for (final e in links.entries)
      e.key: store.po(e.value)?.number ?? _oldPoNo[e.key] ?? '',
  };

  /// "Oxygen → PO 4500123 (52 left after this)" for each gas.
  /// (gas, its PO and what is left, true when nothing is left).
  List<(String, String, bool)> _poPlan() {
    final links = _poLinks(), full = _fullAll;
    final out = <(String, String, bool)>[];
    for (final g in kGases) {
      final qty = full[g.code];
      if (qty == null) continue;
      final id = links[g.code];
      final p = id == null ? null : store.po(id);
      if (p == null) {
        final no = id == null ? '' : (_oldPoNo[g.code] ?? '');
        out.add((g.label, no.isEmpty ? 'no PO' : 'PO $no', false));
        continue;
      }
      final left = store.poLine(p, g.code, exceptEntry: _entryId).left - qty;
      out.add((
        g.label,
        'PO ${p.number}  (${poLeftText(left)}${left > 0 ? ' after this' : ''})',
        left <= 0,
      ));
    }
    return out;
  }

  String get _poSummary {
    final plan = _poPlan();
    if (plan.isEmpty) return '';
    return plan.map((x) => '${x.$1} → ${x.$2}').join(',  ');
  }

  void _afterBill() {
    if (_showPo) {
      _focus(_poNode);
    } else {
      _linesKey.currentState?.focusFirst();
    }
  }

  // ---------------------------------------------------------------- loan

  /// The loan choices ("ARGON · ABC Plant") that are out on this date, and
  /// the entry's own loan lines. Null when there is nothing on loan.
  GasLines? _loanLines(Entry? e) {
    final codes = <String>{};
    final pool = <Gas>[];
    void add(String gas, String plant) {
      if (codes.add(loanCode(gas, plant))) {
        pool.add(loanChoice(store, gas, plant));
      }
    }

    for (final (gas, l) in store.loanLinesOn(widget.date)) {
      if (l.toReturn != 0 || l.moved) add(gas.code, l.plantId);
    }
    for (final m in [e?.loanFull, e?.loanEmpty]) {
      m?.forEach((gas, byPlant) {
        for (final p in byPlant.keys) {
          add(gas, p);
        }
      });
    }
    if (pool.isEmpty) return null;
    // Plant by plant, gases in the usual order.
    final order = {for (var i = 0; i < kGases.length; i++) kGases[i].code: i};
    pool.sort((a, b) {
      final (ga, pa) = loanSplit(a.code);
      final (gb, pb) = loanSplit(b.code);
      final n = store
          .plantName(pa)
          .toLowerCase()
          .compareTo(store.plantName(pb).toLowerCase());
      return n != 0 ? n : (order[ga] ?? 0).compareTo(order[gb] ?? 0);
    });
    final full = loanCodes(e?.loanFull ?? const {});
    final empty = loanCodes(e?.loanEmpty ?? const {});
    return GasLines(2, {
      for (final c in {...full.keys, ...empty.keys})
        c: [full[c] ?? 0, empty[c] ?? 0],
    }, pool);
  }

  /// Remarks of every line: our gases by gas code, loan lines by their code.
  Map<String, String> get _remarks => {
    ..._lines.remarks(),
    ...?_loan?.remarks(),
  };

  PlantQty get _loanFull =>
      _loan == null ? {} : loanFromCodes(_loan!.column(0));
  PlantQty get _loanEmpty =>
      _loan == null ? {} : loanFromCodes(_loan!.column(1));

  /// End of our gas lines: on to the loan list (when shown), else cash.
  void _afterGas() {
    if (_loan != null) {
      _loanKey.currentState?.focusFirst();
    } else {
      _toCash();
    }
  }

  // ---------------------------------------------------------------- cash

  /// Like the gas lines, there is always one empty cash line at the end.
  void _cashBlank() {
    if (_cash.isEmpty || _cash.last.type != null) {
      _cash.add(_CashLine());
    }
  }

  /// To the empty cash line (after the gas lines, or C in the Save box).
  void _toCash() {
    setState(_cashBlank);
    _focus(_cash.last.typeNode);
  }

  void _removeCash(int i) {
    final gone = _cash[i];
    setState(() {
      _cash.removeAt(i);
      _cashBlank();
    });
    // Its boxes may still be on screen until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
    _touch();
    // After the screen is rebuilt (see GasLinesEditor._remove).
    final next = _cash[i < _cash.length ? i : _cash.length - 1].typeNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && next.context != null) next.requestFocus();
    });
  }

  // ---------------------------------------------------------------- save

  Map<String, int> get _full => _lines.column(0);

  /// The bill question is only for full cylinders supplied: hidden once the
  /// lines show only empties received.
  bool get _askBill =>
      _full.isNotEmpty ||
      _loanFull.isNotEmpty ||
      !([
        ..._lines.lines,
        ...?_loan?.lines,
      ].any((l) => l.gas != null && l.hasNumbers));
  Map<String, int> get _empty => _lines.column(1);

  List<CashItem>? _cashItems() {
    final out = <CashItem>[];
    for (final l in _cash) {
      final amt = parseAmount(l.amount.text);
      if (l.type == null && (amt == null || amt == 0)) continue;
      if (l.type == null) {
        toast(context, 'Choose the cash type (Deposit / Payment ...)');
        _focus(l.typeNode);
        return null;
      }
      if (amt == null || amt <= 0) {
        toast(context, 'Enter the cash amount for ${l.type}');
        _focus(l.amountNode);
        return null;
      }
      out.add(CashItem(type: l.type!, amount: amt, mode: l.mode));
    }
    return out;
  }

  bool _check(List<CashItem>? cash) {
    if (cash == null) return false;
    if (_company.isEmpty) {
      toast(context, 'Please choose the company first');
      _focus(_companyNode);
      return false;
    }
    if (_full.isEmpty &&
        _empty.isEmpty &&
        _loanFull.isEmpty &&
        _loanEmpty.isEmpty &&
        cash.isEmpty) {
      toast(context, 'Type at least one gas and its number');
      _linesKey.currentState?.focusFirst();
      return false;
    }
    return true;
  }

  /// End of List: ask "Save this entry?" (Enter = yes, Esc = no,
  /// C = add cash).
  Future<void> _finish() async {
    final cash = _cashItems();
    if (!_check(cash)) return;
    final old = !sameDay(parseDayKey(widget.date), today());
    final r = await askChoice(
      context,
      title: _isNew ? 'Save this entry?' : 'Save the changes?',
      yes: 'Yes, save',
      more: {
        'c': _cash.any((l) => l.type != null) ? 'Add more cash' : 'Add cash',
      },
      extra: _Summary(
        company: _company,
        challan: _challan.text.trim(),
        billed: _billed,
        needsBill: _full.isNotEmpty || _loanFull.isNotEmpty,
        full: _full,
        empty: _empty,
        loanFull: loanText(store, _loanFull),
        loanEmpty: loanText(store, _loanEmpty),
        remarks: remarksText(_remarks),
        po: _showPo || _oldPo.isNotEmpty ? _poSummary : '',
        cash: cash!,
        oldDate: old ? widget.date : null,
      ),
    );
    if (!mounted) return;
    switch (r) {
      case 'yes':
        await _save(cash);
      default:
        // No (Esc) or C: back to the cash line, the last box before saving.
        _toCash();
    }
  }

  Future<void> _save([List<CashItem>? ready]) async {
    final cash = ready ?? _cashItems();
    if (!_check(cash)) return;
    final day = store.day(widget.date);
    final links = _poLinks();
    final entry = Entry(
      id: _entryId ?? newId(),
      sort: _sort != 0 ? _sort : store.nextSort(),
      companyId: _companyId,
      company: _company,
      challan: _challan.text.trim(),
      // Only empties received: no bill to make.
      billed: (_full.isNotEmpty || _loanFull.isNotEmpty) && _billed,
      full: _full,
      empty: _empty,
      cash: cash!,
      loanFull: _loanFull,
      loanEmpty: _loanEmpty,
      remarks: _remarks,
      po: links,
      poNo: _poNumbers(links),
    );
    final i = day.entries.indexWhere((x) => x.id == entry.id);
    if (i >= 0) {
      day.entries[i] = entry;
    } else {
      day.entries.add(entry);
    }
    if (!await stockAllowsSave(context, store, day)) return;
    await store.saveDay(day);
    if (!mounted) return;
    if (_isNew && isWide(context)) {
      // Like Tally: a fresh blank entry opens for the next company.
      final name = _company;
      final n = _srNo;
      // First the cursor goes to Company, so the gas / cash boxes let go of
      // it normally (their pop-up lists close). Their old boxes are thrown
      // away only after the screen has been redrawn without them.
      _companyNode.requestFocus();
      final oldCash = List.of(_cash);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in oldCash) {
          c.dispose();
        }
      });
      setState(() {
        _companyId = null;
        _company = '';
        _companyText.clear();
        _challan.clear();
        _billed = false;
        _sort = 0;
        _po = null;
        _poTouched = false;
        _oldPo = const {};
        _oldPoNo = const {};
        _lines.load(const {});
        _loan?.load(const {});
        _cash.clear();
        _cashBlank();
        _srNo = store.day(widget.date).entries.length + 1;
        _dirty = false;
        _saved =
            'Saved #$n  $name.  Write the next entry, or press Esc to go back.';
      });
      _focus(_companyNode);
      // Once more after the "Save?" box has fully closed, so the cursor is
      // surely in Company and typing goes there (like Tally).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_companyNode.hasFocus) _companyNode.requestFocus();
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    if (_isNew) return;
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message: '$_company will be removed from this day.',
      yes: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    final day = store.day(widget.date);
    day.entries.removeWhere((x) => x.id == _entryId);
    if (!await stockAllowsSave(context, store, day)) return;
    await store.saveDay(day);
    if (mounted) Navigator.pop(context);
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await confirm(
          context,
          title: 'Quit without saving?',
          message: 'What you typed in this entry will be lost.',
          yes: 'Quit',
        );
        if (leave) nav.pop();
      },
      child: KeyPage(
        onSave: _save,
        altLetters: {if (!_isNew) 'd': _delete},
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${_isNew ? 'New Entry' : 'Edit Entry'}  #$_srNo   ·   '
              '${fmtLong(parseDayKey(widget.date))}',
            ),
            actions: [
              if (!_isNew)
                IconButton(
                  key: const Key('deleteEntry'),
                  tooltip: 'Delete (Alt+D)',
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: PageWidth(
            max: 760,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                OldDateBanner(date: widget.date),
                // Always in the list (empty when nothing was just saved):
                // showing / hiding it must not shift the boxes below, or the
                // company box is rebuilt and loses the cursor.
                _SavedBanner(text: _saved),
                KeyedSubtree(
                  key: const ValueKey('entryHead'),
                  child: _headCard(wide),
                ),
                const SizedBox(height: 12),
                GasLinesEditor(
                  key: _linesKey,
                  lines: _lines,
                  titles: const ['Full supplied', 'Empty received'],
                  colors: const [AppColors.full, AppColors.empty],
                  onChanged: _touch,
                  showRemarks: true,
                  onEndOfList: _afterGas,
                ),
                if (_loan != null) ...[
                  const SizedBox(height: 12),
                  _loanHeading(),
                  GasLinesEditor(
                    key: _loanKey,
                    lines: _loan!,
                    titles: const ['Loan full supplied', 'Loan empty received'],
                    colors: const [AppColors.loan, AppColors.loan],
                    onChanged: _touch,
                    showRemarks: true,
                    onEndOfList: _toCash,
                  ),
                ],
                const SizedBox(height: 12),
                _cashCard(),
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
                    max: 760,
                    child: FilledButton.icon(
                      key: const Key('saveEntry'),
                      onPressed: _finish,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save Entry',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
                if (wide)
                  KeyHints([
                    ('Enter', 'Next box'),
                    ('↑ / Backspace', 'Previous box'),
                    ('Enter on empty gas', 'To cash'),
                    ('Enter on empty cash', 'Save'),
                    ('Esc', 'Back'),
                    ('Ctrl+A', 'Save now'),
                    if (!_isNew) ('Alt+D', 'Delete'),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loanHeading() => const Padding(
    padding: EdgeInsets.only(left: 4, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.swap_horiz, color: AppColors.loan, size: 22),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Loan cylinders  (borrowed from a plant)',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.loan,
                ),
              ),
            ),
          ],
        ),
        Text(
          'Only for the plant\'s own cylinders (they look different). Type the gas and '
          'pick its plant; empty line + Enter = on to cash.',
          style: TextStyle(fontSize: 13.5, color: AppColors.muted),
        ),
      ],
    ),
  );

  Widget _label(String text) => SizedBox(
    width: isWide(context) ? 130 : 100,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF39424F),
      ),
    ),
  );

  Widget _headCard(bool wide) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          FocusRow(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              children: [
                _label('Company'),
                Expanded(
                  child: PickField<_CompanyChoice>(
                    controller: _companyText,
                    focusNode: _companyNode,
                    options: _companyOptions,
                    onPicked: _companyPicked,
                    title: 'List of Companies',
                    listWidth: 420,
                    label: (o) => o.isHint
                        ? 'Type to search (${store.activeCompanies.length} companies)'
                        : o.label,
                    special: (o) => o.newName != null,
                    field: (context, submit) => TextField(
                      key: const Key('company'),
                      controller: _companyText,
                      focusNode: _companyNode,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _touch(),
                      onSubmitted: (_) => submit(),
                      onEditingComplete: () {},
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Type company name',
                        prefixIcon: Icon(Icons.business),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          FocusRow(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              children: [
                _label('Challan No.'),
                SizedBox(
                  width: wide ? 260 : 180,
                  child: TextField(
                    key: const Key('challan'),
                    controller: _challan,
                    focusNode: _challanNode,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _touch(),
                    onSubmitted: (_) {
                      if (!onTopPage(context)) {
                        reclaimDialogFocus();
                        return;
                      }
                      if (_askBill) {
                        _focus(_billNode);
                      } else {
                        _afterBill();
                      }
                    },
                    onEditingComplete: () {},
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Challan number',
                      prefixIcon: Icon(Icons.receipt_long),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_askBill)
            FocusRow(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                children: [
                  _label('Bill made?'),
                  Flexible(
                    child: _BillField(
                      key: const Key('bill'),
                      node: _billNode,
                      billed: _billed,
                      onChanged: (v) {
                        setState(() => _billed = v);
                        _touch();
                      },
                      onEnter: _afterBill,
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text(
                        'Y = Yes,  N = No',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_showPo) _poRow(wide),
        ],
      ),
    );
  }

  /// "PO No." and, under it, where each gas supplied goes.
  Widget _poRow(bool wide) {
    final plan = _poPlan();
    return FocusRow(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _label('PO No.'),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: wide ? 320 : double.infinity,
                    child: PoPickField(
                      store: store,
                      companyId: _companyId,
                      value: _poNow,
                      focusNode: _poNode,
                      exceptEntry: _entryId,
                      onPicked: (id) {
                        setState(() {
                          _po = id;
                          _poTouched = true;
                        });
                        _touch();
                        _linesKey.currentState?.focusFirst();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (plan.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: wide ? 130 : 0, top: 6),
              child: Wrap(
                spacing: 14,
                runSpacing: 2,
                children: [
                  for (final x in plan)
                    Text(
                      '${x.$1} → ${x.$2}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: x.$3 ? AppColors.danger : AppColors.navy,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cashCard() {
    final types = [...store.cashTypes];
    return Card(
      color: AppColors.amberBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.amberLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.amber,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: const Text(
              'CASH RECEIVED (if any)   type, amount, C = Cash / G = GPay.  '
              'Nothing? Press Enter to save.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (var i = 0; i < _cash.length; i++)
            FocusRow(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    child: _CashTypeField(
                      key: Key('cashType$i'),
                      line: _cash[i],
                      types: types,
                      onPicked: (t) async {
                        if (!types.contains(t)) await store.addCashType(t);
                        setState(() {
                          _cash[i].type = t;
                          _cashBlank();
                        });
                        _touch();
                        _focus(_cash[i].amountNode);
                      },
                      onEnd: _finish,
                      onClear: _cash[i].type == null
                          ? null
                          : () => _removeCash(i),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      key: Key('cashAmount$i'),
                      controller: _cash[i].amount,
                      focusNode: _cash[i].amountNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _touch(),
                      onSubmitted: (_) {
                        if (onTopPage(context)) {
                          _focus(_cash[i].modeNode);
                        } else {
                          reclaimDialogFocus();
                        }
                      },
                      onEditingComplete: () {},
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Amount',
                        prefixText: '₹ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ModeField(
                    key: Key('cashMode$i'),
                    node: _cash[i].modeNode,
                    mode: _cash[i].mode,
                    onChanged: (m) {
                      setState(() => _cash[i].mode = m);
                      _touch();
                    },
                    onEnter: () {
                      if (i + 1 >= _cash.length) setState(_cashBlank);
                      _focus(_cash[i + 1 < _cash.length ? i + 1 : i].typeNode);
                    },
                  ),
                  SizedBox(
                    width: 40,
                    child: _cash[i].type == null
                        ? null
                        : ExcludeFocus(
                            child: IconButton(
                              tooltip: 'Remove',
                              onPressed: () => _removeCash(i),
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.danger,
                                size: 20,
                              ),
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
}

/// "Saved #3 ..." after a save on the PC; nothing when [text] is null.
class _SavedBanner extends StatelessWidget {
  final String? text;
  const _SavedBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Container(
      key: const Key('savedBanner'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fullBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.full),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.full),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bill made? Y = yes, N = no, Space switches, Enter goes on.
class _BillField extends StatelessWidget {
  final FocusNode node;
  final bool billed;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEnter;
  const _BillField({
    super.key,
    required this.node,
    required this.billed,
    required this.onChanged,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    final color = billed ? AppColors.full : AppColors.danger;
    return Focus(
      focusNode: node,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.keyY) {
          onChanged(true);
        } else if (k == LogicalKeyboardKey.keyN) {
          onChanged(false);
        } else if (k == LogicalKeyboardKey.space) {
          onChanged(!billed);
        } else if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) {
          onEnter();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            key: const Key('billTick'),
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              node.requestFocus();
              onChanged(!billed);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused ? color : color.withValues(alpha: 0.4),
                  width: focused ? 2.5 : 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BillMark(billed: billed, size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      billed ? 'Yes - bill made' : 'No - bill later',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cash or GPay: C / G keys, Space switches, Enter goes on.
class _ModeField extends StatelessWidget {
  final FocusNode node;
  final String mode;
  final ValueChanged<String> onChanged;
  final VoidCallback onEnter;
  const _ModeField({
    super.key,
    required this.node,
    required this.mode,
    required this.onChanged,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: node,
      onKeyEvent: (n, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.keyC) {
          onChanged(kModeCash);
        } else if (k == LogicalKeyboardKey.keyG) {
          onChanged(kModeGpay);
        } else if (k == LogicalKeyboardKey.space) {
          onChanged(mode == kModeCash ? kModeGpay : kModeCash);
        } else if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) {
          onEnter();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              node.requestFocus();
              onChanged(mode == kModeCash ? kModeGpay : kModeCash);
            },
            child: Container(
              width: 96,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused ? AppColors.amber : AppColors.line,
                  width: focused ? 2.5 : 1,
                ),
              ),
              child: Text(
                modeLabel(mode),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.amber,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One choice in the cash type list. A new object every time the list is
/// made (the pop-up list ignores the same object picked twice in a row, so
/// a shared "End of List" would work only once).
class _CashChoice {
  final String? type;
  final String? newType;
  final bool end;
  final bool remove;
  _CashChoice.type(String this.type)
    : newType = null,
      end = false,
      remove = false;
  _CashChoice.newType(String this.newType)
    : type = null,
      end = false,
      remove = false;
  _CashChoice.endOfList()
    : type = null,
      newType = null,
      end = true,
      remove = false;
  _CashChoice.removeLine()
    : type = null,
      newType = null,
      end = false,
      remove = true;

  bool get special => type == null;
  String get label => end
      ? 'End of List (save)'
      : remove
      ? 'Remove this line'
      : newType != null
      ? 'New type: "$newType"'
      : type!;
}

/// Cash type box with a pop-up list (Deposit, Payment, ... or a new type).
class _CashTypeField extends StatefulWidget {
  final _CashLine line;
  final List<String> types;
  final ValueChanged<String> onPicked;
  final VoidCallback onEnd;

  /// Filled line: erasing the type offers "Remove this line".
  final VoidCallback? onClear;
  const _CashTypeField({
    super.key,
    required this.line,
    required this.types,
    required this.onPicked,
    required this.onEnd,
    this.onClear,
  });

  @override
  State<_CashTypeField> createState() => _CashTypeFieldState();
}

class _CashTypeFieldState extends State<_CashTypeField> {
  late final _c = TextEditingController(text: widget.line.type ?? '');

  @override
  void initState() {
    super.initState();
    widget.line.typeNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (widget.line.typeNode.hasFocus) {
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
      if (mounted) roomBelow(context);
    } else if (_c.text != (widget.line.type ?? '')) {
      // Left without choosing: show the chosen type again.
      _c.text = widget.line.type ?? '';
    }
  }

  @override
  void didUpdateWidget(_CashTypeField old) {
    super.didUpdateWidget(old);
    if (old.line != widget.line) {
      old.line.typeNode.removeListener(_onFocus);
      widget.line.typeNode.addListener(_onFocus);
      _c.text = widget.line.type ?? '';
    }
  }

  @override
  void dispose() {
    widget.line.typeNode.removeListener(_onFocus);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PickField<_CashChoice>(
      focusNode: widget.line.typeNode,
      controller: _c,
      title: 'Cash Types',
      label: (o) => o.label,
      special: (o) => o.special,
      options: (text) {
        final t = text.trim().toLowerCase();
        final all = [for (final x in widget.types) _CashChoice.type(x)];
        if (t.isEmpty && widget.onClear != null) {
          return [_CashChoice.removeLine(), ...all];
        }
        if (t.isEmpty || text == widget.line.type) {
          return [
            if (widget.line.type == null) _CashChoice.endOfList(),
            ...all,
          ];
        }
        final m = all.where((x) => x.type!.toLowerCase().contains(t)).toList();
        final exact = widget.types.any((x) => x.toLowerCase() == t);
        return [...m, if (!exact) _CashChoice.newType(text.trim())];
      },
      onPicked: (o) {
        if (o.remove) {
          _c.text = widget.line.type ?? '';
          widget.onClear?.call();
        } else if (o.end) {
          _c.text = '';
          widget.onEnd();
        } else {
          _c.text = o.type ?? o.newType!;
          widget.onPicked(o.type ?? o.newType!);
        }
      },
      field: (context, submit) => TextField(
        controller: _c,
        focusNode: widget.line.typeNode,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => submit(),
        onEditingComplete: () {},
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Type (Enter = End of List)',
        ),
      ),
    );
  }
}

/// What is about to be saved, shown in the "Save?" box.
class _Summary extends StatelessWidget {
  final String company;
  final String challan;
  final bool billed;
  final bool needsBill;
  final Map<String, int> full;
  final Map<String, int> empty;

  /// Loan cylinders, as text ("-" when none).
  final String loanFull;
  final String loanEmpty;

  /// Line remarks as text ("" when none).
  final String remarks;

  /// Where each gas goes ("" when the company has no POs).
  final String po;
  final List<CashItem> cash;
  final String? oldDate;

  const _Summary({
    required this.company,
    required this.challan,
    required this.billed,
    required this.needsBill,
    required this.full,
    required this.empty,
    this.loanFull = '-',
    this.loanEmpty = '-',
    this.remarks = '',
    this.po = '',
    required this.cash,
    this.oldDate,
  });

  String _qty(Map<String, int> m) {
    final q = orderedQty(m);
    return q.isEmpty
        ? '-'
        : q.map((e) => '${gasLabel(e.key)} ${e.value}').join(',  ');
  }

  @override
  Widget build(BuildContext context) {
    Widget line(String a, String b, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              a,
              style: const TextStyle(fontSize: 15, color: AppColors.muted),
            ),
          ),
          Flexible(
            child: Text(
              b,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      width: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (oldDate != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              color: const Color(0xFFFFE0B2),
              child: Text(
                'OLD DATE: ${fmtLong(parseDayKey(oldDate!))} (${agoText(parseDayKey(oldDate!))}) - not today!',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFBF360C),
                ),
              ),
            ),
          line('Company', company),
          line(
            'Challan No.',
            challan.isEmpty ? 'not written' : challan,
            color: challan.isEmpty ? AppColors.amber : null,
          ),
          if (needsBill)
            line(
              'Bill',
              billed ? 'Made ✔' : 'NOT made yet',
              color: billed ? AppColors.full : AppColors.danger,
            )
          else
            line(
              'Bill',
              'Not needed (only empty received)',
              color: AppColors.muted,
            ),
          line('Full supplied', _qty(full), color: AppColors.full),
          if (po.isNotEmpty) line('Purchase order', po, color: AppColors.navy),
          line('Empty received', _qty(empty), color: AppColors.empty),
          if (loanFull != '-')
            line('LOAN full supplied', loanFull, color: AppColors.loan),
          if (loanEmpty != '-')
            line('LOAN empty back', loanEmpty, color: AppColors.loan),
          if (remarks.isNotEmpty)
            line('Remarks', remarks, color: AppColors.navy),
          if (cash.isNotEmpty)
            line(
              'Cash',
              cash
                  .map(
                    (c) =>
                        '${c.type} ${fmtMoney(c.amount)} (${modeLabel(c.mode)})',
                  )
                  .join(',  '),
              color: AppColors.amber,
            ),
        ],
      ),
    );
  }
}
