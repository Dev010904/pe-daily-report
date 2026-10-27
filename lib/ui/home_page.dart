import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/session.dart';
import '../data/store.dart';
import '../models/day_data.dart';
import '../util/dates.dart';
import 'account_page.dart';
import 'companies_tab.dart';
import 'companies_table.dart';
import 'company_page.dart';
import 'damaged_page.dart';
import 'dashboard_tab.dart';
import 'entry_page.dart';
import 'export_page.dart';
import 'filling_page.dart';
import 'install_page.dart';
import 'loan_page.dart';
import 'keys.dart';
import 'opening_page.dart';
import 'plants_tab.dart';
import 'settings_page.dart';
import 'share.dart';
import 'stock_tab.dart';
import 'supply_tab.dart';
import 'supply_table.dart';
import 'sync_badge.dart';
import 'theme.dart';
import 'vehicles_page.dart';
import 'widgets.dart';

enum Section { dashboard, supply, stock, companies, plants }

/// One line of the PC menu. [letter] null = a heading.
class _MenuItem {
  final String? letter;
  final String label;
  final IconData? icon;
  final VoidCallback? action;
  final Section? section;
  const _MenuItem(
    this.letter,
    this.label, {
    this.icon,
    this.action,
    this.section,
  });
  const _MenuItem.head(this.label)
    : letter = null,
      icon = null,
      action = null,
      section = null;
}

class HomePage extends StatefulWidget {
  final Session session;
  const HomePage({super.key, required this.session});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Phone tabs: Dashboard, Supply, Stock, Companies, Filling (opens on
  // Supply).
  late final TabController _tabs = TabController(
    length: 5,
    vsync: this,
    initialIndex: 1,
  );

  /// PC: the part shown on the right of the menu.
  Section _section = Section.dashboard;

  /// The app always opens on today's date.
  DateTime _date = today();
  DateTime _openedOn = today();

  final _rootFocus = FocusNode(debugLabel: 'home');
  final _menuFocus = FocusNode(debugLabel: 'menu');
  final _contentFocus = FocusNode(debugLabel: 'content');
  final _searchFocus = FocusNode(debugLabel: 'companySearch');
  final _stockScroll = ScrollController();
  bool _wide = false;

  AppStore get store => widget.session.store;
  String get _key => dayKey(_date);
  bool get _isToday => sameDay(_date, today());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    store.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _wide) _menuFocus.requestFocus();
      _remindPapers();
    });
  }

  bool _reminding = false;

  /// Once a day: vehicle papers to renew (expiring within 10 days, or
  /// expired). Only over this screen, never over a page being filled in.
  Future<void> _remindPapers() async {
    if (_reminding || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (store.paperAlerts().isEmpty) return;
    _reminding = true;
    try {
      final open = await showPaperReminder(context, store);
      if (open && mounted) _vehicles();
    } finally {
      _reminding = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_changed);
    _tabs.dispose();
    _stockScroll.dispose();
    for (final n in [_rootFocus, _menuFocus, _contentFocus, _searchFocus]) {
      n.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {});
    // Papers can arrive with the first sync after logging in.
    WidgetsBinding.instance.addPostFrameCallback((_) => _remindPapers());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the app was left open overnight, jump to the new day.
    if (state == AppLifecycleState.resumed && !sameDay(_openedOn, today())) {
      setState(() {
        _openedOn = today();
        _date = today();
      });
      _remindPapers();
    }
  }

  // ------------------------------------------------------------- actions

  void _go(DateTime d) {
    final day = dateOnly(d);
    if (day.isAfter(today())) return;
    setState(() => _date = day);
  }

  void _prevDay() => _go(_date.subtract(const Duration(days: 1)));
  void _nextDay() {
    if (!_isToday) _go(_date.add(const Duration(days: 1)));
  }

  void _goToday() => _go(today());

  Future<void> _gotoDate() async {
    final d = await askTypedDate(context, current: _date);
    if (d != null) _go(d);
  }

  Future<void> _pickDate() async {
    final d = await pickDay(
      context,
      selected: _date,
      hasData: (d) => store.hasData(dayKey(d)),
    );
    if (d != null) _go(d);
  }

  void _show(Section s) {
    setState(() {
      _section = s;
      _tabs.index = s.index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (s == Section.companies && _wide) {
        _searchFocus.requestFocus();
      } else if (_wide) {
        _contentFocus.requestFocus();
      }
    });
  }

  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    // Back from a page: keep the keyboard working on this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final f = FocusManager.instance.primaryFocus;
      final inside =
          f != null && (f == _rootFocus || f.ancestors.contains(_rootFocus));
      if (!inside || f == _rootFocus) {
        (_wide ? _contentFocus : _rootFocus).requestFocus();
      }
    });
  }

  void _newEntry() => _push(EntryPage(store: store, date: _key));
  void _openEntry(String date, String id, {bool focusChallan = false}) => _push(
    EntryPage(
      store: store,
      date: date,
      entryId: id,
      focusChallan: focusChallan,
    ),
  );
  void _filling() => _push(FillingPage(store: store, date: _key));
  void _opening() => _push(OpeningPage(store: store, date: _key));
  void _damaged() => _push(DamagedPage(store: store, date: _key));
  void _loan() => _push(LoanPage(store: store, date: _key));
  void _reports() => _push(ExportPage(store: store));
  void _settings() => _push(SettingsPage(session: widget.session));
  void _install() => _push(InstallPage(session: widget.session));
  void _account() => _push(AccountPage(session: widget.session));
  void _company(NamedItem c) =>
      _push(CompanyPage(store: store, companyId: c.id));
  void _plant(NamedItem p) => _push(PlantPage(store: store, plantId: p.id));
  void _vehicles() => _push(VehiclesPage(store: store));
  Future<void> _dayPdf() => sendDayPdf(context, store, [_key]);

  Future<void> _logout() async {
    final ok = await confirm(
      context,
      title: 'Log out?',
      message: 'You will need the username and password to come back in.',
      yes: 'Log out',
    );
    if (!ok || !mounted) return;
    // No message from before is left on the login screen.
    ScaffoldMessenger.of(context).clearSnackBars();
    await widget.session.auth.signOut();
  }

  late final Map<String, VoidCallback> _letters = {
    'd': () => _show(Section.dashboard),
    's': () => _show(Section.supply),
    'k': () => _show(Section.stock),
    'c': () => _show(Section.companies),
    'l': () => _show(Section.plants),
    'v': _vehicles,
    'n': _newEntry,
    'f': _filling,
    'o': _opening,
    'x': _damaged,
    'b': _loan,
    'p': _dayPdf,
    'r': _reports,
    't': _goToday,
    'g': _gotoDate,
    'e': _settings,
    'i': _install,
    'a': _account,
    'q': _logout,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!isPress(e)) return KeyEventResult.ignored;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape && _wide) {
      _menuFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (typingInTextField() || ctrlDown || altDown) {
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
      _prevDay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown) {
      _nextDay();
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final l = letterOf(e);
    final f = l == null ? null : _letters[l];
    if (f == null) return KeyEventResult.ignored;
    f();
    return KeyEventResult.handled;
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= kWideLayout;
          if (wide && !_wide) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_menuFocus.hasFocus && !_contentFocus.hasFocus) {
                _menuFocus.requestFocus();
              }
            });
          }
          _wide = wide;
          return wide ? _wideLayout() : _narrowLayout();
        },
      ),
    );
  }

  // ------------------------------------------------------------------ PC

  List<_MenuItem> get _menu => [
    const _MenuItem.head('VIEW'),
    _MenuItem(
      'D',
      'Dashboard',
      icon: Icons.dashboard,
      section: Section.dashboard,
      action: () => _show(Section.dashboard),
    ),
    _MenuItem(
      'S',
      'Supply  (day\'s entries)',
      icon: Icons.local_shipping,
      section: Section.supply,
      action: () => _show(Section.supply),
    ),
    _MenuItem(
      'K',
      'Stock',
      icon: Icons.inventory_2,
      section: Section.stock,
      action: () => _show(Section.stock),
    ),
    _MenuItem(
      'C',
      'Companies',
      icon: Icons.business,
      section: Section.companies,
      action: () => _show(Section.companies),
    ),
    _MenuItem(
      'L',
      'Filling Report (plants)',
      icon: Icons.factory,
      section: Section.plants,
      action: () => _show(Section.plants),
    ),
    _MenuItem(
      'V',
      'Vehicles (papers / renew)',
      icon: Icons.local_shipping_outlined,
      action: _vehicles,
    ),
    const _MenuItem.head('WORK'),
    _MenuItem('N', 'New Entry', icon: Icons.add_box, action: _newEntry),
    _MenuItem(
      'F',
      'Filling / Plant',
      icon: Icons.local_gas_station,
      action: _filling,
    ),
    _MenuItem(
      'X',
      'Damaged Cylinders',
      icon: Icons.broken_image_outlined,
      action: _damaged,
    ),
    _MenuItem(
      'B',
      'Loan Cylinders (from plant)',
      icon: Icons.swap_horiz,
      action: _loan,
    ),
    _MenuItem('O', 'Opening Stock', icon: Icons.edit_note, action: _opening),
    const _MenuItem.head('DATE'),
    _MenuItem('T', 'Today', icon: Icons.today, action: _goToday),
    _MenuItem('G', 'Go to Date', icon: Icons.calendar_month, action: _gotoDate),
    const _MenuItem.head('REPORTS'),
    _MenuItem(
      'P',
      'PDF of this day',
      icon: Icons.picture_as_pdf,
      action: _dayPdf,
    ),
    _MenuItem(
      'R',
      'Reports (month / year / dates)',
      icon: Icons.summarize,
      action: _reports,
    ),
    const _MenuItem.head('SETTINGS'),
    _MenuItem('E', 'Settings & Lists', icon: Icons.settings, action: _settings),
    _MenuItem(
      'I',
      'Install App',
      icon: Icons.install_desktop,
      action: _install,
    ),
    _MenuItem('A', 'Account', icon: Icons.manage_accounts, action: _account),
    _MenuItem('Q', 'Log out', icon: Icons.logout, action: _logout),
  ];

  Widget _wideLayout() {
    final menu = _menu;
    return Scaffold(
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 262,
                  color: const Color(0xFF13325A),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      KeyList(
                        key: const Key('menu'),
                        focusNode: _menuFocus,
                        itemCount: menu.length,
                        selectable: (i) => menu[i].letter != null,
                        onOpen: (i) => menu[i].action?.call(),
                        itemBuilder: (context, i, selected) =>
                            _menuRow(menu[i], selected),
                      ),
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'Press the letter to open.\n'
                          '← → = previous / next day\n'
                          'Esc = back to this menu',
                          style: TextStyle(
                            color: Color(0xFFB9C6DA),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.page,
                      border: _isToday
                          ? null
                          : Border.all(
                              color: const Color(0xFFE65100),
                              width: 4,
                            ),
                    ),
                    child: Column(
                      children: [
                        if (!_isToday) _oldDateStrip(),
                        Expanded(child: _content()),
                        KeyHints(_hints()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(_MenuItem m, bool selected) {
    if (m.letter == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          m.label,
          style: const TextStyle(
            color: Color(0xFF8FA6C7),
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      );
    }
    final current = m.section != null && m.section == _section;
    return Container(
      key: Key('menu_${m.letter}'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? kSelectBg
            : (current ? Colors.white.withValues(alpha: 0.12) : null),
        borderRadius: BorderRadius.circular(8),
        border: current ? Border.all(color: AppColors.gold, width: 1.2) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.navy : AppColors.gold,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              m.letter!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            m.icon,
            size: 19,
            color: selected ? AppColors.navy : const Color(0xFFDCE6F2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.navyDark : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final old = !_isToday;
    return Container(
      height: 66,
      color: old ? const Color(0xFFBF360C) : AppColors.navy,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const LogoBadge(size: 40),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Report',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Panchal Enterprise',
                style: TextStyle(color: Color(0xFFE9D9A6), fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Previous day (←)',
            onPressed: _prevDay,
            color: Colors.white,
            icon: const Icon(Icons.chevron_left, size: 30),
          ),
          InkWell(
            key: const Key('dateButton'),
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month,
                    color: old ? const Color(0xFFBF360C) : AppColors.navy,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fmtLong(_date),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: old ? const Color(0xFFBF360C) : AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: old ? const Color(0xFFBF360C) : AppColors.full,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      old ? 'OLD DATE' : 'TODAY',
                      key: const Key('dateStatus'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day (→)',
            onPressed: _isToday ? null : _nextDay,
            color: Colors.white,
            disabledColor: Colors.white.withValues(alpha: 0.3),
            icon: const Icon(Icons.chevron_right, size: 30),
          ),
          if (old) ...[
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _goToday,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFBF360C),
              ),
              child: const Text(
                'Back to Today (T)',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
          const Spacer(),
          SyncBadge(repo: widget.session.repo),
          const SizedBox(width: 8),
          Text(
            widget.session.auth.username ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _oldDateStrip() => Container(
    key: const Key('oldDateStrip'),
    width: double.infinity,
    color: const Color(0xFFFFE0B2),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFBF360C),
          size: 26,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'You are working on an OLD DATE: ${fmtLong(_date)} (${agoText(_date)}).  '
            'This is NOT today.  Press T to go back to today.',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3E2723),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _content() {
    switch (_section) {
      case Section.dashboard:
        return DashboardTab(
          key: const Key('dashboard'),
          store: store,
          date: _key,
          wide: true,
          focusNode: _contentFocus,
          onOpen: (r, {focusChallan = false}) =>
              _openEntry(r.date, r.entry.id, focusChallan: focusChallan),
        );
      case Section.supply:
        return SupplyTable(
          key: ValueKey('supply_$_key'),
          store: store,
          date: _key,
          focusNode: _contentFocus,
          onOpen: (id) => _openEntry(_key, id),
          onNew: _newEntry,
        );
      case Section.stock:
        return KeyScroll(
          controller: _stockScroll,
          child: Focus(
            focusNode: _contentFocus,
            child: StockTab(store: store, date: _key, scroll: _stockScroll),
          ),
        );
      case Section.companies:
        return CompaniesTable(
          store: store,
          date: _key,
          searchFocus: _searchFocus,
          listFocus: _contentFocus,
          onOpen: _company,
        );
      case Section.plants:
        return PlantsList(
          store: store,
          date: _key,
          wide: true,
          listFocus: _contentFocus,
          onOpen: _plant,
        );
    }
  }

  List<(String, String)> _hints() => switch (_section) {
    Section.dashboard => const [
      ('↑ ↓', 'Move'),
      ('Enter', 'Open entry'),
      ('Space', 'Mark bill made'),
      ('Tab', 'Next list'),
      ('Esc', 'Menu'),
    ],
    Section.supply => const [
      ('↑ ↓', 'Move'),
      ('Enter', 'Open'),
      ('Space', 'Bill made / not'),
      ('Del', 'Delete'),
      ('N', 'New entry'),
      ('← →', 'Day'),
      ('Esc', 'Menu'),
    ],
    Section.stock => const [
      ('↑ ↓', 'Scroll'),
      ('F', 'Filling / Plant'),
      ('X', 'Damaged'),
      ('B', 'Loan'),
      ('O', 'Opening stock'),
      ('← →', 'Day'),
      ('Esc', 'Menu'),
    ],
    Section.companies => const [
      ('Type', 'Search'),
      ('↓', 'List'),
      ('Enter', 'Open company'),
      ('Esc', 'Menu'),
    ],
    Section.plants => const [
      ('↑ ↓', 'Move'),
      ('Enter', 'Open plant'),
      ('← →', 'Day'),
      ('F', 'Filling / Plant'),
      ('Esc', 'Menu'),
    ],
  };

  // --------------------------------------------------------------- phone

  Widget _narrowLayout() {
    final entries = store.day(_key).entries;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          children: [
            LogoBadge(size: 38),
            SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Report',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Panchal Enterprise',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFE9D9A6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          SyncBadge(repo: widget.session.repo),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: TextButton.icon(
              key: const Key('shareDay'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: _dayPdf,
              icon: Icon(shareIcon),
              label: const Text(
                'PDF',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          IconButton(
            key: const Key('settings'),
            tooltip: 'Settings',
            onPressed: _settings,
            icon: const Icon(Icons.settings),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(118),
          child: Column(
            children: [
              _DateBar(
                date: _date,
                isToday: _isToday,
                onPrev: _prevDay,
                onNext: _isToday ? null : _nextDay,
                onPick: _pickDate,
                onToday: _goToday,
              ),
              TabBar(
                controller: _tabs,
                isScrollable: false,
                indicatorColor: AppColors.gold,
                indicatorWeight: 4,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFFB9C6DA),
                labelPadding: EdgeInsets.zero,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                tabs: [
                  _tab(store.paperAlerts().isEmpty ? 'Dashboard' : '⚠ Dashboard'),
                  _tab(
                    entries.isEmpty ? 'Supply' : 'Supply (${entries.length})',
                  ),
                  _tab('Stock'),
                  _tab('Companies'),
                  _tab('Filling'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          DashboardTab(
            store: store,
            date: _key,
            onOpen: (r, {focusChallan = false}) =>
                _openEntry(r.date, r.entry.id, focusChallan: focusChallan),
          ),
          PageWidth(
            child: SupplyTab(store: store, date: _key),
          ),
          PageWidth(
            child: StockTab(store: store, date: _key),
          ),
          PageWidth(
            child: CompaniesTab(store: store, date: _key),
          ),
          PageWidth(
            child: PlantsList(store: store, date: _key, onOpen: _plant),
          ),
        ],
      ),
      floatingActionButton: _tabs.index == 1
          ? FloatingActionButton.extended(
              key: const Key('addEntry'),
              onPressed: _newEntry,
              backgroundColor: AppColors.full,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add, size: 28),
              label: const Text(
                'Add Entry',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }
}

/// A phone tab whose name shrinks to fit (five tabs on a small screen).
Widget _tab(String text) => Tab(
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1)),
  ),
);

class _DateBar extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onPick;
  final VoidCallback onToday;

  const _DateBar({
    required this.date,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    const oldColor = Color(0xFFBF360C);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(
        children: [
          _arrow(Icons.chevron_left, onPrev, 'Previous day'),
          const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: isToday ? Colors.white : const Color(0xFFFFE0B2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isToday
                    ? BorderSide.none
                    : const BorderSide(color: Color(0xFFE65100), width: 3),
              ),
              child: InkWell(
                key: const Key('dateButton'),
                borderRadius: BorderRadius.circular(12),
                onTap: onPick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month,
                        color: isToday ? AppColors.navy : oldColor,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                fmtLong(date),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: isToday
                                      ? AppColors.navyDark
                                      : oldColor,
                                ),
                              ),
                            ),
                            Text(
                              isToday ? 'TODAY' : 'OLD DATE - not today!',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: isToday ? AppColors.full : oldColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isToday)
                        TextButton(
                          onPressed: onToday,
                          style: TextButton.styleFrom(
                            backgroundColor: oldColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text(
                            'Today',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _arrow(Icons.chevron_right, onNext, 'Next day'),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback? onTap, String tip) => SizedBox(
    width: 48,
    height: 56,
    child: IconButton(
      tooltip: tip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 30),
    ),
  );
}
