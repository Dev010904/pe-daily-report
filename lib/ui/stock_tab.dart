import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/stock.dart';
import '../models/gas.dart';
import 'damaged_page.dart';
import 'filling_page.dart';
import 'loan_page.dart';
import 'opening_page.dart';
import 'theme.dart';

/// Daily stock table:
/// Gas | Opening Full | Filling | Sales | Closing Full | Empty (Godown)
class StockTab extends StatelessWidget {
  final AppStore store;
  final String date;

  /// PC: lets the arrow keys scroll the page.
  final ScrollController? scroll;
  const StockTab({
    super.key,
    required this.store,
    required this.date,
    this.scroll,
  });

  void _openFilling(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FillingPage(store: store, date: date),
    ),
  );

  void _openOpening(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => OpeningPage(store: store, date: date),
    ),
  );

  void _openLoan(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => LoanPage(store: store, date: date),
    ),
  );

  void _openDamaged(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DamagedPage(store: store, date: date),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final stock = store.stock(date);
    final day = store.day(date);
    final firstDay =
        !stock.hasPrevious && day.openFull.isEmpty && day.openEmpty.isEmpty;
    final anyPlant = stock.rows.any((r) => r.plantLines.isNotEmpty);

    // Kept narrow on a big screen so each number stays close to its gas.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 32),
          children: [
            if (firstDay)
              Card(
                color: AppColors.amberBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.amberLine),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Starting for the first time?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter the full and empty cylinders you have in stock '
                        'now. After this, every day\'s opening stock will '
                        'come automatically from the day before.',
                        style: TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: const Key('setOpening'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.amber,
                        ),
                        onPressed: () => _openOpening(context),
                        icon: const Icon(Icons.inventory_2),
                        label: const Text('Enter Opening Stock'),
                      ),
                    ],
                  ),
                ),
              ),
            if (firstDay) const SizedBox(height: 10),
            _StockTable(
              store: store,
              stock: stock,
              onFill: () => _openFilling(context),
              onOpening: () => _openOpening(context),
              onDamaged: () => _openDamaged(context),
              onLoan: () => _openLoan(context),
            ),
            const SizedBox(height: 8),
            _Legend(showPlant: anyPlant, showLoan: stock.hasLoans),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('editFilling'),
              onPressed: () => _openFilling(context),
              icon: const Icon(Icons.local_gas_station),
              label: const Text('Enter Filling / Plant'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('editDamaged'),
              onPressed: () => _openDamaged(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              icon: const Icon(Icons.broken_image_outlined),
              label: const Text('Damaged Cylinders'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('editLoan'),
              onPressed: () => _openLoan(context),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.loan),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Loan Cylinders (from plant)'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('editOpening'),
              onPressed: () => _openOpening(context),
              icon: const Icon(Icons.edit_note),
              label: const Text('Correct Opening Stock'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final bool showPlant;
  final bool showLoan;
  const _Legend({required this.showPlant, this.showLoan = false});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, color: AppColors.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Closing Full = Opening + Filling − Sales', style: style),
          const Text(
            'Empty (Godown) = Yesterday\'s empty − Sent to plant + Empty received today',
            style: style,
          ),
          if (showPlant)
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Yellow',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.amber,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: ' = empties sent to a plant.  At plant = start + sent − filled back',
                    style: style,
                  ),
                ],
              ),
            ),
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Damaged',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text:
                      ' = start + damaged today − repaired; each keeps its gas (by gas on the right). '
                      'Red under a gas = cylinders of that gas damaged / repaired today',
                  style: style,
                ),
              ],
            ),
          ),
          if (showLoan)
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Purple ↳ loan',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.loan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' = cylinders borrowed from a plant (not ours): full in godown '
                        'under Closing Full, empty in godown under Empty',
                    style: style,
                  ),
                ],
              ),
            ),
          const Text('Tap a number to change it', style: style),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- table

const double _gasW = 78;
const double _headH = 50;
const double _rowH = 56;
const double _plantH = 42;
const double _loanH = 46;
// Base widths; the whole table is scaled to fit the screen exactly.
const List<double> _minW = [52, 50, 46, 54, 100];

class _StockTable extends StatelessWidget {
  final AppStore store;
  final StockDay stock;
  final VoidCallback onFill;
  final VoidCallback onOpening;
  final VoidCallback onDamaged;
  final VoidCallback onLoan;

  const _StockTable({
    required this.store,
    required this.stock,
    required this.onFill,
    required this.onOpening,
    required this.onDamaged,
    required this.onLoan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) {
          // Fit the full table to the screen so no column is hidden.
          final f = c.maxWidth / (_gasW + _minW.fold(0.0, (a, b) => a + b));
          final gasW = _gasW * f;
          final w = [for (final x in _minW) x * f];

          final fixed = <Widget>[_gasHead()];
          final moving = <Widget>[_head(w)];
          for (final r in stock.rows) {
            fixed.add(_gasCell(r));
            moving.add(_row(r, w));
            for (final l in r.plantLines) {
              fixed.add(_plantGasCell());
              moving.add(InkWell(onTap: onFill, child: _plantRow(r, l, w)));
            }
            for (final l in r.loanLines) {
              fixed.add(_loanGasCell());
              moving.add(InkWell(onTap: onLoan, child: _loanRow(l, w)));
            }
          }
          // Damaged cylinders (all gases) always last, so the total and
          // what was damaged today are always in sight.
          fixed.add(_damagedGasCell());
          moving.add(InkWell(onTap: onDamaged, child: _damagedRow(w)));

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: gasW,
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppColors.line, width: 1.5),
                  ),
                ),
                child: Column(children: fixed),
              ),
              Expanded(child: Column(children: moving)),
            ],
          );
        },
      ),
    );
  }

  static const _headStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    height: 1.15,
  );

  Widget _gasHead() => Container(
    height: _headH,
    color: AppColors.navy,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.only(left: 10),
    child: const Text('Gas', style: _headStyle),
  );

  Widget _head(List<double> w) {
    const labels = [
      'Opening\nFull',
      'Filling',
      'Sales',
      'Closing\nFull',
      'Empty\n(Godown)',
    ];
    return Container(
      height: _headH,
      color: AppColors.navy,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            SizedBox(
              width: w[i],
              child: _fit(
                Text(labels[i], textAlign: TextAlign.center, style: _headStyle),
              ),
            ),
        ],
      ),
    );
  }

  Color? _groupColor(StockRow r) => switch (r.gas.group) {
    'AR' => AppColors.groupAr,
    'N2' => AppColors.groupN2,
    _ => null,
  };

  Widget _gasCell(StockRow r) {
    final g = _groupColor(r);
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: g?.withValues(alpha: 0.06),
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Container(width: 4, color: g ?? Colors.transparent),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                r.gas.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: g ?? const Color(0xFF1B2330),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _plantGasCell() => Container(
    height: _plantH,
    decoration: const BoxDecoration(
      color: AppColors.amberBg,
      border: Border(top: BorderSide(color: AppColors.amberLine)),
    ),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 6),
    child: const Text(
      '↳ at plant',
      style: TextStyle(
        fontSize: 12.5,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w700,
        color: AppColors.amber,
      ),
    ),
  );

  static final Color _dmgBg = AppColors.danger.withValues(alpha: 0.06);
  static final Color _dmgLine = AppColors.danger.withValues(alpha: 0.4);

  Widget _damagedGasCell() => Container(
    key: const Key('damagedRowName'),
    height: _rowH,
    decoration: BoxDecoration(
      color: _dmgBg,
      border: Border(top: BorderSide(color: _dmgLine, width: 1.5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.centerLeft,
    child: _fitLeft(
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Damaged',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.danger,
            ),
          ),
          Text(
            'all gases',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );

  /// Start | + damaged today | − repaired | = total | which gases today.
  Widget _damagedRow(List<double> w) {
    final s = stock;
    final today = [
      for (final r in s.rows)
        if (r.damagedEmpty + r.damagedFull > 0)
          '${r.gas.label} ${r.damagedEmpty + r.damagedFull}',
    ];
    final rep = [
      for (final e in orderedQty(s.repairedToday))
        '${gasLabel(e.key)} ${e.value}',
    ];
    // Each damaged cylinder keeps its gas: what the total is made of.
    final byGas = [
      for (final e in orderedQty(s.damagedCloseBy))
        '${gasLabel(e.key)} ${e.value}',
    ];
    const muted = Color(0xFFADB5C2);
    return Container(
      key: const Key('damagedRow'),
      height: _rowH,
      decoration: BoxDecoration(
        color: _dmgBg,
        border: Border(top: BorderSide(color: _dmgLine, width: 1.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: w[0],
            child: _captioned(
              '${s.damagedOpen}',
              'start',
              s.damagedOpen < 0 ? AppColors.danger : const Color(0xFF1B2330),
              key: const Key('damagedStart'),
              edited: s.damagedOpenEdited,
            ),
          ),
          SizedBox(
            width: w[1],
            child: _captioned(
              s.damagedIn > 0 ? '+${s.damagedIn}' : '0',
              'today',
              s.damagedIn > 0 ? AppColors.danger : muted,
              key: const Key('damagedTodayCount'),
            ),
          ),
          SizedBox(
            width: w[2],
            child: _captioned(
              s.repairedOut > 0 ? '−${s.repairedOut}' : '0',
              'repaired',
              s.repairedOut > 0 ? AppColors.empty : muted,
              key: const Key('damagedRepaired'),
            ),
          ),
          Container(
            width: w[3],
            height: double.infinity,
            color: AppColors.danger.withValues(alpha: 0.1),
            child: _captioned(
              '${s.damagedClose}',
              'total',
              AppColors.danger,
              key: const Key('damagedTotal'),
              big: true,
            ),
          ),
          SizedBox(
            width: w[4],
            child: today.isEmpty && rep.isEmpty && byGas.isEmpty
                ? const SizedBox()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (byGas.isNotEmpty)
                            Text(
                              byGas.join(',  '),
                              key: const Key('damagedByGas'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: AppColors.danger,
                              ),
                            ),
                          if (today.isNotEmpty)
                            Text(
                              'today: ${today.join(',  ')}',
                              key: const Key('damagedTodayGases'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                              ),
                            ),
                          if (rep.isNotEmpty)
                            Text(
                              'repaired: ${rep.join(',  ')}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.empty,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// A number with a small word under it ("+2" / "today").
  Widget _captioned(
    String value,
    String caption,
    Color color, {
    Key? key,
    bool edited = false,
    bool big = false,
  }) => Center(
    child: _fit(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                key: key,
                style: TextStyle(
                  fontSize: big ? 19 : 17,
                  fontWeight: big ? FontWeight.w900 : FontWeight.w800,
                  color: color,
                ),
              ),
              if (edited)
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Icon(Icons.edit, size: 12, color: AppColors.amber),
                ),
            ],
          ),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.muted,
              height: 1,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fitLeft(Widget child) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );

  Widget _loanGasCell() => Container(
    height: _loanH,
    decoration: BoxDecoration(
      color: AppColors.loanBg,
      border: Border(
        top: BorderSide(color: AppColors.loan.withValues(alpha: 0.35)),
      ),
    ),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 6),
    child: const FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '↳ loan',
        style: TextStyle(
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w800,
          color: AppColors.loan,
        ),
      ),
    ),
  );

  /// Loan cylinders of one gas from one plant: full in godown (in the
  /// Closing Full column), empty in godown (in the Empty column), and how
  /// many are with companies / still to give back.
  Widget _loanRow(LoanLine l, List<double> w) {
    final nameW = w[0] + w[1] + w[2];
    TextStyle num(bool bad) => TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w900,
      color: bad ? AppColors.danger : AppColors.loan,
    );
    return Container(
      key: Key('loanRow_${l.plantId}'),
      height: _loanH,
      decoration: BoxDecoration(
        color: AppColors.loanBg,
        border: Border(
          top: BorderSide(color: AppColors.loan.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: nameW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _fitLeft(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Loan · ${store.plantName(l.plantId)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.loan,
                      ),
                    ),
                    Text(
                      'with companies ${l.atCompanies}  ·  to give back ${l.toReturn}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6A3A78),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: w[3],
            child: Center(
              child: _fit(
                Text(
                  l.fullCalcText(),
                  key: Key('loanFull_${l.plantId}'),
                  style: num(l.closeFull < 0),
                ),
              ),
            ),
          ),
          SizedBox(
            width: w[4],
            child: Center(
              child: _fit(
                Text(
                  l.emptyCalcText(),
                  key: Key('loanEmpty_${l.plantId}'),
                  style: num(l.closeEmpty < 0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(StockRow r, List<double> w) {
    final g = _groupColor(r);
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: g?.withValues(alpha: 0.06),
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          _tap(w[0], onOpening, _num(r.openFull, edited: r.openFullEdited)),
          _tap(w[1], onFill, _fillCell(r)),
          SizedBox(
            width: w[2],
            child: Center(
              child: _fit(
                Text(
                  '${r.sales}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: r.sales > 0
                        ? const Color(0xFF1B2330)
                        : const Color(0xFFADB5C2),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: w[3],
            height: double.infinity,
            color: AppColors.fullBg,
            alignment: Alignment.center,
            child: _fullCell(r),
          ),
          _tap(w[4], r.gas.isDA ? onFill : onOpening, _emptyCell(r)),
        ],
      ),
    );
  }

  /// "+11 +3" over "= +14" when filled in more than one go.
  Widget _fillCell(StockRow r) {
    final total = Text(
      r.fill > 0
          ? (r.fillSteps.length > 1 ? '= +${r.fill}' : '+${r.fill}')
          : '${r.fill}',
      key: Key('fill_${r.gas.code}'),
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: r.fill > 0 ? AppColors.full : const Color(0xFFADB5C2),
      ),
    );
    final steps = r.fillStepsText;
    if (steps.isEmpty) return _fit(total);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _fit(
          Text(
            steps,
            key: Key('fillSteps_${r.gas.code}'),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5363),
            ),
          ),
        ),
        _fit(total),
      ],
    );
  }

  /// Closing full, with "−2 damaged" under it when full ones were damaged.
  Widget _fullCell(StockRow r) {
    final n = Text(
      '${r.closeFull}',
      style: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w900,
        color: r.closeFull < 0 ? AppColors.danger : AppColors.full,
      ),
    );
    if (r.damagedFull == 0) return _fit(n);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _fit(n),
        _fit(
          Text(
            '−${r.damagedFull} damaged',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.danger,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyCell(StockRow r) {
    final parts = r.emptyCalc();
    final total = Text(
      parts.length == 1 ? '${r.closeGodown}' : '= ${r.closeGodown}',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: r.closeGodown < 0 ? AppColors.danger : AppColors.empty,
      ),
    );
    if (parts.length == 1) return _fit(total);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < parts.length; i++)
                  TextSpan(
                    text: (i == 0 ? '' : ' ') + parts[i].text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: parts[i].damaged
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: parts[i].plant
                          ? AppColors.amber
                          : parts[i].damaged
                          ? AppColors.danger
                          : const Color(0xFF4A5363),
                      backgroundColor: parts[i].plant
                          ? AppColors.amberBg
                          : parts[i].damaged
                          ? const Color(0xFFFDECEC)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        _fit(total),
      ],
    );
  }

  Widget _plantRow(StockRow r, PlantLine l, List<double> w) {
    final nameW = w[0] + w[1] + w[2] + w[3];
    return Container(
      height: _plantH,
      decoration: const BoxDecoration(
        color: AppColors.amberBg,
        border: Border(top: BorderSide(color: AppColors.amberLine)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: nameW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.factory_outlined,
                    size: 18,
                    color: AppColors.amber,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      store.plantName(l.plantId),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B4A00),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: w[4],
            child: Center(
              child: _fit(
                Text(
                  l.calcText(),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: l.close < 0 ? AppColors.danger : AppColors.amber,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(int v, {bool edited = false}) => _fit(
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$v',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: v < 0 ? AppColors.danger : const Color(0xFF1B2330),
          ),
        ),
        if (edited)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.edit, size: 12, color: AppColors.amber),
          ),
      ],
    ),
  );

  /// Shrinks a cell's text a little when the phone is narrow.
  Widget _fit(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: FittedBox(fit: BoxFit.scaleDown, child: child),
  );

  Widget _tap(double width, VoidCallback onTap, Widget child) => SizedBox(
    width: width,
    height: double.infinity,
    child: InkWell(
      onTap: onTap,
      child: Center(child: child),
    ),
  );
}
