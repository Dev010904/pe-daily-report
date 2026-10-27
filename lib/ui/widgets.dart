import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/day_data.dart';
import '../util/dates.dart';
import 'keys.dart';
import 'theme.dart';

/// The PE logo.
class LogoBadge extends StatelessWidget {
  final double size;
  const LogoBadge({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset('assets/logo.png', width: size, height: size),
  );
}

int qtyOf(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

TextEditingController qtyController(int v) =>
    TextEditingController(text: v == 0 ? '' : '$v');

/// A plain number box for cylinder counts (no +/− buttons). Whatever is in
/// it is selected when the cursor arrives, so typing replaces it. Enter,
/// Up and Down call back so forms can move between boxes like Tally.
class QtyField extends StatefulWidget {
  final TextEditingController controller;
  final Color color;
  final VoidCallback? onChanged;
  final double fieldWidth;
  final FocusNode? focusNode;
  final VoidCallback? onEnter;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final bool autofocus;

  const QtyField({
    super.key,
    required this.controller,
    this.color = AppColors.navy,
    this.onChanged,
    this.fieldWidth = 76,
    this.focusNode,
    this.onEnter,
    this.onUp,
    this.onDown,
    this.autofocus = false,
  });

  @override
  State<QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<QtyField> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(QtyField old) {
    super.didUpdateWidget(old);
    final was = old.focusNode ?? _own;
    if (was != _node) {
      was?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _own?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_node.hasFocus) {
      final c = widget.controller;
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
      widget.onUp!();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
      widget.onDown!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return SizedBox(
      width: widget.fieldWidth,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: TextField(
          controller: widget.controller,
          focusNode: _node,
          autofocus: widget.autofocus,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          textInputAction: widget.onEnter != null
              ? TextInputAction.next
              : TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: (_) => widget.onChanged?.call(),
          onSubmitted: (_) {
            if (onTopPage(context)) {
              widget.onEnter?.call();
            } else {
              reclaimDialogFocus();
            }
          },
          onEditingComplete: widget.onEnter != null ? () {} : null,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: color,
          ),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: TextStyle(
              color: color.withValues(alpha: 0.30),
              fontWeight: FontWeight.w600,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 4,
            ),
            filled: true,
            fillColor: color.withValues(alpha: 0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withValues(alpha: 0.30)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color, width: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Numbers added one after another during the day (e.g. filled 11, later 3
/// more): type a number and press Enter → it is added as a step (+11, +3)
/// and the total is shown. Enter on an empty box moves on. Backspace on an
/// empty box takes the last step off; the small × removes any step.
class StepsField extends StatefulWidget {
  final List<int> steps;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color color;
  final ValueChanged<List<int>> onChanged;
  final VoidCallback? onNext;
  final Key? fieldKey;

  const StepsField({
    super.key,
    required this.steps,
    required this.controller,
    required this.focusNode,
    required this.color,
    required this.onChanged,
    this.onNext,
    this.fieldKey,
  });

  /// The steps plus whatever is typed but not yet added with Enter.
  static List<int> withPending(List<int> steps, TextEditingController c) {
    final n = qtyOf(c);
    return n > 0 ? [...steps, n] : steps;
  }

  @override
  State<StepsField> createState() => _StepsFieldState();
}

class _StepsFieldState extends State<StepsField> {
  void _submit() {
    if (!onTopPage(context)) {
      reclaimDialogFocus();
      return;
    }
    final n = qtyOf(widget.controller);
    widget.controller.clear();
    if (n > 0) {
      widget.onChanged([...widget.steps, n]);
      widget.focusNode.requestFocus();
    } else {
      widget.onNext?.call();
    }
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.backspace &&
        widget.controller.text.isEmpty &&
        widget.steps.isNotEmpty) {
      widget.onChanged(widget.steps.sublist(0, widget.steps.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final steps = widget.steps;
    final total = steps.fold(0, (a, b) => a + b);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++)
          Container(
            padding: const EdgeInsets.fromLTRB(9, 4, 2, 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+${steps[i]}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                ExcludeFocus(
                  child: InkWell(
                    onTap: () => widget.onChanged([...steps]..removeAt(i)),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(
                        Icons.close,
                        size: 15,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (steps.length > 1)
          Text(
            '= $total',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        SizedBox(
          width: 86,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: TextField(
              key: widget.fieldKey,
              controller: widget.controller,
              focusNode: widget.focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              // The page's working ("0 + 8 − 5 = 3") counts the number
              // being typed too, so tell it on every key.
              onChanged: (_) {
                setState(() {});
                widget.onChanged(widget.steps);
              },
              onSubmitted: (_) => _submit(),
              onEditingComplete: () {},
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: color,
              ),
              decoration: InputDecoration(
                hintText: steps.isEmpty ? '0' : '+ more',
                hintStyle: TextStyle(
                  fontSize: steps.isEmpty ? 19 : 14,
                  color: color.withValues(alpha: 0.35),
                  fontWeight: FontWeight.w600,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                filled: true,
                fillColor: color.withValues(alpha: 0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: color.withValues(alpha: 0.30)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: color, width: 2.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A row that lights up while the cursor is in it, so it is always clear
/// which gas / line is being typed.
class FocusRow extends StatefulWidget {
  final Widget child;
  final Color? stripe;
  final EdgeInsets padding;
  const FocusRow({
    super.key,
    required this.child,
    this.stripe,
    this.padding = const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
  });

  @override
  State<FocusRow> createState() => _FocusRowState();
}

class _FocusRowState extends State<FocusRow> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (f) => setState(() => _on = f),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _on ? const Color(0xFFFFF1C4) : widget.stripe,
        border: Border(
          left: BorderSide(
            color: _on ? AppColors.gold : Colors.transparent,
            width: 5,
          ),
          top: const BorderSide(color: Color(0xFFE6EAF0)),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontWeight: _on ? FontWeight.w900 : null,
          color: _on ? AppColors.navyDark : null,
        ),
        child: widget.child,
      ),
    ),
  );
}

/// Small coloured "O2 2" chip used in entry cards.
class QtyChip extends StatelessWidget {
  final String label;
  final int qty;
  final Color color;
  const QtyChip({
    super.key,
    required this.label,
    required this.qty,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(fontSize: 14, color: Color(0xFF39424F)),
          ),
          TextSpan(
            text: '$qty',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  final Widget? trailing;
  const SectionTitle(
    this.text, {
    super.key,
    this.color = AppColors.navy,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

// ------------------------------------------------------------------ dialogs

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'Yes',
  String no = 'No',
  bool danger = false,
  Widget? extra,
}) async {
  final r = await askChoice(
    context,
    title: title,
    message: message,
    yes: yes,
    no: no,
    danger: danger,
    extra: extra,
  );
  return r == 'yes';
}

/// Tally-style question: [Enter]/[Y] = yes, [Esc]/[N] = no, and optional
/// extra letter choices, e.g. {'c': 'Add cash'}. Returns 'yes', 'no' or
/// the extra letter.
Future<String> askChoice(
  BuildContext context, {
  required String title,
  String? message,
  Widget? extra,
  String yes = 'Yes',
  String no = 'No',
  bool danger = false,
  Map<String, String> more = const {},
}) async {
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => KeyDialog(
      onEnter: () => Navigator.pop(ctx, 'yes'),
      onEsc: () => Navigator.pop(ctx, 'no'),
      letters: {
        'y': () => Navigator.pop(ctx, 'yes'),
        'n': () => Navigator.pop(ctx, 'no'),
        for (final m in more.keys) m: () => Navigator.pop(ctx, m),
      },
      child: AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null)
                Text(message, style: const TextStyle(fontSize: 16)),
              ?extra,
            ],
          ),
        ),
        actions: [
          for (final m in more.entries)
            TextButton(
              key: Key('choice_${m.key}'),
              onPressed: () => Navigator.pop(ctx, m.key),
              child: Text('${m.value} (${m.key.toUpperCase()})'),
            ),
          TextButton(
            key: const Key('choiceNo'),
            onPressed: () => Navigator.pop(ctx, 'no'),
            child: Text('$no (Esc)'),
          ),
          FilledButton(
            key: const Key('choiceYes'),
            style: danger
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, 'yes'),
            child: Text('$yes (Enter)'),
          ),
        ],
      ),
    ),
  );
  return r ?? 'no';
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String ok = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) =>
        _TextDialog(title: title, initial: initial, hint: hint, ok: ok),
  );
}

class _TextDialog extends StatefulWidget {
  final String title, initial, hint, ok;
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.ok,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    final t = _c.text.trim();
    if (t.isNotEmpty) Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _done, child: Text(widget.ok)),
    ],
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

// ------------------------------------------------------------ name picker

/// Bottom sheet listing names with a search box and an "add new" row.
/// Returns the picked item, or null.
Future<NamedItem?> pickNamed(
  BuildContext context, {
  required String title,
  required List<NamedItem> items,
  required String addLabel,
  required Future<NamedItem> Function(String name) onAdd,
}) {
  return showModalBottomSheet<NamedItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _NamePickerSheet(
      title: title,
      items: items,
      addLabel: addLabel,
      onAdd: onAdd,
    ),
  );
}

class _NamePickerSheet extends StatefulWidget {
  final String title;
  final List<NamedItem> items;
  final String addLabel;
  final Future<NamedItem> Function(String name) onAdd;
  const _NamePickerSheet({
    required this.title,
    required this.items,
    required this.addLabel,
    required this.onAdd,
  });

  @override
  State<_NamePickerSheet> createState() => _NamePickerSheetState();
}

class _NamePickerSheetState extends State<_NamePickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add([String? preset]) async {
    final name =
        preset ??
        await askText(context, title: widget.addLabel, hint: 'Name', ok: 'Add');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final item = await widget.onAdd(name);
    if (mounted) Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.items
        : widget.items.where((c) => c.name.toLowerCase().contains(q)).toList();
    final exact = widget.items.any((c) => c.name.toLowerCase() == q);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('pickSearch'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                // Enter takes the first name in the list, or adds the typed
                // name when nothing matches.
                onSubmitted: (_) {
                  if (list.isNotEmpty && q.isNotEmpty) {
                    Navigator.pop(context, list.first);
                  } else if (q.isNotEmpty && !exact) {
                    _add(_search.text.trim());
                  }
                },
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Type name, then Enter',
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (q.isNotEmpty && !exact)
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.fullBg,
                        child: Icon(Icons.add, color: AppColors.full),
                      ),
                      title: Text(
                        'Add "${_search.text.trim()}"',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.full,
                        ),
                      ),
                      onTap: () => _add(_search.text.trim()),
                    ),
                  if (q.isEmpty)
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.fullBg,
                        child: Icon(Icons.add, color: AppColors.full),
                      ),
                      title: Text(
                        widget.addLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.full,
                        ),
                      ),
                      onTap: () => _add(),
                    ),
                  for (final c in list)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.emptyBg,
                        child: Text(
                          c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(c.name, style: const TextStyle(fontSize: 18)),
                      onTap: () => Navigator.pop(context, c),
                    ),
                  if (list.isEmpty && q.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No names yet. Tap the green + above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- calendar

/// Month calendar where days with saved data show a dot.
Future<DateTime?> pickDay(
  BuildContext context, {
  required DateTime selected,
  required bool Function(DateTime) hasData,
  DateTime? first,
  DateTime? last,
  String title = 'Choose date',
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CalendarSheet(
      selected: selected,
      hasData: hasData,
      first: first,
      last: last ?? today(),
      title: title,
    ),
  );
}

class _CalendarSheet extends StatefulWidget {
  final DateTime selected;
  final bool Function(DateTime) hasData;
  final DateTime? first;
  final DateTime last;
  final String title;
  const _CalendarSheet({
    required this.selected,
    required this.hasData,
    required this.first,
    required this.last,
    required this.title,
  });

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  bool _allowed(DateTime d) =>
      !d.isAfter(widget.last) &&
      (widget.first == null || !d.isBefore(widget.first!));

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(
      _month.year,
      _month.month,
      1,
    ).weekday; // Mon=1
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 1; i < firstWeekday; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];
    final now = today();
    final canNext = DateTime(
      _month.year,
      _month.month + 1,
    ).isBefore(DateTime(widget.last.year, widget.last.month + 1));
    final canPrev =
        widget.first == null ||
        DateTime(
          _month.year,
          _month.month,
        ).isAfter(DateTime(widget.first!.year, widget.first!.month));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: canPrev
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      )
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${_monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: canNext
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      )
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final w in const [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ])
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: w == 'Sun' ? AppColors.danger : AppColors.muted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            children: [
              for (final d in cells)
                if (d == null) const SizedBox() else _dayCell(d, now),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.full,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'Green dot = data saved on that day',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
          if (_allowed(now)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, now),
                icon: const Icon(Icons.today),
                label: const Text('Go to Today'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayCell(DateTime d, DateTime now) {
    final allowed = _allowed(d);
    final isSel = sameDay(d, widget.selected);
    final isToday = sameDay(d, now);
    final has = widget.hasData(d);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSel ? AppColors.navy : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isToday && !isSel
              ? const BorderSide(color: AppColors.gold, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: allowed ? () => Navigator.pop(context, d) : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${d.day}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isSel
                      ? Colors.white
                      : !allowed
                      ? const Color(0xFFC3C8D0)
                      : d.weekday == DateTime.sunday
                      ? AppColors.danger
                      : const Color(0xFF1B2330),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: has
                      ? (isSel ? Colors.white : AppColors.full)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats a money amount typed by the user, or null if invalid.
double? parseAmount(String s) {
  final t = s.replaceAll(',', '').replaceAll('₹', '').trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String moneyText(double v) => fmtMoney(v);

/// A dropdown with a label box around it. [addLabel] adds a last
/// "+ Add new..." row that calls [onAdd] instead of selecting.
class LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final String? addLabel;
  final VoidCallback? onAdd;

  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.addLabel,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: Color(0xFF1B2330),
    );
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Object>(
          value: items.containsKey(value) ? value : null,
          isDense: true,
          isExpanded: true,
          style: style,
          hint: const Text('Choose', style: TextStyle(color: AppColors.amber)),
          items: [
            for (final e in items.entries)
              DropdownMenuItem<Object>(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            if (addLabel != null)
              DropdownMenuItem<Object>(
                value: const _AddNew(),
                child: Text(
                  addLabel!,
                  style: const TextStyle(color: AppColors.full),
                ),
              ),
          ],
          onChanged: (v) {
            if (v is _AddNew) {
              onAdd?.call();
            } else if (v is T) {
              onChanged(v);
            }
          },
        ),
      ),
    );
  }
}

class _AddNew {
  const _AddNew();
}

/// Green ✔ when the bill is made, red ✘ when it is still to be made, and a
/// grey – when no bill is needed (only empties received).
class BillMark extends StatelessWidget {
  final bool billed;
  final double size;
  final bool needed;
  const BillMark({
    super.key,
    required this.billed,
    this.size = 30,
    this.needed = true,
  });

  @override
  Widget build(BuildContext context) => !needed
      ? Tooltip(
          message: 'No bill needed (only empty received)',
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFB4BFD0), width: 1.5),
            ),
            child: Text(
              '–',
              style: TextStyle(
                color: const Color(0xFF8A94A6),
                fontSize: size * 0.6,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        )
      : Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: billed ? AppColors.full : AppColors.danger,
            shape: BoxShape.circle,
          ),
          child: Icon(
            billed ? Icons.check : Icons.close,
            color: Colors.white,
            size: size * 0.66,
          ),
        );
}

/// Keeps page content at a comfortable width on big PC screens.
class PageWidth extends StatelessWidget {
  final Widget child;
  final double max;
  const PageWidth({super.key, required this.child, this.max = 980});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: child,
    ),
  );
}
