import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'theme.dart';

/// Asks for the ARGON stock note of [date] and saves it. It goes on to the
/// next days until it is changed or cleared.
Future<void> editArgonStockRemark(
  BuildContext context,
  AppStore store,
  String date,
) async {
  final now = store.stockRemarkOn(date, kArgon);
  final r = await showDialog<String>(
    context: context,
    builder: (_) => _RemarkDialog(date: date, now: now),
  );
  if (r == null || r == (now?.text ?? '')) return;
  await store.setStockRemark(date, kArgon, r);
}

class _RemarkDialog extends StatefulWidget {
  final String date;
  final ({String text, String from})? now;
  const _RemarkDialog({required this.date, required this.now});

  @override
  State<_RemarkDialog> createState() => _RemarkDialogState();
}

class _RemarkDialogState extends State<_RemarkDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.now?.text ?? '',
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, _c.text.trim());

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final carried = now != null && now.from != widget.date;
    return AlertDialog(
      title: const Text('ARGON remark (stock)'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fmtLong(parseDayKey(widget.date)),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              carried
                  ? 'Written on ${fmtShort(parseDayKey(now.from))} and shown '
                        'on the next days. A change is shown from this day on.'
                  : 'E.g. how many of the ARGON are ARGON SPL. It stays on '
                        'the next days until you change it.',
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('argonRemarkField'),
              controller: _c,
              autofocus: true,
              maxLength: 120,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'e.g. SPL 4 full, 2 empty',
                counterText: '',
              ),
              onSubmitted: (_) => _done(),
            ),
          ],
        ),
      ),
      actions: [
        if (now != null)
          TextButton(
            key: const Key('argonRemarkClear'),
            onPressed: () => Navigator.pop(context, ''),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('argonRemarkSave'),
          onPressed: _done,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
