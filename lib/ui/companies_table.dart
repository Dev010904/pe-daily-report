import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';
import '../util/dates.dart';
import 'keys.dart';
import 'share.dart';
import 'loan_text.dart';
import 'theme.dart';

/// PC view of company-wise cylinder stock: type to search, Down arrow to
/// the list, Enter opens the company.
class CompaniesTable extends StatefulWidget {
  final AppStore store;
  final String date;
  final FocusNode searchFocus;
  final FocusNode listFocus;
  final ValueChanged<NamedItem> onOpen;

  const CompaniesTable({
    super.key,
    required this.store,
    required this.date,
    required this.searchFocus,
    required this.listFocus,
    required this.onOpen,
  });

  @override
  State<CompaniesTable> createState() => _CompaniesTableState();
}

class _CompaniesTableState extends State<CompaniesTable> {
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
    final list =
        [
          for (final c in store.companies)
            if ((c.active ||
                    (bal[c.id]?.isNotEmpty ?? false) ||
                    loans.containsKey(c.id)) &&
                (q.isEmpty || c.name.toLowerCase().contains(q)))
              c,
        ]..sort((a, b) {
          if (q.isNotEmpty) {
            final sa = a.name.toLowerCase().startsWith(q),
                sb = b.name.toLowerCase().startsWith(q);
            if (sa != sb) return sa ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    final totals = <String, int>{};
    for (final b in bal.values) {
      b.forEach((k, v) => totals[k] = (totals[k] ?? 0) + v);
    }
    int sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);
    String gases(Map<String, int> m) {
      final o = orderedQty(m);
      return o.isEmpty
          ? 'No cylinders'
          : o.map((e) => '${gasLabel(e.key)} ${e.value}').join(',   ');
    }

    const h = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    // Close columns: the count sits right after the company name.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Focus(
                    skipTraversal: true,
                    canRequestFocus: false,
                    onKeyEvent: (n, e) {
                      if (e is KeyDownEvent &&
                          e.logicalKey == LogicalKeyboardKey.arrowDown) {
                        widget.listFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      key: const Key('companySearch'),
                      controller: _search,
                      focusNode: widget.searchFocus,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (list.isNotEmpty) widget.onOpen(list.first);
                      },
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Type company name  (Down arrow = list, Enter = open first)',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: const Key('companySummaryPdf'),
                  onPressed: () =>
                      sendCompanySummary(context, store, widget.date),
                  icon: Icon(shareIcon),
                  label: const Text('PDF of all companies'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.emptyBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          'Cylinder stock at companies on ${fmtLong(parseDayKey(widget.date))}:   ',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.navy,
                      ),
                    ),
                    TextSpan(
                      text: '${sum(totals)} cylinders',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: '    ${gases(totals)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AppColors.navy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: const Row(
                      children: [
                        Flexible(
                          child: SizedBox(
                            width: 290,
                            child: Text('Company', style: h),
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            'Total',
                            textAlign: TextAlign.center,
                            style: h,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(child: Text('Cylinders with them', style: h)),
                      ],
                    ),
                  ),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No company found',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  KeyList(
                    focusNode: widget.listFocus,
                    itemCount: list.length,
                    onOpen: (i) => widget.onOpen(list[i]),
                    onUpFromTop: widget.searchFocus.requestFocus,
                    itemBuilder: (context, i, selected) {
                      final c = list[i];
                      final b = bal[c.id] ?? const <String, int>{};
                      return Container(
                        key: Key('companyRow_${c.id}'),
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
                          horizontal: 7,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: SizedBox(
                                width: 290,
                                child: Text(
                                  c.name + (c.active ? '' : ' (removed)'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(
                                '${sum(b)}',
                                key: Key('companyTotal_${c.id}'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: gases(b)),
                                    if (loans[c.id] != null)
                                      TextSpan(
                                        text:
                                            '\nLOAN  ${loanText(store, loans[c.id]!)}',
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.loan,
                                        ),
                                      ),
                                  ],
                                ),
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: b.isEmpty
                                      ? AppColors.muted
                                      : AppColors.navy,
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
          ],
        ),
      ),
    );
  }
}
