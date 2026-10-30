import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/stock.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../models/purchase_order.dart';
import '../models/vehicle.dart';
import '../util/dates.dart';
import 'keys.dart';
import 'po_field.dart';
import 'purchase_orders_page.dart';
import 'theme.dart';
import 'vehicles_page.dart';
import 'widgets.dart';

/// An entry that needs attention, with its date and Sr No.
class AlertRow {
  final String date;
  final int sr;
  final Entry entry;
  const AlertRow(this.date, this.sr, this.entry);
}

/// Entries matching [test] on every saved day, newest day first.
List<AlertRow> alertRows(AppStore store, bool Function(Entry) test) {
  final out = <AlertRow>[];
  for (final d in store.savedDates.reversed) {
    final entries = store.day(d).entries;
    for (var i = 0; i < entries.length; i++) {
      if (test(entries[i])) out.add(AlertRow(d, i + 1, entries[i]));
    }
  }
  return out;
}

/// Bills still to be made. Entries with only empties received need no bill.
List<AlertRow> billsPending(AppStore s) => alertRows(s, (e) => e.billPending);
List<AlertRow> challanMissing(AppStore s) =>
    alertRows(s, (e) => e.challan.trim().isEmpty);

/// Dashboard: what still needs doing (bills not made, challan numbers not
/// written) and where cylinders are (empties at filling plants).
class DashboardTab extends StatelessWidget {
  final AppStore store;
  final String date;
  final bool wide;
  final FocusNode? focusNode;
  final void Function(AlertRow row, {bool focusChallan}) onOpen;

  const DashboardTab({
    super.key,
    required this.store,
    required this.date,
    required this.onOpen,
    this.wide = false,
    this.focusNode,
  });

  Future<void> _billMade(BuildContext context, AlertRow r) async {
    final day = store.day(r.date);
    final e = day.entries.firstWhere((x) => x.id == r.entry.id);
    if (!e.needsBill) return;
    e.billed = !e.billed;
    await store.saveDay(day);
    if (context.mounted) {
      toast(
        context,
        e.billed
            ? '${e.company} (${fmtDmy(parseDayKey(r.date))}): bill made ✔'
            : '${e.company}: bill to be made later',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bills = billsPending(store);
    final challans = challanMissing(store);
    final stock = store.stock(date);
    final plants = <(String, String, int)>[
      for (final r in stock.rows)
        for (final l in r.plantLines)
          if (l.close > 0) (store.plantName(l.plantId), r.gas.label, l.close),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final day = store.day(date);
    final full = sumFull(day).values.fold(0, (a, b) => a + b);
    final empty = sumEmpty(day).values.fold(0, (a, b) => a + b);
    final atPlants = plants.fold(0, (a, p) => a + p.$3);
    final isToday = sameDay(parseDayKey(date), today());

    final dmgToday = stock.damagedIn, repToday = stock.repairedOut;
    final dmgBy = orderedQty(stock.damagedCloseBy)
        .map((e) => '${gasLabel(e.key)} ${e.value}')
        .join(' · ');
    final loans =
        [
          for (final (gas, l) in stock.loanLines)
            if (l.toReturn != 0) (gas, l),
        ]..sort(
          (a, b) => store
              .plantName(a.$2.plantId)
              .toLowerCase()
              .compareTo(store.plantName(b.$2.plantId).toLowerCase()),
        );
    final loanOut = loans.fold(0, (a, x) => a + x.$2.toReturn);
    final hasVehicles = store.vehicles.isNotEmpty;
    final papers = store.paperAlerts();
    final urgent = papers.where((a) => a.daysLeft <= 0).length;
    final poAlerts = store.poAlerts();
    final hasPos = store.poLines().isNotEmpty;
    final poDone = poAlerts.where((l) => l.done).length;

    // Kept to a readable width on a big screen (nothing stretched far apart).
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Stat(
                  key: const Key('statBills'),
                  label: 'Bills not made',
                  value: '${bills.length}',
                  color: bills.isEmpty ? AppColors.full : AppColors.danger,
                  icon: Icons.receipt_long,
                  wide: wide,
                ),
                _Stat(
                  key: const Key('statChallan'),
                  label: 'Challan No. not written',
                  value: '${challans.length}',
                  color: challans.isEmpty
                      ? AppColors.full
                      : const Color(0xFFE65100),
                  icon: Icons.edit_note,
                  wide: wide,
                ),
                _Stat(
                  label: isToday
                      ? 'Entries today'
                      : 'Entries on ${fmtShort(parseDayKey(date))}',
                  value: '${day.entries.length}',
                  sub: 'Full $full  ·  Empty $empty',
                  color: AppColors.navy,
                  icon: Icons.local_shipping,
                  wide: wide,
                ),
                _Stat(
                  label: 'Empties at filling plants',
                  value: '$atPlants',
                  color: AppColors.amber,
                  icon: Icons.factory,
                  wide: wide,
                ),
                _Stat(
                  key: const Key('statDamaged'),
                  label: 'Damaged cylinders',
                  value: '${stock.damagedClose}',
                  sub: [
                    if (dmgBy.isNotEmpty) dmgBy,
                    if (dmgToday > 0) '+$dmgToday today',
                    if (repToday > 0) '−$repToday repaired',
                  ].join('  ·  '),
                  color: stock.damagedClose == 0
                      ? AppColors.muted
                      : const Color(0xFF8E1B1B),
                  icon: Icons.broken_image_outlined,
                  wide: wide,
                ),
                if (hasVehicles)
                  _Stat(
                    key: const Key('statPapers'),
                    label: 'Vehicle papers to renew',
                    value: '${papers.length}',
                    sub: urgent > 0
                        ? '$urgent URGENT (expired)'
                        : (papers.isEmpty
                              ? 'All papers valid'
                              : 'Within $kPaperAlertDays days'),
                    color: urgent > 0
                        ? AppColors.danger
                        : (papers.isEmpty
                              ? AppColors.full
                              : const Color(0xFFE65100)),
                    icon: Icons.local_shipping,
                    wide: wide,
                  ),
                if (hasPos)
                  _Stat(
                    key: const Key('statPo'),
                    label: 'Purchase orders supplied',
                    value: '$poDone',
                    sub: poAlerts.length > poDone
                        ? '${poAlerts.length - poDone} almost done'
                        : (poDone == 0 ? 'All POs have cylinders left' : null),
                    color: poDone > 0
                        ? AppColors.danger
                        : (poAlerts.isEmpty
                              ? AppColors.full
                              : const Color(0xFFE65100)),
                    icon: Icons.assignment_outlined,
                    wide: wide,
                  ),
                if (loans.isNotEmpty)
                  _Stat(
                    key: const Key('statLoan'),
                    label: 'Loan cylinders to give back',
                    value: '$loanOut',
                    sub:
                        '${{for (final x in loans) x.$2.plantId}.length} plant(s)',
                    color: AppColors.loan,
                    icon: Icons.swap_horiz,
                    wide: wide,
                  ),
              ],
            ),
            if (papers.isNotEmpty) ...[
              const SizedBox(height: 18),
              _Section(
                title: urgent > 0
                    ? 'VEHICLE PAPERS - URGENT RENEW'
                    : 'VEHICLE PAPERS TO RENEW',
                count: papers.length,
                color: urgent > 0 ? AppColors.danger : const Color(0xFFE65100),
                help:
                    'Shown every day from $kPaperAlertDays days before the last day. '
                    'Enter = open the vehicle and write the new dates (Renewed).',
                empty: '',
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: wide ? 760 : null,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: KeyList(
                        key: const Key('paperAlerts'),
                        itemCount: papers.length,
                        onOpen: (i) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VehiclePage(
                              store: store,
                              vehicleId: papers[i].vehicle.id,
                            ),
                          ),
                        ),
                        itemBuilder: (context, i, selected) => PaperAlertRow(
                          papers[i],
                          selected: selected,
                          index: i,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (poAlerts.isNotEmpty) ...[
              const SizedBox(height: 18),
              _Section(
                title: poDone == 0
                    ? 'PURCHASE ORDERS - ALMOST DONE'
                    : (poDone == poAlerts.length
                          ? 'PURCHASE ORDERS - FULLY SUPPLIED'
                          : 'PURCHASE ORDERS - FULLY / ALMOST SUPPLIED'),
                count: poAlerts.length,
                color: poDone > 0 ? AppColors.danger : const Color(0xFFE65100),
                help:
                    'Ask the company for a new PO. Enter = open its POs '
                    '(Settings > Companies) to add the new one or remove the old.',
                empty: '',
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: wide ? 760 : null,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: KeyList(
                        key: const Key('poAlerts'),
                        itemCount: poAlerts.length,
                        onOpen: (i) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PurchaseOrdersPage(
                              store: store,
                              companyId: poAlerts[i].po.companyId,
                            ),
                          ),
                        ),
                        itemBuilder: (context, i, selected) =>
                            _poRow(poAlerts[i], i, selected),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _Section(
              title: 'BILLS NOT MADE',
              count: bills.length,
              color: AppColors.danger,
              help: 'Enter = open the entry,  Space = mark bill made',
              empty: 'All bills are made ✔',
              child: _AlertList(
                key: const Key('billsList'),
                rows: bills,
                wide: wide,
                focusNode: focusNode,
                highlightBill: true,
                onOpen: (r) => onOpen(r),
                onSpace: (r) => _billMade(context, r),
              ),
            ),
            const SizedBox(height: 18),
            _Section(
              title: 'CHALLAN NO. NOT WRITTEN',
              count: challans.length,
              color: const Color(0xFFE65100),
              help: 'Enter = open the entry and write the challan number',
              empty: 'Every entry has a challan number ✔',
              child: _AlertList(
                key: const Key('challanList'),
                rows: challans,
                wide: wide,
                highlightChallan: true,
                onOpen: (r) => onOpen(r, focusChallan: true),
              ),
            ),
            if (loans.isNotEmpty) ...[
              const SizedBox(height: 18),
              _Section(
                title: 'LOAN CYLINDERS TO GIVE BACK',
                count: loanOut,
                color: AppColors.loan,
                help: 'Borrowed from plants, on ${fmtLong(parseDayKey(date))}',
                empty: '',
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: wide ? 760 : null,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < loans.length; i++)
                            _loanRow(loans[i].$1, loans[i].$2, i),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _Section(
              title: 'EMPTIES WAITING AT FILLING PLANTS',
              count: atPlants,
              color: AppColors.amber,
              help: 'On ${fmtLong(parseDayKey(date))}',
              empty: 'No empties waiting at any plant',
              child: plants.isEmpty
                  ? null
                  : Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: wide ? 560 : null,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < plants.length; i++)
                                Container(
                                  color: i.isOdd
                                      ? const Color(0xFFF7F9FC)
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.factory_outlined,
                                        color: AppColors.amber,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          plants[i].$1,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          plants[i].$2,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          '${plants[i].$3}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.amber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on DashboardTab {
  /// A PO gas that is (almost) all supplied.
  Widget _poRow(PoLine l, int i, bool selected) {
    final color = l.done ? AppColors.danger : const Color(0xFFE65100);
    return Container(
      key: Key('dashPo_${l.po.number}_${l.gas}'),
      decoration: BoxDecoration(
        color: selected
            ? kSelectBg
            : (i.isOdd ? const Color(0xFFF7F9FC) : null),
        border: Border(
          left: BorderSide(
            color: selected ? kSelectLine : Colors.transparent,
            width: 5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Icon(Icons.assignment_outlined, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${store.company(l.po.companyId)?.name ?? ''}  ·  PO ${l.po.number}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${gasLabel(l.gas)}: ${l.supplied} of ${l.ordered} supplied',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l.done ? poLeftText(l.left).toUpperCase() : poLeftText(l.left),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// One plant + gas of loan cylinders: still to give back, and where they are.
  Widget _loanRow(Gas gas, LoanLine l, int i) {
    final cos = store.loanCompaniesFor(gas.code, l.plantId, date);
    final where = [
      if (l.closeFull != 0) '${l.closeFull} full in godown',
      if (l.closeEmpty != 0) '${l.closeEmpty} empty in godown',
      for (final e in cos.entries) '${e.value} with ${e.key}',
    ].join(',  ');
    return Container(
      key: Key('dashLoan_${l.plantId}_${gas.code}'),
      color: i.isOdd ? const Color(0xFFF7F9FC) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.swap_horiz, color: AppColors.loan, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${store.plantName(l.plantId)}  ·  ${gas.label}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (where.isNotEmpty)
                  Text(
                    where,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${l.toReturn}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.loan,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color color;
  final IconData icon;
  final bool wide;

  const _Stat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.wide,
    this.sub,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: wide ? 230 : 165,
    child: Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            if (sub != null)
              Text(
                sub!,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final String help;
  final String empty;
  final Widget? child;

  const _Section({
    required this.title,
    required this.count,
    required this.color,
    required this.help,
    required this.empty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Container(width: 5, height: 22, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$title  ($count)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 13, top: 2),
        child: Text(
          help,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ),
      const SizedBox(height: 8),
      if (count == 0 || child == null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.fullBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            empty,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.full,
            ),
          ),
        )
      else
        child!,
    ],
  );
}

/// Table of entries that need attention. Up/Down move, Enter opens.
class _AlertList extends StatelessWidget {
  final List<AlertRow> rows;
  final bool wide;
  final FocusNode? focusNode;
  final bool highlightBill;
  final bool highlightChallan;
  final ValueChanged<AlertRow> onOpen;
  final ValueChanged<AlertRow>? onSpace;

  const _AlertList({
    super.key,
    required this.rows,
    required this.wide,
    required this.onOpen,
    this.focusNode,
    this.highlightBill = false,
    this.highlightChallan = false,
    this.onSpace,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle h() => const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: AppColors.navy,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Container(
              color: const Color(0xFFE3EBF5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text('Bill', style: h())),
                  SizedBox(width: 160, child: Text('Date', style: h())),
                  SizedBox(width: 36, child: Text('Sr', style: h())),
                  SizedBox(width: 220, child: Text('Company', style: h())),
                  SizedBox(width: 96, child: Text('Challan', style: h())),
                  SizedBox(
                    width: 180,
                    child: Text('Full supplied', style: h()),
                  ),
                  Flexible(
                    child: SizedBox(
                      width: 180,
                      child: Text('Empty received', style: h()),
                    ),
                  ),
                ],
              ),
            ),
          KeyList(
            focusNode: focusNode,
            itemCount: rows.length,
            onOpen: (i) => onOpen(rows[i]),
            onSpace: onSpace == null ? null : (i) => onSpace!(rows[i]),
            itemBuilder: (context, i, selected) => _row(rows[i], i, selected),
          ),
        ],
      ),
    );
  }

  String _q(Map<String, int> m) {
    final q = orderedQty(m);
    return q.isEmpty
        ? '-'
        : q.map((e) => '${gasLabel(e.key)} ${e.value}').join(', ');
  }

  /// "  + 10 loan" when the entry has loan cylinders.
  String _loan(int n) => n == 0 ? '' : '  + $n loan';

  Widget _row(AlertRow r, int i, bool selected) {
    final d = parseDayKey(r.date);
    final isToday = sameDay(d, today());
    final e = r.entry;
    final dateText = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: fmtDmy(d),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: isToday ? '  today' : '  ${agoText(d)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isToday ? AppColors.full : const Color(0xFFE65100),
            ),
          ),
        ],
      ),
    );
    final challan = e.challan.trim().isEmpty
        ? const Text(
            'missing',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE65100),
            ),
          )
        : Text(
            e.challan,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          );
    final bg = selected
        ? kSelectBg
        : (i.isOdd ? const Color(0xFFF7F9FC) : Colors.white);
    final border = Border(
      left: BorderSide(
        color: selected ? kSelectLine : Colors.transparent,
        width: 5,
      ),
      top: const BorderSide(color: Color(0xFFE6EAF0)),
    );
    if (!wide) {
      return Container(
        decoration: BoxDecoration(color: bg, border: border),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Row(
          children: [
            BillMark(billed: e.billed, needed: e.needsBill, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.company}   #${r.sr}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  dateText,
                  Text(
                    'Full: ${_q(e.full)}${_loan(e.totalLoanFull)}   '
                    'Empty: ${_q(e.empty)}${_loan(e.totalLoanEmpty)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            challan,
          ],
        ),
      );
    }
    return Container(
      key: Key('alert_${e.id}'),
      decoration: BoxDecoration(color: bg, border: border),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: BillMark(billed: e.billed, needed: e.needsBill, size: 22),
            ),
          ),
          SizedBox(width: 160, child: dateText),
          SizedBox(
            width: 36,
            child: Text(
              '${r.sr}',
              style: const TextStyle(fontSize: 15, color: AppColors.muted),
            ),
          ),
          SizedBox(
            width: 220,
            child: Text(
              e.company,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(width: 96, child: challan),
          SizedBox(
            width: 180,
            child: Text(
              '${_q(e.full)}${_loan(e.totalLoanFull)}',
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.full,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: SizedBox(
              width: 180,
              child: Text(
                '${_q(e.empty)}${_loan(e.totalLoanEmpty)}',
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.empty,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
