import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'gas_lines.dart';
import 'keys.dart';

/// A typing box with a pop-up list under it (Tally's "List of ...").
///
/// Our own instead of Flutter's RawAutocomplete, which only remakes its
/// list when the text changes and ignores a choice equal to the one picked
/// last time: after going back to a box, "End of List" (or the same gas or
/// company again) did nothing and the cursor looked stuck. Here the list is
/// made fresh from the text on every build and Enter always takes the
/// highlighted choice.
///
/// Keys: typing filters, Up / Down / Page Up / Page Down move the highlight,
/// Enter takes it, Esc closes the list (Esc again leaves the page). With the
/// list closed, Up / Down go to the box before / after.
///
/// With [typeAhead] the box is choose-only (its field must be read-only):
/// nothing can be written, a letter only moves the highlight to the first
/// choice starting with it, Enter takes the highlighted one and Backspace
/// goes to the box before. Its list does not open by itself (it would
/// cover the page): a click / tap on the box, Down or a letter opens it; a
/// choice, Esc, or a click / tap anywhere else closes it. Enter works with
/// the list closed too (on an empty line it is "End of List").
class PickField<T extends Object> extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// The choices for the text typed so far (first one is highlighted).
  final List<T> Function(String text) options;
  final ValueChanged<T> onPicked;
  final String Function(T) label;
  final bool Function(T)? special;
  final String title;
  final double listWidth;

  /// Choose-only box: the index of the first choice matching the letters
  /// pressed so far (-1 = none).
  final int Function(String typed, List<T> options)? typeAhead;

  /// Builds the typing box; [submit] must be called on Enter.
  final Widget Function(BuildContext context, VoidCallback submit) field;

  const PickField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.options,
    required this.onPicked,
    required this.label,
    required this.title,
    required this.field,
    this.special,
    this.listWidth = 280,
    this.typeAhead,
  });

  @override
  State<PickField<T>> createState() => _PickFieldState<T>();
}

class _PickFieldState<T extends Object> extends State<PickField<T>> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _hi = ValueNotifier<int>(0);
  String _lastText = '';

  /// Esc closed the list; it opens again when typing or coming back.
  bool _dismissed = false;
  bool _picking = false;

  /// Choose-only: letters pressed in a row (forgotten after a second).
  String _typed = '';
  DateTime _typedAt = DateTime(2000);

  /// Choose-only: when the box was last clicked / tapped (that opens it).
  DateTime _tappedAt = DateTime(2000);

  bool get _chooseOnly => widget.typeAhead != null;

  static final _letterOrDigit = RegExp(r'^[a-zA-Z0-9]$');

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
    if (widget.focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void didUpdateWidget(PickField<T> old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _lastText = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    _hi.dispose();
    super.dispose();
  }

  List<T> get _opts => widget.options(widget.controller.text);

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      // Choose-only: the list stays closed until asked for (click / tap,
      // Down or a letter), so it never covers the page by itself.
      _dismissed =
          _chooseOnly &&
          DateTime.now().difference(_tappedAt).inMilliseconds > 800;
      _hi.value = 0;
    }
    _refresh();
  }

  void _onText() {
    final text = widget.controller.text;
    if (text == _lastText) return; // only the cursor moved
    _lastText = text;
    if (_picking) return;
    _dismissed = false;
    _hi.value = 0;
    _refresh();
  }

  /// Shows the list while the box has the cursor and there are choices.
  void _refresh() {
    if (!mounted) return;
    // Never in the middle of building the screen (e.g. the text was set
    // while the page was being rebuilt): do it right after.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      return;
    }
    final show = widget.focusNode.hasFocus && !_dismissed && _opts.isNotEmpty;
    if (show) {
      _portal.show();
    } else {
      _portal.hide();
    }
    setState(() {});
  }

  void _take(T o) {
    _picking = true;
    _portal.hide();
    try {
      widget.onPicked(o);
    } finally {
      _picking = false;
      _lastText = widget.controller.text;
    }
    if (mounted) setState(() {});
  }

  /// Enter: the highlighted choice (always, also the same one as before).
  void _submit() {
    if (!onTopPage(context)) {
      reclaimDialogFocus();
      return;
    }
    final opts = _opts;
    if (opts.isEmpty) return;
    _take(opts[_hi.value.clamp(0, opts.length - 1)]);
  }

  /// Choose-only: shows the list again (after Esc, or a click on the box).
  void _reopen() {
    if (_dismissed) {
      _dismissed = false;
      _refresh();
    }
  }

  KeyEventResult _chooseOnlyKey(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown && !_portal.isShowing) {
      // Down opens the list (Down again moves in it).
      _dismissed = false;
      _refresh();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
      // Nothing to erase here: Backspace goes to the box before.
      if (k == LogicalKeyboardKey.backspace) {
        focusNeighbourField(widget.focusNode, forward: false);
      }
      return KeyEventResult.handled;
    }
    if (ctrlDown || altDown) return KeyEventResult.ignored;
    final label = k.keyLabel;
    if (label.length != 1 || !_letterOrDigit.hasMatch(label)) {
      return KeyEventResult.ignored;
    }
    final now = DateTime.now();
    _typed = now.difference(_typedAt).inMilliseconds < 1000
        ? _typed + label.toLowerCase()
        : label.toLowerCase();
    _typedAt = now;
    final opts = _opts;
    var i = widget.typeAhead!(_typed, opts);
    if (i < 0 && _typed.length > 1) {
      _typed = label.toLowerCase();
      i = widget.typeAhead!(_typed, opts);
    }
    if (i >= 0) _hi.value = i;
    _reopen();
    // Handled either way, so no letter is ever written in the box.
    return KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.typeAhead != null &&
        _chooseOnlyKey(e) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    final k = e.logicalKey;
    final open = _portal.isShowing;
    final count = _opts.length;
    int? to;
    if (k == LogicalKeyboardKey.arrowDown) {
      to = _hi.value + 1;
    } else if (k == LogicalKeyboardKey.arrowUp) {
      to = _hi.value - 1;
    } else if (k == LogicalKeyboardKey.pageDown) {
      to = _hi.value + 8;
    } else if (k == LogicalKeyboardKey.pageUp) {
      to = _hi.value - 8;
    } else if (k == LogicalKeyboardKey.escape && e is KeyDownEvent && open) {
      _dismissed = true;
      _refresh();
      return KeyEventResult.handled;
    }
    if (to == null || !open || count == 0) return KeyEventResult.ignored;
    _hi.value = to.clamp(0, count - 1);
    return KeyEventResult.handled;
  }

  Widget _list(BuildContext overlayContext) {
    final opts = _opts;
    if (opts.isEmpty) return const SizedBox.shrink();
    // Below the box; above it when there is clearly more room there.
    var below = 340.0, above = 0.0;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached) {
      final screen = MediaQuery.sizeOf(overlayContext);
      final top = box.localToGlobal(Offset.zero).dy;
      below = screen.height - top - box.size.height - 10;
      above = top - 10;
    }
    final up = below < 170 && above > below;
    final maxHeight = (up ? above : below).clamp(90.0, 340.0);
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: up ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: up ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(0, up ? -2 : 2),
      child: Align(
        alignment: up ? Alignment.bottomLeft : Alignment.topLeft,
        // Taps in the list are not "outside" the typing box.
        child: TextFieldTapRegion(
          child: AutocompleteHighlightedOption(
            highlightIndexNotifier: _hi,
            child: ChoiceList<T>(
              options: opts,
              onSelected: _take,
              label: widget.label,
              special: widget.special,
              title: widget.title,
              width: widget.listWidth,
              maxHeight: maxHeight,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field(context, _submit);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _list,
      child: CompositedTransformTarget(
        link: _link,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: widget.typeAhead == null
              ? field
              // Choose-only: a click on the box shows the list again.
              : TextFieldTapRegion(
                  // Clicked / tapped anywhere else (or the page scrolled):
                  // close the list so nothing behind it is hidden.
                  onTapOutside: (_) {
                    if (!_dismissed) {
                      _dismissed = true;
                      _refresh();
                    }
                  },
                  child: Listener(
                    onPointerDown: (_) {
                      _tappedAt = DateTime.now();
                      _reopen();
                    },
                    child: field,
                  ),
                ),
        ),
      ),
    );
  }
}
