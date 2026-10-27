import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'company_page.dart';
import 'share.dart';
import 'loan_text.dart';
import 'theme.dart';
import 'widgets.dart';

/// Company-wise stock: how many cylinders of each gas every company has
/// (starting stock + supplied − empty received) on the chosen date. Full and
/// empty are not split: it is simply the cylinders at that company.
class CompaniesTab extends StatefulWidget {
  final AppStore store;
  final String date;
  const CompaniesTab({super.key, required this.store, required this.date});

  @override
  State<CompaniesTab> createState() => _CompaniesTabState();
}

class _CompaniesTabState extends State<CompaniesTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final bal = store.balancesOn(widget.date);
    final loans = store.stock(widget.date).loanAtCompanies;
    final q = _search.text.trim().toLowerCase();
    final list = [
      for (final c in store.companies)
        if ((c.active ||
                (bal[c.id]?.isNotEmpty ?? false) ||
                loans.containsKey(c.id)) &&
            (q.isEmpty || c.name.toLowerCase().contains(q)))
          c,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final totals = <String, int>{};
    for (final b in bal.values) {
      b.forEach((k, v) => totals[k] = (totals[k] ?? 0) + v);
    }
    final grand = totals.values.fold(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Card(
          color: AppColors.emptyBg,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cylinder stock at companies on ${fmtShort(parseDayKey(widget.date))}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${plural(grand, 'cylinder', 'cylinders')} in total',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                _GasChips(balance: totals),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('companySummaryPdf'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      sendCompanySummary(context, store, widget.date),
                  icon: Icon(shareIcon),
                  label: const Text('Send / Download PDF (all companies)'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('companySearch'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 17),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search company',
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'No companies yet.\nThey appear here when you add an entry.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.muted),
            ),
          ),
        for (final c in list) ...[
          Card(
            child: InkWell(
              key: Key('company_${c.id}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CompanyPage(store: store, companyId: c.id),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name + (c.active ? '' : ' (removed)'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _GasChips(balance: bal[c.id] ?? const {}),
                          if (loans[c.id] != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'LOAN  ${loanText(store, loans[c.id]!)}',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.loan,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        Text(
                          '${(bal[c.id] ?? const <String, int>{}).values.fold(0, (a, b) => a + b)}',
                          key: Key('companyTotal_${c.id}'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        const Text(
                          'cylinders',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _GasChips extends StatelessWidget {
  final Map<String, int> balance;
  const _GasChips({required this.balance});

  @override
  Widget build(BuildContext context) {
    final items = orderedQty(balance);
    if (items.isEmpty) {
      return const Text(
        'No cylinders with them',
        style: TextStyle(color: AppColors.muted, fontSize: 15),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in items)
          QtyChip(
            label: gasLabel(e.key),
            qty: e.value,
            color: e.value < 0 ? AppColors.danger : AppColors.navy,
          ),
      ],
    );
  }
}
