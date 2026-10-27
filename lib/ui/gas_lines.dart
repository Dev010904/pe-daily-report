import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/gas.dart';
import 'keys.dart';
import 'pick_field.dart';
import 'theme.dart';
import 'widgets.dart';

/// One choice in the gas list: a gas, "End of List" (finish, like Tally),
/// or "Remove this line" (when the gas name of a filled line is erased).
///
/// Never const and never shared: the pop-up list ignores a choice that is
/// the same object as the one picked last time, so a shared "End of List"
/// would work only once (the cursor then got stuck after coming back).
class GasChoice {
  final Gas? gas;
  final bool remove;
  GasChoice(this.gas, {this.remove = false});
  GasChoice.endOfList() : gas = null, remove = false;
  GasChoice.removeLine() : gas = null, remove = true;
  bool get isEnd => gas == null && !remove;
  bool get isSpecial => gas == null;
  String get label => remove ? 'Remove this line' : gas?.label ?? 'End of List';
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Gases matching what was typed ("co" → CO2, "arm" → AR Mix.), names that
/// start with it first. [skip] leaves out gases already used on other lines.
List<Gas> matchGases(
  String typed, {
  Set<String> skip = const {},
  List<Gas> from = kGases,
}) {
  final t = _norm(typed);
  final pool = from.where((g) => !skip.contains(g.code));
  if (t.isEmpty) return pool.toList();
  final starts = <Gas>[], has = <Gas>[];
  for (final g in pool) {
    final n = _norm(g.label);
    if (n.startsWith(t) || _norm(g.code).startsWith(t)) {
      starts.add(g);
    } else if (n.contains(t)) {
      has.add(g);
    }
  }
  return [...starts, ...has];
}

/// Typing box with a pop-up list of gases. Up/Down move in the list, Enter
/// takes the highlighted one. With [onEnd], an empty box offers
/// "End of List" first, so Enter on an empty line finishes the list.
class GasPickField extends StatefulWidget {
  final String? value;
  final ValueChanged<String> onPicked;
  final VoidCallback? onEnd;

  /// Filled line: erasing the gas name offers "Remove this line".
  final VoidCallback? onClear;
  final Set<String> skip;
  final FocusNode focusNode;
  final bool autofocus;
  final String hint;

  /// Choose from the list only, nothing can be written in the box (a
  /// letter jumps to the gas starting with it).
  final bool chooseOnly;

  /// What can be chosen (normally the gases; loan lines list
  /// "ARGON · ABC Plant" choices).
  final List<Gas> pool;

  const GasPickField({
    super.key,
    required this.value,
    required this.onPicked,
    required this.focusNode,
    this.onEnd,
    this.onClear,
    this.skip = const {},
    this.autofocus = false,
    this.hint = 'Type gas name',
    this.chooseOnly = false,
    this.pool = kGases,
  });

  @override
  State<GasPickField> createState() => _GasPickFieldState();
}

class _GasPickFieldState extends State<GasPickField> {
  late final TextEditingController _c = TextEditingController(
    text: _label(widget.value),
  );

  Gas? _gas(String code) {
    for (final g in widget.pool) {
      if (g.code == code) return g;
    }
    return gasByCode(code);
  }

  String _label(String? code) =>
      code == null ? '' : (_gas(code)?.label ?? gasLabel(code));

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(GasPickField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      // Now showing another line (e.g. one above was removed): show its gas.
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
      _c.text = _label(widget.value);
    } else if (old.value != widget.value && !widget.focusNode.hasFocus) {
      _c.text = _label(widget.value);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _c.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
      if (mounted) roomBelow(context);
    } else if (_c.text != _label(widget.value)) {
      // Left without choosing: show the chosen gas again.
      _c.text = _label(widget.value);
    }
  }

  List<GasChoice> _options(String text) {
    final current = _label(widget.value);
    final skip = widget.skip.difference({widget.value});
    if (widget.value != null && text == current) {
      return [
        GasChoice(_gas(widget.value!)),
        for (final g in matchGases('', skip: skip, from: widget.pool))
          if (g.code != widget.value) GasChoice(g),
        // Choose-only: the name can't be erased, so removing is offered here.
        if (widget.chooseOnly && widget.onClear != null) GasChoice.removeLine(),
      ];
    }
    final gases = matchGases(
      text,
      skip: skip,
      from: widget.pool,
    ).map(GasChoice.new);
    if (text.trim().isEmpty && widget.onClear != null) {
      return [GasChoice.removeLine(), ...gases];
    }
    if (text.trim().isEmpty && widget.onEnd != null) {
      return [GasChoice.endOfList(), ...gases];
    }
    return gases.toList();
  }

  /// Choose-only: the first gas whose name (or code) starts with [typed].
  static int _typeAhead(String typed, List<GasChoice> opts) {
    final t = _norm(typed);
    for (var i = 0; i < opts.length; i++) {
      final g = opts[i].gas;
      if (g == null) continue;
      if (_norm(g.label).startsWith(t) || _norm(g.code).startsWith(t)) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final chooseOnly = widget.chooseOnly;
    return PickField<GasChoice>(
      controller: _c,
      focusNode: widget.focusNode,
      options: _options,
      label: (o) => o.label,
      special: (o) => o.isSpecial,
      title: chooseOnly ? 'Choose gas  (↑ ↓, Enter)' : 'List of Gases',
      typeAhead: chooseOnly ? _typeAhead : null,
      onPicked: (o) {
        if (o.remove) {
          _c.text = _label(widget.value);
          widget.onClear?.call();
        } else if (o.isEnd) {
          _c.text = _label(widget.value);
          widget.onEnd?.call();
        } else {
          _c.text = o.gas!.label;
          widget.onPicked(o.gas!.code);
        }
      },
      field: (context, submit) => TextField(
        controller: _c,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        // Choose-only: nothing can be written; Enter is read as a key.
        readOnly: chooseOnly,
        enableInteractiveSelection: !chooseOnly,
        textInputAction: TextInputAction.next,
        onSubmitted: chooseOnly ? null : (_) => submit(),
        onEditingComplete: () {},
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 11,
          ),
          suffixIcon: const Icon(Icons.arrow_drop_down, color: AppColors.muted),
          suffixIconConstraints: const BoxConstraints(minWidth: 28),
        ),
      ),
    );
  }
}

/// The pop-up list under a typing box (Tally's "List of ..." panel).
class ChoiceList<T extends Object> extends StatefulWidget {
  final Iterable<T> options;
  final AutocompleteOnSelected<T> onSelected;
  final String Function(T) label;
  final bool Function(T)? special;
  final String title;
  final double width;
  final double maxHeight;

  const ChoiceList({
    super.key,
    required this.options,
    required this.onSelected,
    required this.label,
    required this.title,
    this.special,
    this.width = 280,
    this.maxHeight = 340,
  });

  @override
  State<ChoiceList<T>> createState() => _ChoiceListState<T>();
}

class _ChoiceListState<T extends Object> extends State<ChoiceList<T>> {
  final _scroll = ScrollController();

  /// Every row has the same height, so the highlighted one can be kept in
  /// view exactly (the list never opens scrolled away from the top).
  static const double _row = 38;
  int? _shown;

  @override
  void initState() {
    super.initState();
    openChoiceLists++;
  }

  @override
  void dispose() {
    openChoiceLists--;
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls just enough to show row [i] (none when it is already shown).
  void _keepVisible(int i) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final top = i * _row, bottom = top + _row;
    var to = p.pixels;
    if (top < to) {
      to = top;
    } else if (bottom > to + p.viewportDimension) {
      to = bottom - p.viewportDimension;
    }
    to = to.clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to != p.pixels) _scroll.jumpTo(to);
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final label = widget.label;
    final special = widget.special;
    final hi = AutocompleteHighlightedOption.of(context);
    if (hi != _shown) {
      _shown = hi;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keepVisible(hi);
      });
    }
    // Placed by the pop-up box (below or above the typing box).
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.maxHeight,
          maxWidth: widget.width,
          minWidth: widget.width,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The title stays on top; only the choices scroll.
            Container(
              color: AppColors.navy,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                widget.title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemExtent: _row,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final o = options.elementAt(i);
                  final on = hi == i;
                  final isSpecial = special?.call(o) ?? false;
                  return InkWell(
                    onTap: () => widget.onSelected(o),
                    child: Container(
                      color: on ? kSelectBg : null,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        label(o),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                          fontStyle: isSpecial ? FontStyle.italic : null,
                          color: isSpecial
                              ? AppColors.full
                              : const Color(0xFF1B2330),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line: a gas and its numbers (e.g. full supplied, empty received).
class GasLine {
  String? gas;
  final List<TextEditingController> qty;
  final FocusNode gasNode = FocusNode(debugLabel: 'gas');
  final List<FocusNode> qtyNodes;

  GasLine(int columns, {this.gas, List<int>? values})
    : qty = [
        for (var i = 0; i < columns; i++)
          qtyController(values != null && i < values.length ? values[i] : 0),
      ],
      qtyNodes = [
        for (var i = 0; i < columns; i++) FocusNode(debugLabel: 'qty$i'),
      ];

  bool get hasNumbers => qty.any((c) => qtyOf(c) > 0);

  void dispose() {
    gasNode.dispose();
    for (final c in qty) {
      c.dispose();
    }
    for (final n in qtyNodes) {
      n.dispose();
    }
  }
}

/// The lines of a gas list; there is always one empty line at the end to
/// type the next gas in.
class GasLines {
  final int columns;

  /// What the lines can be (normally the gases).
  final List<Gas> pool;
  final List<GasLine> lines = [];

  GasLines(
    this.columns, [
    Map<String, List<int>> initial = const {},
    this.pool = kGases,
  ]) {
    load(initial);
  }

  void load(Map<String, List<int>> initial) {
    // The old boxes may still be on screen until the next frame: throw
    // them away after it.
    final old = List.of(lines);
    if (old.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final l in old) {
          l.dispose();
        }
      });
    }
    lines.clear();
    for (final g in pool) {
      final v = initial[g.code];
      if (v != null && v.any((x) => x != 0)) {
        lines.add(GasLine(columns, gas: g.code, values: v));
      }
    }
    ensureBlank();
  }

  void ensureBlank() {
    if (lines.isEmpty || lines.last.gas != null) lines.add(GasLine(columns));
  }

  /// gas -> qty for one column.
  Map<String, int> column(int i) {
    final m = <String, int>{};
    for (final l in lines) {
      final v = qtyOf(l.qty[i]);
      if (l.gas == null || v <= 0) continue;
      m[l.gas!] = (m[l.gas!] ?? 0) + v;
    }
    return m;
  }

  int total(int i) => column(i).values.fold(0, (a, b) => a + b);

  Set<String> get usedGases => {for (final l in lines) ?l.gas};

  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
  }
}

/// Table of gas lines: [#] [Gas] [numbers...]. Type a gas name, Enter, type
/// the numbers (Enter moves on), and the next line opens. Enter on an empty
/// gas box = End of List → [onEndOfList] (the form then asks to save).
class GasLinesEditor extends StatefulWidget {
  final GasLines lines;
  final List<String> titles;
  final List<Color> colors;
  final VoidCallback onChanged;
  final VoidCallback onEndOfList;
  final bool autofocusFirst;

  /// Gases that may not be picked here (e.g. ones a damaged cylinder
  /// cannot be repaired into).
  final Set<String> skipGases;

  /// Gas boxes are choose-only (picked from the list, never written).
  final bool chooseOnly;

  const GasLinesEditor({
    super.key,
    required this.lines,
    required this.titles,
    required this.colors,
    required this.onChanged,
    required this.onEndOfList,
    this.autofocusFirst = false,
    this.skipGases = const {},
    this.chooseOnly = false,
  });

  @override
  State<GasLinesEditor> createState() => GasLinesEditorState();
}

class GasLinesEditorState extends State<GasLinesEditor> {
  List<GasLine> get _lines => widget.lines.lines;

  void focusFirst() => _focus(_lines.first.gasNode);

  void focusLast() => _focus(_lines.last.gasNode);

  void _focus(FocusNode n) => focusSoon(n);

  void _picked(int i, String code) {
    setState(() {
      _lines[i].gas = code;
      widget.lines.ensureBlank();
    });
    widget.onChanged();
    _focus(_lines[i].qtyNodes.first);
  }

  void _qtyEnter(int i, int col) {
    if (_lines[i].gas == null) {
      // Numbers on the empty line: the gas must be chosen first.
      _focus(_lines[i].gasNode);
      return;
    }
    if (col + 1 < widget.lines.columns) {
      _focus(_lines[i].qtyNodes[col + 1]);
      return;
    }
    setState(widget.lines.ensureBlank);
    _focus(_lines[i + 1].gasNode);
  }

  void _up(int i, int col) {
    if (i > 0) {
      _focus(_lines[i - 1].qtyNodes[col]);
    } else {
      // First line: on to the box above the list.
      focusNeighbourField(
        _lines[i].qtyNodes[col],
        forward: false,
        wholeRow: true,
      );
    }
  }

  void _down(int i, int col) {
    if (i + 1 >= _lines.length) {
      focusNeighbourField(
        _lines[i].qtyNodes[col],
        forward: true,
        wholeRow: true,
      );
      return;
    }
    final next = _lines[i + 1];
    _focus(next.gas == null ? next.gasNode : next.qtyNodes[col]);
  }

  void _remove(int i) {
    final gone = _lines[i];
    setState(() {
      _lines.removeAt(i);
      widget.lines.ensureBlank();
    });
    // Its boxes may still be on screen until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
    widget.onChanged();
    // The cursor goes to the line that took its place, after the screen is
    // rebuilt (its box is first linked to that line, then gets the cursor;
    // the other way round the box looks active but takes no keys).
    final next = _lines[i < _lines.length ? i : _lines.length - 1].gasNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && next.context != null) next.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cols = widget.lines.columns;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 480;
        final qtyW = narrow ? 70.0 : 100.0;
        Widget cell(Widget child, {double? width}) => width == null
            ? Expanded(child: child)
            : SizedBox(width: width, child: child);
        final head = TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: narrow ? 12.5 : 14,
        );
        // # + gas + numbers + remove button + paddings and the focus bar.
        final natural = 30 + _gasW + cols * (qtyW + 12) + 40 + 34.0;
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: narrow
                ? box.maxWidth
                : (natural < box.maxWidth ? natural : box.maxWidth),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AppColors.navy,
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 30, child: Text('#', style: head)),
                        cell(
                          Text('Gas', style: head),
                          width: narrow ? null : _gasW,
                        ),
                        for (var c = 0; c < cols; c++)
                          cell(
                            Text(
                              widget.titles[c],
                              textAlign: TextAlign.center,
                              style: head,
                            ),
                            width: qtyW + 12,
                          ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  for (var i = 0; i < _lines.length; i++)
                    _row(i, narrow, qtyW, cell),
                  Container(
                    color: const Color(0xFFF1F4F8),
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 10,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 30),
                        cell(
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          width: narrow ? null : _gasW,
                        ),
                        for (var c = 0; c < cols; c++)
                          cell(
                            Text(
                              '${widget.lines.total(c)}',
                              key: Key('lineTotal$c'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: widget.colors[c],
                              ),
                            ),
                            width: qtyW + 12,
                          ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static const double _gasW = 210;

  Widget _row(
    int i,
    bool narrow,
    double qtyW,
    Widget Function(Widget, {double? width}) cell,
  ) {
    final l = _lines[i];
    final blank = l.gas == null;
    return FocusRow(
      stripe: i.isOdd ? const Color(0xFFF7F9FC) : null,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${i + 1}',
              style: const TextStyle(fontSize: 15, color: AppColors.muted),
            ),
          ),
          cell(
            GasPickField(
              key: Key('gasPick$i'),
              value: l.gas,
              focusNode: l.gasNode,
              autofocus: widget.autofocusFirst && i == 0,
              skip: {...widget.lines.usedGases, ...widget.skipGases},
              chooseOnly: widget.chooseOnly,
              pool: widget.lines.pool,
              hint: blank
                  ? (i == 0
                        ? (widget.chooseOnly ? 'Choose gas' : 'Type gas name')
                        : (widget.chooseOnly
                              ? 'Choose next gas'
                              : 'Next gas, or Enter to finish'))
                  : 'Type gas name',
              onPicked: (code) => _picked(i, code),
              onEnd: blank ? widget.onEndOfList : null,
              onClear: blank ? null : () => _remove(i),
            ),
            width: narrow ? null : _gasW,
          ),
          for (var c = 0; c < widget.lines.columns; c++)
            cell(
              Center(
                // The boxes are always there (also on the empty line), so
                // the cursor can jump in the moment a gas is picked and no
                // typed digit is lost. Tab skips them until then.
                child: Opacity(
                  opacity: blank ? 0.35 : 1,
                  child: QtyField(
                    key: Key('lineQty${i}_$c'),
                    controller: l.qty[c],
                    focusNode: l.qtyNodes[c]..skipTraversal = blank,
                    color: widget.colors[c],
                    fieldWidth: qtyW,
                    onChanged: () {
                      setState(() {});
                      widget.onChanged();
                    },
                    onEnter: () => _qtyEnter(i, c),
                    onUp: () => _up(i, c),
                    onDown: () => _down(i, c),
                  ),
                ),
              ),
              width: qtyW + 12,
            ),
          SizedBox(
            width: 40,
            child: blank
                ? null
                : ExcludeFocus(
                    child: IconButton(
                      key: Key('lineDel$i'),
                      tooltip: 'Remove this gas',
                      onPressed: () => _remove(i),
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
    );
  }
}
