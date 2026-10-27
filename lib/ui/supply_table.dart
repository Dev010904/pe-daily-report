import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'keys.dart';
import 'stock_guard.dart';
import 'supply_tab.dart';
import 'loan_text.dart';
import 'theme.dart';
import 'widgets.dart';

/// PC view of the day's register, like the paper book:
/// Bill | Sr | Company | Full Supplied | Challan || Empty Received | Cash.
/// Up/Down move, Enter opens, Space = bill made / not, Delete removes.
class SupplyTable extends StatelessWidget {
  final AppStore store;
  final String date;
  final FocusNode? focusNode;
  final void Function(String entryId) onOpen;
  final VoidCallback onNew;

  const SupplyTable({
    super.key,
    required this.store,
    required this.date,
    required this.onOpen,
    required this.onNew,
    this.focusNode,
  });

  Future<void> _toggleBill(BuildContext context, Entry e) async {
    final day = store.day(date);
    final x = day.entries.firstWhere((y) => y.id == e.id);
    if (!x.needsBill) {
      toast(context, '${x.company}: only empty received - no bill needed.');
      return;
    }
    x.billed = !x.billed;
    await store.saveDay(day);
    if (context.mounted) {
      toast(
        context,
        x.billed
            ? '${x.company}: bill made ✔'
            : '${x.company}: bill to be made later',
      );
    }
  }

  Future<void> _delete(BuildContext context, Entry e) async {
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message: '${e.company} will be removed from this day.',
      yes: 'Delete',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final day = store.day(date);
    day.entries.removeWhere((x) => x.id == e.id);
    if (!await stockAllowsSave(context, store, day)) return;
    await store.saveDay(day);
  }

  static const double _companyW = 270;
  static const double _qtyW = 170;

  /// Our cylinders, and under them the loan ones in the loan colour.
  Widget _withLoan(String ours, List<String> loan, Color color) => Text.rich(
    TextSpan(
      children: [
        if (ours != '-' || loan.isEmpty)
          TextSpan(
            text: ours,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        if (loan.isNotEmpty)
          TextSpan(
            text: '${ours != '-' ? '\n' : ''}LOAN ${loan.join('\nLOAN ')}',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.loan,
            ),
          ),
      ],
    ),
  );

  String _q(Map<String, int> m) {
    final q = orderedQty(m);
    return q.isEmpty
        ? '-'
        : q.map((e) => '${gasLabel(e.key)} ${e.value}').join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final day = store.day(date);
    final hasCash = day.entries.any((e) => e.cash.isNotEmpty);
    const h = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    const emptiesLine = Border(
      left: BorderSide(color: AppColors.navy, width: 3),
    );
    if (day.entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const Icon(
            Icons.local_shipping_outlined,
            size: 64,
            color: Color(0xFFB4BFD0),
          ),
          const SizedBox(height: 10),
          const Text(
            'No entries for this day',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Press N for a new entry',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Center(
            child: FilledButton.icon(
              focusNode: focusNode,
              onPressed: onNew,
              style: FilledButton.styleFrom(backgroundColor: AppColors.full),
              icon: const Icon(Icons.add),
              label: const Text('New Entry (N)'),
            ),
          ),
        ],
      );
    }
    // Fixed, close columns (like the paper book), not spread over the
    // whole screen.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: hasCash ? 1030 : 840),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AppColors.navy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 46,
                          child: Text('Bill', style: h),
                        ),
                        const SizedBox(width: 40, child: Text('Sr', style: h)),
                        const Flexible(
                          child: SizedBox(
                            width: _companyW,
                            child: Text('Company Name', style: h),
                          ),
                        ),
                        const Flexible(
                          child: SizedBox(
                            width: _qtyW,
                            child: Text('Full Supplied', style: h),
                          ),
                        ),
                        const SizedBox(
                          width: 110,
                          child: Text('Challan No.', style: h),
                        ),
                        Flexible(
                          child: Container(
                            width: _qtyW + 8,
                            decoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Colors.white, width: 3),
                              ),
                            ),
                            padding: const EdgeInsets.only(left: 8),
                            child: const Text('Empty Received', style: h),
                          ),
                        ),
                        if (hasCash)
                          const SizedBox(
                            width: 170,
                            child: Text('Cash Received', style: h),
                          ),
                      ],
                    ),
                  ),
                  KeyList(
                    focusNode: focusNode,
                    itemCount: day.entries.length,
                    onOpen: (i) => onOpen(day.entries[i].id),
                    onSpace: (i) => _toggleBill(context, day.entries[i]),
                    onDelete: (i) => _delete(context, day.entries[i]),
                    itemBuilder: (context, i, selected) {
                      final e = day.entries[i];
                      final noChallan = e.challan.trim().isEmpty;
                      return Container(
                        key: Key('supplyRow_${e.id}'),
                        decoration: BoxDecoration(
                          color: selected
                              ? kSelectBg
                              : (i.isOdd
                                    ? const Color(0xFFF7F9FC)
                                    : Colors.white),
                          border: Border(
                            left: BorderSide(
                              color: selected
                                  ? kSelectLine
                                  : Colors.transparent,
                              width: 5,
                            ),
                            top: const BorderSide(color: Color(0xFFE6EAF0)),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 46,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: InkWell(
                                  key: Key('bill_${e.id}'),
                                  onTap: () => _toggleBill(context, e),
                                  child: BillMark(
                                    billed: e.billed,
                                    needed: e.needsBill,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            Flexible(
                              child: SizedBox(
                                width: _companyW,
                                child: Text(
                                  e.company,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              child: SizedBox(
                                width: _qtyW,
                                child: _withLoan(
                                  _q(e.full),
                                  loanTexts(store, e.loanFull),
                                  AppColors.full,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: noChallan
                                  ? Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE0B2),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Text(
                                          'not written',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFBF360C),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Text(
                                      e.challan,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            Flexible(
                              child: Container(
                                width: _qtyW + 8,
                                decoration: const BoxDecoration(
                                  border: emptiesLine,
                                ),
                                padding: const EdgeInsets.only(left: 8),
                                child: _withLoan(
                                  _q(e.empty),
                                  loanTexts(store, e.loanEmpty),
                                  AppColors.empty,
                                ),
                              ),
                            ),
                            if (hasCash)
                              SizedBox(
                                width: 170,
                                child: Text(
                                  e.cash
                                      .map(
                                        (c) =>
                                            '${c.type} ${fmtMoney(c.amount)} (${modeLabel(c.mode)})',
                                      )
                                      .join('\n'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.amber,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DayTotals(day: day),
          ],
        ),
      ),
    );
  }
}
