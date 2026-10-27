import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/ctrl_key.dart';
import '../util/dates.dart';
import 'theme.dart';

/// Keyboard use, Tally style: Enter moves on, Esc goes back, single letters
/// open menu items, Ctrl+A saves a form.

/// Screens wider than this get the PC layout (menu on the left).
const double kWideLayout = 900;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayout;

/// True while the cursor is in a text box (then letters type text instead
/// of opening menu items).
bool typingInTextField() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorStateOfType<EditableTextState>() != null;
}

bool get ctrlDown =>
    HardwareKeyboard.instance.isControlPressed ||
    HardwareKeyboard.instance.isMetaPressed ||
    browserCtrlHeld;
bool get altDown => HardwareKeyboard.instance.isAltPressed;

/// Moves the cursor to [n] right away (so the next key press lands there),
/// or straight after the next frame when that box is still being built.
void focusSoon(FocusNode n) {
  if (n.context != null) {
    n.requestFocus();
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (n.context != null) n.requestFocus();
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

bool isPress(KeyEvent e) => e is KeyDownEvent || e is KeyRepeatEvent;

// ------------------------------------------------------ message boxes

final List<_KeyDialogState> _openKeyDialogs = [];

/// True when [context] is on the page at the top (no message box above it).
bool onTopPage(BuildContext context) =>
    ModalRoute.of(context)?.isCurrent ?? true;

/// A key reached a page under an open message box: give the cursor back to
/// the box. Returns true when there was a box to give it to.
bool reclaimDialogFocus() {
  for (final d in _openKeyDialogs.reversed) {
    if (d.mounted && onTopPage(d.context)) {
      d._node.requestFocus();
      return true;
    }
  }
  return false;
}

/// A message box answered with the keyboard: Enter, Esc and letters are
/// handled by the box itself (not by whichever button has the cursor). It
/// takes the cursor when it opens and takes it back if the page below
/// grabs it while the boxes change (one closing, the next opening).
class KeyDialog extends StatefulWidget {
  final Widget child;
  final VoidCallback onEnter;
  final VoidCallback? onEsc;
  final Map<String, VoidCallback> letters;
  const KeyDialog({
    super.key,
    required this.child,
    required this.onEnter,
    this.onEsc,
    this.letters = const {},
  });

  @override
  State<KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<KeyDialog> {
  final _node = FocusNode(debugLabel: 'keyDialog');
  bool _done = false;

  /// Where the cursor was before the box opened (it goes back there).
  FocusNode? _before;

  @override
  void initState() {
    super.initState();
    _before = FocusManager.instance.primaryFocus;
    _openKeyDialogs.add(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _claim());
    // Again once the boxes have finished changing.
    for (final ms in const [120, 300]) {
      Future<void>.delayed(Duration(milliseconds: ms), _claim);
    }
  }

  void _claim() {
    if (!mounted || _done || !onTopPage(context)) return;
    final f = FocusManager.instance.primaryFocus;
    final inside = f != null && (f == _node || f.ancestors.contains(_node));
    if (!inside) _node.requestFocus();
  }

  @override
  void dispose() {
    _openKeyDialogs.remove(this);
    _node.dispose();
    super.dispose();
  }

  void _run(VoidCallback f) {
    if (_done) return;
    _done = true; // one answer only (no double Enter)
    _openKeyDialogs.remove(this);
    // Back to where the cursor was, right away (not left in the closing
    // box); what runs next may move it on from there.
    final b = _before;
    if (b != null && b.context != null && b.canRequestFocus) b.requestFocus();
    f();
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _run(widget.onEnter);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _run(widget.onEsc ?? () => Navigator.maybePop(context));
      return KeyEventResult.handled;
    }
    final l = letterOf(e);
    final f = l == null ? null : widget.letters[l];
    if (f == null) return KeyEventResult.ignored;
    _run(f);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    autofocus: true,
    onKeyEvent: _onKey,
    // The buttons are for the mouse; the keys are answered above.
    child: ExcludeFocus(child: widget.child),
  );
}

// ------------------------------------------------- moving between boxes

/// Form boxes that are not typing boxes (e.g. Bill made Y/N, Cash/GPay).
final Expando<bool> _choiceFields = Expando<bool>('choiceField');

/// Lets [n] take part in moving back / forward between boxes.
void markField(FocusNode n) => _choiceFields[n] = true;

EditableTextState? _editState(FocusNode n) {
  final ctx = n.context;
  if (ctx == null) return null;
  if (ctx is StatefulElement && ctx.state is EditableTextState) {
    return ctx.state as EditableTextState;
  }
  return ctx.findAncestorStateOfType<EditableTextState>();
}

bool _isField(FocusNode n) => _choiceFields[n] == true || _editState(n) != null;

/// Moves the cursor to the box before (or after) [from] on the same page,
/// in reading order (left to right, then the next line down). Buttons are
/// passed over. With [wholeRow] it leaves the row: the last box of the rows
/// above, or the first box of the rows below. Returns false when there is
/// no such box.
bool focusNeighbourField(
  FocusNode from, {
  required bool forward,
  bool wholeRow = false,
}) {
  final scope = from.nearestScope;
  if (scope == null) return false;
  final fields = scope.traversalDescendants
      .where((n) => n == from || (n.context != null && _isField(n)))
      .toList();
  // Reading order: rows from top to bottom (boxes less than 14 px apart in
  // height are on the same row), then left to right.
  fields.sort((a, b) {
    final ra = a.rect, rb = b.rect;
    if ((ra.center.dy - rb.center.dy).abs() > 14) {
      return ra.center.dy.compareTo(rb.center.dy);
    }
    return ra.left.compareTo(rb.left);
  });
  final i = fields.indexOf(from);
  if (i < 0) return false;
  var j = forward ? i + 1 : i - 1;
  if (wholeRow) {
    final y = from.rect.center.dy;
    bool sameRow(int k) => (fields[k].rect.center.dy - y).abs() <= 14;
    while (j >= 0 && j < fields.length && sameRow(j)) {
      j += forward ? 1 : -1;
    }
  }
  if (j < 0 || j >= fields.length) return false;
  final to = fields[j];
  to.requestFocus();
  final ctx = to.context;
  if (ctx != null && ctx.mounted) {
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 120),
    );
  }
  return true;
}

/// Up / Down arrows scroll a long page (Stock, a company's history) when no
/// box or list has the cursor; Home / End go to the top / bottom.
class KeyScroll extends StatelessWidget {
  final ScrollController controller;
  final Widget child;
  const KeyScroll({super.key, required this.controller, required this.child});

  KeyEventResult _onKey(KeyEvent e) {
    if (!isPress(e) || typingInTextField() || !controller.hasClients) {
      return KeyEventResult.ignored;
    }
    final p = controller.position;
    final k = e.logicalKey;
    double? to;
    if (k == LogicalKeyboardKey.arrowDown) {
      to = p.pixels + 90;
    } else if (k == LogicalKeyboardKey.arrowUp) {
      to = p.pixels - 90;
    } else if (k == LogicalKeyboardKey.home && e is KeyDownEvent) {
      to = p.minScrollExtent;
    } else if (k == LogicalKeyboardKey.end && e is KeyDownEvent) {
      to = p.maxScrollExtent;
    }
    if (to == null) return KeyEventResult.ignored;
    controller.animateTo(
      to.clamp(p.minScrollExtent, p.maxScrollExtent),
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (n, e) => _onKey(e),
    child: child,
  );
}

/// A box low on the screen (e.g. the gas or cash type box) moves up when it
/// gets the cursor, so its pop-up list has room below it.
void roomBelow(BuildContext context) {
  final s = Scrollable.maybeOf(context);
  final box = context.findRenderObject();
  final vp = s?.context.findRenderObject();
  if (s == null || box is! RenderBox || vp is! RenderBox || !box.attached) {
    return;
  }
  final y = box.localToGlobal(Offset.zero, ancestor: vp).dy;
  if (y > vp.size.height * 0.55) {
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 150),
    );
  }
}

/// Tally style, on every form: Backspace in an empty box or Up arrow goes
/// back to the box before; Down arrow goes on to the next one. (Boxes with
/// a pop-up list use Up / Down for the list first.)
KeyEventResult fieldNavKey(KeyEvent e) {
  if (e is KeyDownEvent) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null && ctx.mounted && !onTopPage(ctx) && reclaimDialogFocus()) {
      return KeyEventResult.handled;
    }
  }
  // Only a fresh press: holding Backspace must not run back through boxes
  // wiping them.
  if (e is! KeyDownEvent) return KeyEventResult.ignored;
  final k = e.logicalKey;
  final back = k == LogicalKeyboardKey.backspace;
  final up = k == LogicalKeyboardKey.arrowUp;
  final down = k == LogicalKeyboardKey.arrowDown;
  if (!back && !up && !down) return KeyEventResult.ignored;
  final kb = HardwareKeyboard.instance;
  if (kb.isShiftPressed || ctrlDown || altDown) return KeyEventResult.ignored;
  final f = FocusManager.instance.primaryFocus;
  if (f == null) return KeyEventResult.ignored;
  final edit = _editState(f);
  if (edit == null && _choiceFields[f] != true) return KeyEventResult.ignored;
  if (edit != null) {
    if (edit.widget.maxLines != 1) return KeyEventResult.ignored;
    if (back && edit.widget.controller.text.isNotEmpty) {
      return KeyEventResult.ignored;
    }
  }
  return focusNeighbourField(f, forward: down)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
}

/// Letter keys a..z as lower-case text, or null.
String? letterOf(KeyEvent e) {
  final label = e.logicalKey.keyLabel;
  if (label.length != 1) return null;
  final c = label.toLowerCase();
  return RegExp(r'^[a-z]$').hasMatch(c) ? c : null;
}

/// How many pop-up lists (company / gas / cash type) are open right now.
/// While one is open, Esc closes the list instead of leaving the page.
int openChoiceLists = 0;

KeyEventResult _escBack(BuildContext context, KeyEvent e) {
  if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
    return KeyEventResult.ignored;
  }
  if (openChoiceLists > 0) return KeyEventResult.ignored;
  if (!(ModalRoute.of(context)?.isCurrent ?? false)) {
    return KeyEventResult.ignored;
  }
  Navigator.maybePop(context);
  return KeyEventResult.handled;
}

/// Esc goes back from this page (an open pop-up list closes first; pages
/// with unsaved typing ask before leaving).
class EscBack extends StatelessWidget {
  final Widget child;
  final bool autofocus;
  const EscBack({super.key, required this.child, this.autofocus = true});

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: autofocus,
    skipTraversal: true,
    onKeyEvent: (n, e) => _escBack(context, e),
    child: child,
  );
}

/// Keyboard for a whole page: Esc goes back, Ctrl+A saves, Alt+letter and
/// plain letters run page actions (plain letters only when not typing in a
/// box).
class KeyPage extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSave;
  final Map<String, VoidCallback> letters;
  final Map<String, VoidCallback> altLetters;
  final bool autofocus;

  const KeyPage({
    super.key,
    required this.child,
    this.onSave,
    this.letters = const {},
    this.altLetters = const {},
    this.autofocus = false,
  });

  KeyEventResult _onKey(BuildContext context, KeyEvent e) {
    if (_escBack(context, e) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final l = letterOf(e);
    if (l == null) return KeyEventResult.ignored;
    if (ctrlDown && l == 'a' && onSave != null) {
      onSave!();
      return KeyEventResult.handled;
    }
    if (altDown && altLetters.containsKey(l)) {
      altLetters[l]!();
      return KeyEventResult.handled;
    }
    if (ctrlDown || altDown || typingInTextField()) {
      return KeyEventResult.ignored;
    }
    final f = letters[l];
    if (f == null) return KeyEventResult.ignored;
    f();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: autofocus,
    skipTraversal: true,
    onKeyEvent: (n, e) => _onKey(context, e),
    child: child,
  );
}

/// A list moved through with the arrow keys, like Tally: the selected row
/// is highlighted, Enter opens it, Space and Delete run extra actions.
class KeyList extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index, bool selected)
  itemBuilder;
  final ValueChanged<int>? onOpen;
  final ValueChanged<int>? onSpace;
  final ValueChanged<int>? onDelete;
  final bool Function(int index)? selectable;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Up arrow on the first row (e.g. back to a search box).
  final VoidCallback? onUpFromTop;

  const KeyList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onOpen,
    this.onSpace,
    this.onDelete,
    this.selectable,
    this.focusNode,
    this.autofocus = false,
    this.onUpFromTop,
  });

  @override
  State<KeyList> createState() => KeyListState();
}

class KeyListState extends State<KeyList> {
  FocusNode? _own;
  FocusNode get _node =>
      widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'KeyList'));
  int _sel = 0;
  bool _focused = false;
  final List<GlobalKey> _keys = [];

  int get selected => _sel;

  bool _ok(int i) => widget.selectable?.call(i) ?? true;

  @override
  void initState() {
    super.initState();
    _sel = _first();
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  int _first() {
    for (var i = 0; i < widget.itemCount; i++) {
      if (_ok(i)) return i;
    }
    return 0;
  }

  void select(int i) {
    if (i < 0 || i >= widget.itemCount || !_ok(i)) return;
    setState(() => _sel = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = i < _keys.length ? _keys[i].currentContext : null;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 80),
        );
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: const Duration(milliseconds: 80),
        );
      }
    });
  }

  void _move(int by) {
    var i = _sel + by;
    while (i >= 0 && i < widget.itemCount && !_ok(i)) {
      i += by;
    }
    if (i < 0) {
      widget.onUpFromTop?.call();
      return;
    }
    if (i >= widget.itemCount) return;
    select(i);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!isPress(e) || widget.itemCount == 0) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.home) {
      select(_first());
    } else if (k == LogicalKeyboardKey.end) {
      for (var i = widget.itemCount - 1; i >= 0; i--) {
        if (_ok(i)) {
          select(i);
          break;
        }
      }
    } else if (e is KeyDownEvent &&
        (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) &&
        widget.onOpen != null) {
      widget.onOpen!(_sel);
    } else if (e is KeyDownEvent &&
        k == LogicalKeyboardKey.space &&
        widget.onSpace != null) {
      widget.onSpace!(_sel);
    } else if (e is KeyDownEvent &&
        k == LogicalKeyboardKey.delete &&
        widget.onDelete != null) {
      widget.onDelete!(_sel);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_sel >= widget.itemCount) {
      _sel = widget.itemCount == 0 ? 0 : widget.itemCount - 1;
    }
    if (widget.itemCount > 0 && !_ok(_sel)) _sel = _first();
    while (_keys.length < widget.itemCount) {
      _keys.add(GlobalKey());
    }
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.itemCount; i++)
            KeyedSubtree(
              key: _keys[i],
              child: !_ok(i)
                  ? widget.itemBuilder(context, i, false)
                  : MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _node.requestFocus();
                          select(i);
                          widget.onOpen?.call(i);
                        },
                        child: widget.itemBuilder(
                          context,
                          i,
                          i == _sel && _focused,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Tally-style highlight colour for the selected row.
const Color kSelectBg = Color(0xFFFFE9A8);
const Color kSelectLine = Color(0xFFC9962B);

/// A key cap, e.g. [Enter].
class KeyCap extends StatelessWidget {
  final String text;
  final bool dark;
  const KeyCap(this.text, {super.key, this.dark = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: dark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: 0.5)
            : const Color(0xFFB0B9C6),
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: dark ? Colors.white : AppColors.navyDark,
      ),
    ),
  );
}

/// Bottom strip listing the keys of a screen: [Enter] Next  [Esc] Back ...
class KeyHints extends StatelessWidget {
  final List<(String, String)> keys;
  const KeyHints(this.keys, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: const BoxDecoration(
      color: Color(0xFFE8EDF4),
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final (k, label) in keys)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KeyCap(k),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF39424F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

/// "3 days ago" style text for a date that is not today.
String agoText(DateTime d) {
  final n = daysInclusive(d, today()) - 1;
  if (n == 0) return 'today';
  if (n == 1) return 'yesterday';
  if (n < 0) return 'in the future';
  return '$n days ago';
}

/// Big orange warning when the work is not for today.
class OldDateBanner extends StatelessWidget {
  final String date;
  const OldDateBanner({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final d = parseDayKey(date);
    if (sameDay(d, today())) return const SizedBox.shrink();
    return Container(
      key: const Key('oldDateBanner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE0B2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE65100), width: 2),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFE65100),
            size: 30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'OLD DATE:  ',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFBF360C),
                    ),
                  ),
                  TextSpan(
                    text: '${fmtLong(d)}  (${agoText(d)})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const TextSpan(text: '  -  this is NOT today\'s work.'),
                ],
              ),
              style: const TextStyle(fontSize: 16, color: Color(0xFF3E2723)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reads a typed date: "12", "12-10", "12-10-2026", "12/10/26".
/// Returns null when it is not a real date or is after today.
DateTime? parseTypedDate(String text, {DateTime? now, bool allowFuture = false}) {
  final base = now ?? today();
  final parts = text
      .trim()
      .split(RegExp(r'[\s./\-]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.length > 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null)) return null;
  final d = nums[0]!;
  final m = parts.length > 1 ? nums[1]! : base.month;
  var y = parts.length > 2 ? nums[2]! : base.year;
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final r = DateTime(y, m, d);
  if (r.month != m || r.day != d) return null;
  if (!allowFuture && r.isAfter(base)) return null;
  return r;
}

/// Tally-style "Go to date": type the date and press Enter. The date shown
/// is highlighted, so typing replaces it.
Future<DateTime?> askTypedDate(
  BuildContext context, {
  required DateTime current,
  String title = 'Go to date',
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _DateDialog(current: current, title: title),
  );
}

class _DateDialog extends StatefulWidget {
  final DateTime current;
  final String title;
  const _DateDialog({required this.current, this.title = 'Go to date'});

  @override
  State<_DateDialog> createState() => _DateDialogState();
}

class _DateDialogState extends State<_DateDialog> {
  late final _c = TextEditingController(text: fmtDmy(widget.current));
  final _node = FocusNode(debugLabel: 'typedDate');
  String? _error;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (_node.hasFocus) {
        _c.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _c.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _node.dispose();
    super.dispose();
  }

  void _go() {
    final d = parseTypedDate(_c.text);
    if (d == null) {
      setState(
        () => _error = 'Type a date like 12-10-2026 (not a future date)',
      );
      return;
    }
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('gotoDate'),
            controller: _c,
            focusNode: _node,
            autofocus: true,
            onTap: () => _c.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _c.text.length,
            ),
            keyboardType: TextInputType.datetime,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: 'dd-mm-yyyy',
              errorText: _error,
              helperText: 'Only the day (e.g. 12) also works for this month.',
            ),
            onSubmitted: (_) => _go(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel (Esc)'),
      ),
      FilledButton(onPressed: _go, child: const Text('Go (Enter)')),
    ],
  );
}
