import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../models/purchase_order.dart';
import 'pick_field.dart';
import 'theme.dart';

/// The PO numbers of an entry: "PO 4500123", or "PO 4500123 (Oxygen),
/// 778 (CO2)" when its gases go to different POs. "" when none.
String poText(AppStore store, Entry e) {
  final byNo = <String, List<String>>{};
  for (final g in kGases) {
    if (e.fullOf(g.code) == 0) continue;
    final n = store.poNumberOf(e, g.code);
    if (n.isNotEmpty) (byNo[n] ??= []).add(g.label);
  }
  if (byNo.isEmpty) return '';
  if (byNo.length == 1) return 'PO ${byNo.keys.first}';
  return 'PO ${byNo.entries.map((x) => '${x.key} (${x.value.join(', ')})').join(', ')}';
}

/// The challan number with the PO under it ("-" when no challan).
String challanWithPo(AppStore store, Entry e) {
  final c = e.challan.isEmpty ? '-' : e.challan;
  final p = poText(store, e);
  return p.isEmpty ? c : '$c\n$p';
}

/// "40 left", "fully supplied" or "over by 3".
String poLeftText(int left) => left > 0
    ? '$left left'
    : (left == 0 ? 'fully supplied' : 'over by ${-left}');

/// Each gas of a PO and what is left of it: "Oxygen 40 left, CO2 fully
/// supplied".
String poItemsText(AppStore store, PurchaseOrder p, {String? exceptEntry}) => [
  for (final g in kGases)
    if (p.hasGas(g.code))
      '${g.label} ${poLeftText(store.poLine(p, g.code, exceptEntry: exceptEntry).left)}',
].join(',  ');

/// A PO in the list, or "No PO".
class PoChoice {
  final PurchaseOrder? po;
  const PoChoice(this.po);
  String get id => po?.id ?? kNoPo;
}

/// Choose-only box for the PO an entry is supplied against. Letters / digits
/// jump to the PO number starting with them; Enter takes it.
class PoPickField extends StatefulWidget {
  final AppStore store;
  final String? companyId;

  /// PO id, or [kNoPo].
  final String value;
  final FocusNode focusNode;
  final ValueChanged<String> onPicked;

  /// The saved entry being changed (its own cylinders are not "used").
  final String? exceptEntry;

  const PoPickField({
    super.key,
    required this.store,
    required this.companyId,
    required this.value,
    required this.focusNode,
    required this.onPicked,
    this.exceptEntry,
  });

  @override
  State<PoPickField> createState() => _PoPickFieldState();
}

class _PoPickFieldState extends State<PoPickField> {
  late final TextEditingController _c = TextEditingController(
    text: _short(widget.value),
  );

  String _short(String id) {
    final p = widget.store.po(id);
    return p == null ? 'No PO' : 'PO ${p.number}';
  }

  @override
  void didUpdateWidget(PoPickField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value || old.companyId != widget.companyId) {
      _c.text = _short(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<PoChoice> _options(String _) {
    final all = [
      for (final p in widget.store.posOf(widget.companyId)) PoChoice(p),
      const PoChoice(null),
    ];
    // The chosen one first, so Enter keeps it.
    final i = all.indexWhere((o) => o.id == widget.value);
    if (i > 0) all.insert(0, all.removeAt(i));
    return all;
  }

  String _label(PoChoice o) {
    final p = o.po;
    if (p == null) return 'No PO  (not against a purchase order)';
    return 'PO ${p.number}   ·   '
        '${poItemsText(widget.store, p, exceptEntry: widget.exceptEntry)}';
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(' ', '');

  int _typeAhead(String typed, List<PoChoice> opts) {
    final t = _norm(typed);
    for (var i = 0; i < opts.length; i++) {
      final p = opts[i].po;
      final name = p == null ? 'nopo' : _norm(p.number);
      if (name.startsWith(t) || (p != null && 'po$name'.startsWith(t))) {
        return i;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) => PickField<PoChoice>(
    controller: _c,
    focusNode: widget.focusNode,
    options: _options,
    label: _label,
    special: (o) => o.po == null,
    title: 'Choose purchase order  (↑ ↓, Enter)',
    listWidth: 460,
    typeAhead: _typeAhead,
    onPicked: (o) {
      _c.text = _short(o.id);
      widget.onPicked(o.id);
    },
    field: (context, submit) => TextField(
      key: const Key('poPick'),
      controller: _c,
      focusNode: widget.focusNode,
      readOnly: true,
      enableInteractiveSelection: false,
      textInputAction: TextInputAction.next,
      onEditingComplete: () {},
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.assignment_outlined, color: AppColors.navy),
        suffixIcon: Icon(Icons.arrow_drop_down),
      ),
    ),
  );
}
