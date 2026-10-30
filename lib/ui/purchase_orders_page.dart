import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/gas.dart';
import '../models/purchase_order.dart';
import 'gas_lines.dart';
import 'keys.dart';
import 'po_field.dart';
import 'theme.dart';
import 'widgets.dart';

/// One company's purchase orders (Settings > Companies > PO): Up / Down,
/// Enter = change, Delete = remove, N = add. POs are managed only here.
class PurchaseOrdersPage extends StatelessWidget {
  final AppStore store;
  final String companyId;
  const PurchaseOrdersPage({
    super.key,
    required this.store,
    required this.companyId,
  });

  void _edit(BuildContext context, [PurchaseOrder? po]) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PoEditPage(store: store, companyId: companyId, po: po),
    ),
  );

  Future<void> _remove(BuildContext context, PurchaseOrder p) async {
    final ok = await confirm(
      context,
      title: 'Remove PO ${p.number}?',
      message:
          'It will not be tracked any more. Entries already supplied '
          'against it keep the PO number.',
      yes: 'Remove',
      danger: true,
    );
    if (ok) await store.removePo(p);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final company = store.company(companyId);
        final pos = store.posOf(companyId);
        return KeyPage(
          letters: {'n': () => _edit(context)},
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                'Purchase Orders  ·  ${company?.name ?? ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            bottomNavigationBar: isWide(context)
                ? const KeyHints([
                    ('↑ ↓', 'Move'),
                    ('Enter', 'Change'),
                    ('Del', 'Remove'),
                    ('N', 'Add new PO'),
                    ('Esc', 'Back'),
                  ])
                : null,
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('addPo'),
              backgroundColor: AppColors.full,
              foregroundColor: Colors.white,
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add),
              label: const Text(
                'Add PO (N)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            body: PageWidth(
              max: 720,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      'In the entries of this company a "PO No." box comes after '
                      'Bill. Each gas supplied is counted against its PO; the '
                      'dashboard tells when a PO is almost or fully supplied.',
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                  ),
                  if (pos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No purchase orders.\nPress N (or tap "Add PO").',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, color: AppColors.muted),
                      ),
                    ),
                  KeyList(
                    autofocus: true,
                    itemCount: pos.length,
                    onOpen: (i) => _edit(context, pos[i]),
                    onDelete: (i) => _remove(context, pos[i]),
                    itemBuilder: (context, i, selected) =>
                        _poCard(context, pos[i], selected),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _poCard(BuildContext context, PurchaseOrder p, bool selected) => Card(
    key: Key('po_${p.number}'),
    margin: const EdgeInsets.only(bottom: 8),
    color: selected ? kSelectBg : null,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? kSelectLine : Colors.transparent,
        width: 2,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PoProgress(store: store, po: p),
          ),
          ExcludeFocus(
            child: IconButton(
              tooltip: 'Change (Enter)',
              onPressed: () => _edit(context, p),
              icon: const Icon(Icons.edit, color: AppColors.navy),
            ),
          ),
          ExcludeFocus(
            child: IconButton(
              tooltip: 'Remove (Delete)',
              onPressed: () => _remove(context, p),
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A PO's number and, gas by gas, supplied / ordered and what is left.
class PoProgress extends StatelessWidget {
  final AppStore store;
  final PurchaseOrder po;

  /// Company name above the PO number (dashboard).
  final String? company;
  const PoProgress({
    super.key,
    required this.store,
    required this.po,
    this.company,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (company != null)
          Text(
            company!,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        Text(
          'PO ${po.number}',
          style: TextStyle(
            fontSize: company == null ? 18 : 15,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        for (final g in kGases)
          if (po.hasGas(g.code)) _gasLine(store.poLine(po, g.code)),
      ],
    );
  }

  Widget _gasLine(PoLine l) {
    final color = l.done
        ? AppColors.danger
        : (l.nearlyDone ? const Color(0xFFE65100) : AppColors.full);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${gasLabel(l.gas)}:  ${l.supplied} of ${l.ordered} supplied',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l.done
                  ? poLeftText(l.left).toUpperCase()
                  : '${poLeftText(l.left)}${l.nearlyDone ? ' - almost done' : ''}',
              key: Key('poLeft_${l.po.number}_${l.gas}'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Add or change a PO: its number, then each gas and how many were ordered.
class PoEditPage extends StatefulWidget {
  final AppStore store;
  final String companyId;
  final PurchaseOrder? po;
  const PoEditPage({
    super.key,
    required this.store,
    required this.companyId,
    this.po,
  });

  @override
  State<PoEditPage> createState() => _PoEditPageState();
}

class _PoEditPageState extends State<PoEditPage> {
  AppStore get store => widget.store;
  late final TextEditingController _number = TextEditingController(
    text: widget.po?.number ?? '',
  );
  final _numberNode = FocusNode(debugLabel: 'poNumber');
  late final GasLines _items = GasLines(1, {
    for (final e in (widget.po?.items ?? const <String, int>{}).entries)
      e.key: [e.value],
  });
  final _itemsKey = GlobalKey<GasLinesEditorState>();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _numberNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _numberNode.dispose();
    _items.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  /// What is wrong (null = can be saved).
  String? _problem() {
    final n = _number.text.trim();
    if (n.isEmpty) return 'Write the PO number';
    final same = store
        .posOf(widget.companyId)
        .where(
          (p) =>
              p.id != widget.po?.id &&
              p.number.toLowerCase() == n.toLowerCase(),
        );
    if (same.isNotEmpty) return 'PO $n is already there for this company';
    if (_items.column(0).isEmpty) {
      return 'Choose a gas and type how many cylinders were ordered';
    }
    return null;
  }

  Future<void> _ask() async {
    final problem = _problem();
    if (problem != null) {
      toast(context, problem);
      if (_number.text.trim().isEmpty) _numberNode.requestFocus();
      return;
    }
    final items = _items.column(0);
    final ok = await confirm(
      context,
      title: 'Save PO ${_number.text.trim()}?',
      message: orderedQty(items)
          .map((e) => '${gasLabel(e.key)}: ${e.value} cylinders')
          .join('\n'),
      yes: 'Yes, save',
    );
    if (!mounted) return;
    if (ok) {
      await _save();
    } else {
      _itemsKey.currentState?.focusLast();
    }
  }

  Future<void> _save() async {
    final problem = _problem();
    if (problem != null) {
      toast(context, problem);
      return;
    }
    final number = _number.text.trim(), items = _items.column(0);
    final old = widget.po;
    if (old == null) {
      await store.addPo(widget.companyId, number, items);
    } else {
      await store.savePo(
        old.copy()
          ..number = number
          ..items = items,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final company = store.company(widget.companyId)?.name ?? '';
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
              '${widget.po == null ? 'New PO' : 'Change PO'}  ·  $company',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: PageWidth(
            max: 660,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                Card(
                  child: FocusRow(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 110,
                          child: Text(
                            'PO number',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            key: const Key('poNumber'),
                            controller: _number,
                            focusNode: _numberNode,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            maxLength: 40,
                            onChanged: (_) => _touch(),
                            onSubmitted: (_) {
                              if (!onTopPage(context)) {
                                reclaimDialogFocus();
                                return;
                              }
                              _itemsKey.currentState?.focusFirst();
                            },
                            onEditingComplete: () {},
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              counterText: '',
                              hintText: 'e.g. 4500012345',
                              prefixIcon: Icon(Icons.assignment_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    'Gas and cylinders ordered  (a PO can have one gas or more)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                GasLinesEditor(
                  key: _itemsKey,
                  lines: _items,
                  titles: const ['Ordered'],
                  colors: const [AppColors.navy],
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
                      key: const Key('savePo'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.full,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        'Save PO',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
                if (isWide(context))
                  const KeyHints([
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
