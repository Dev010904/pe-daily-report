import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../util/dates.dart';
import 'keys.dart';
import 'theme.dart';

/// Stops a save that would push any stock or company balance below zero
/// and explains why. Returns true when it is safe to save.
Future<bool> stockAllowsSave(
  BuildContext context,
  AppStore store,
  DayData d,
) async {
  final problems = store.problemsIfSaved(d);
  if (problems.isEmpty) return true;
  await showStockProblems(
    context,
    problems,
    sameDay: problems.first.date == d.date,
  );
  return false;
}

Future<void> showStockProblems(
  BuildContext context,
  List<StockProblem> problems, {
  required bool sameDay,
}) async {
  // Let a box that is just closing ("Save?") finish first.
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (ctx) => KeyDialog(
      onEnter: () => Navigator.pop(ctx),
      onEsc: () => Navigator.pop(ctx),
      child: AlertDialog(
        icon: const Icon(Icons.block, color: AppColors.danger, size: 40),
        title: const Text('Cannot go below zero'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sameDay || problems.first.date.isEmpty
                    ? 'Not saved, because:'
                    : 'This change makes the numbers wrong on '
                          '${fmtLong(parseDayKey(problems.first.date))}:',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final p in problems)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    p.message,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              const Text(
                'Please check the numbers.\n'
                '•  If filled cylinders came back from a plant, write them in '
                'Filling / Plant first.\n'
                '•  Empties must be written as "sent" to a plant before they '
                'can come back filled.\n'
                '•  If the real godown count is different, use "Correct Opening '
                'Stock" on the Stock tab.\n'
                '•  If a company had cylinders before the app, set its Starting '
                'Stock in the Companies tab.',
                style: TextStyle(fontSize: 14.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('stockProblemOk'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK (Enter)'),
          ),
        ],
      ),
    ),
  );
}
