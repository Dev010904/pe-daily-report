import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'entry_page.dart';
import 'loan_text.dart';
import 'theme.dart';
import 'widgets.dart';

/// The day's register: one card per company delivery.
class SupplyTab extends StatelessWidget {
  final AppStore store;
  final String date;
  const SupplyTab({super.key, required this.store, required this.date});

  Future<void> _toggleBill(BuildContext context, String id) async {
    final day = store.day(date);
    final e = day.entries.firstWhere((x) => x.id == id);
    if (!e.needsBill) {
      toast(context, '${e.company}: only empty received - no bill needed.');
      return;
    }
    e.billed = !e.billed;
    await store.saveDay(day);
    if (context.mounted) {
      toast(
        context,
        e.billed
            ? '${e.company}: bill made ✔'
            : '${e.company}: bill to be made later',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = store.day(date);
    if (day.entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          const SizedBox(height: 40),
          const Icon(
            Icons.local_shipping_outlined,
            size: 72,
            color: Color(0xFFB4BFD0),
          ),
          const SizedBox(height: 12),
          const Text(
            'No entries for this day',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap the green "Add Entry" button below\nto write a company\'s cylinders.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppColors.muted),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
      children: [
        for (var i = 0; i < day.entries.length; i++) ...[
          EntryCard(
            index: i + 1,
            entry: day.entries[i],
            loanFull: loanTexts(store, day.entries[i].loanFull),
            loanEmpty: loanTexts(store, day.entries[i].loanEmpty),
            remarks: remarksText(day.entries[i].remarks, store: store),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EntryPage(
                  store: store,
                  date: date,
                  entryId: day.entries[i].id,
                ),
              ),
            ),
            onToggleBill: () => _toggleBill(context, day.entries[i].id),
          ),
          const SizedBox(height: 10),
        ],
        DayTotals(day: day),
      ],
    );
  }
}

class EntryCard extends StatelessWidget {
  final int index;
  final Entry entry;
  final VoidCallback onTap;
  final VoidCallback onToggleBill;

  /// Loan cylinders in the entry ("ARGON 10 (ABC Plant)").
  final List<String> loanFull;
  final List<String> loanEmpty;

  /// Line remarks as text ("" when none).
  final String remarks;
  const EntryCard({
    super.key,
    required this.index,
    required this.entry,
    this.loanFull = const [],
    this.loanEmpty = const [],
    this.remarks = '',
    required this.onTap,
    required this.onToggleBill,
  });

  @override
  Widget build(BuildContext context) {
    final full = orderedQty(entry.full);
    final empty = orderedQty(entry.empty);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bill | Sr No. | Company | Challan
            Container(
              color: const Color(0xFFF6F8FB),
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
              child: Row(
                children: [
                  Tooltip(
                    message: !entry.needsBill
                        ? 'No bill needed (only empty received)'
                        : entry.billed
                        ? 'Bill made - tap to change'
                        : 'Bill not made - tap to change',
                    child: InkWell(
                      key: Key('bill_${entry.id}'),
                      customBorder: const CircleBorder(),
                      onTap: onToggleBill,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BillMark(
                              billed: entry.billed,
                              needed: entry.needsBill,
                              size: 28,
                            ),
                            const Text(
                              'BILL',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    color: AppColors.line,
                  ),
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: AppColors.navy,
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.company,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: entry.challan.isEmpty
                          ? const Color(0xFFFFE0B2)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: entry.challan.isEmpty
                            ? const Color(0xFFE65100)
                            : AppColors.line,
                      ),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Challan ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          TextSpan(
                            text: entry.challan.isEmpty
                                ? 'not written'
                                : entry.challan,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: entry.challan.isEmpty
                                  ? const Color(0xFFBF360C)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Full supplied || Empty received
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _QtyBlock(
                      title: 'FULL SUPPLIED',
                      color: AppColors.full,
                      items: full,
                      loan: loanFull,
                    ),
                  ),
                  Container(width: 4, color: AppColors.navy),
                  Expanded(
                    child: _QtyBlock(
                      title: 'EMPTY RECEIVED',
                      color: AppColors.empty,
                      items: empty,
                      loan: loanEmpty,
                    ),
                  ),
                ],
              ),
            ),
            if (remarks.isNotEmpty)
              Container(
                key: Key('remarks_${entry.id}'),
                width: double.infinity,
                color: const Color(0xFFF1F4F8),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Text(
                  'Remarks:  $remarks',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: AppColors.navy,
                  ),
                ),
              ),
            if (entry.cash.isNotEmpty)
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.amberBg,
                  border: Border(top: BorderSide(color: AppColors.amberLine)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CASH RECEIVED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.amber,
                      ),
                    ),
                    const SizedBox(height: 2),
                    for (final c in entry.cash)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${c.type}: ',
                              style: const TextStyle(fontSize: 15),
                            ),
                            TextSpan(
                              text: fmtMoney(c.amount),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: '  (${modeLabel(c.mode)})',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.amber,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
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

class _QtyBlock extends StatelessWidget {
  final String title;
  final Color color;
  final List<MapEntry<String, int>> items;

  /// Loan cylinders, shown apart in the loan colour.
  final List<String> loan;
  const _QtyBlock({
    required this.title,
    required this.color,
    required this.items,
    this.loan = const [],
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        if (items.isEmpty && loan.isEmpty)
          const Text(
            '—',
            style: TextStyle(fontSize: 16, color: AppColors.muted),
          )
        else if (items.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in items)
                QtyChip(label: gasLabel(e.key), qty: e.value, color: color),
            ],
          ),
        if (loan.isNotEmpty) ...[
          if (items.isNotEmpty) const SizedBox(height: 6),
          Text(
            'LOAN:  ${loan.join(',  ')}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.loan,
            ),
          ),
        ],
      ],
    ),
  );
}

class DayTotals extends StatelessWidget {
  final DayData day;
  const DayTotals({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final full = sumFull(day).values.fold(0, (a, b) => a + b);
    final empty = sumEmpty(day).values.fold(0, (a, b) => a + b);
    var cash = 0.0, gpay = 0.0;
    for (final e in day.entries) {
      for (final c in e.cash) {
        if (c.mode == kModeGpay) {
          gpay += c.amount;
        } else {
          cash += c.amount;
        }
      }
    }
    Widget stat(String label, String value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
    return Card(
      color: const Color(0xFFF9FAFC),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              "DAY TOTAL",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                stat('Full supplied', '$full', AppColors.full),
                stat('Empty received', '$empty', AppColors.empty),
              ],
            ),
            if (cash + gpay > 0) ...[
              const Divider(height: 20),
              Row(
                children: [
                  stat('Cash', fmtMoney(cash), AppColors.amber),
                  stat('GPay', fmtMoney(gpay), AppColors.amber),
                ],
              ),
            ],
            const Divider(height: 20),
            Row(
              children: [
                stat(
                  'Bills made',
                  '${day.entries.where((e) => e.needsBill && e.billed).length}',
                  AppColors.full,
                ),
                stat(
                  'Bills pending',
                  '${day.entries.where((e) => e.billPending).length}',
                  AppColors.danger,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
