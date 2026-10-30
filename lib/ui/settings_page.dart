import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/session.dart';
import '../data/store.dart';
import '../models/day_data.dart';
import 'account_page.dart';
import 'export_page.dart';
import 'keys.dart';
import 'install_page.dart';
import 'purchase_orders_page.dart';
import '../util/dates.dart';
import 'theme.dart';
import 'vehicles_page.dart';
import 'widgets.dart';

/// One row of the Settings list, or a heading ([letter] null).
class _SettingsItem {
  final String? letter;
  final Key? key;
  final IconData? icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? open;
  const _SettingsItem(
    this.letter, {
    this.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.open,
  });
  const _SettingsItem.head(this.title)
    : letter = null,
      key = null,
      icon = null,
      color = AppColors.navy,
      subtitle = '',
      open = null;
}

/// Settings, like the PC menu: Up / Down + Enter, or the letter.
class SettingsPage extends StatelessWidget {
  final Session session;
  const SettingsPage({super.key, required this.session});

  AppStore get store => session.store;

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  List<_SettingsItem> _items(BuildContext context) => [
    const _SettingsItem.head('App'),
    _SettingsItem(
      'I',
      key: const Key('installApp'),
      icon: kIsWeb ? Icons.install_mobile : Icons.verified,
      color: AppColors.full,
      title: 'Install App',
      subtitle: kIsWeb
          ? 'Put Daily Report on this phone or computer'
          : 'Installed on this phone. Use on a computer too',
      open: () => _push(context, InstallPage(session: session)),
    ),
    const _SettingsItem.head('PDF reports'),
    _SettingsItem(
      'P',
      key: const Key('sendPdf'),
      icon: Icons.picture_as_pdf,
      color: AppColors.full,
      title: 'Send / Download PDF',
      subtitle: 'A month, a business year (April - March) or any dates',
      open: () => _push(context, ExportPage(store: store)),
    ),
    const _SettingsItem.head('Lists'),
    _SettingsItem(
      'C',
      key: const Key('companies'),
      icon: Icons.business,
      color: AppColors.navy,
      title: 'Companies',
      subtitle:
          '${plural(store.activeCompanies.length, 'company', 'companies')} - add or remove, purchase orders (PO)',
      open: () =>
          _push(context, NamesPage(store: store, kind: NamesKind.company)),
    ),
    _SettingsItem(
      'F',
      key: const Key('plants'),
      icon: Icons.factory,
      color: AppColors.amber,
      title: 'Filling Plants',
      subtitle:
          '${plural(store.activePlants.length, 'plant', 'plants')} - add or remove',
      open: () =>
          _push(context, NamesPage(store: store, kind: NamesKind.plant)),
    ),
    _SettingsItem(
      'T',
      key: const Key('cashTypes'),
      icon: Icons.payments,
      color: AppColors.amber,
      title: 'Cash Types',
      subtitle: store.cashTypes.join(', '),
      open: () => _push(context, CashTypesPage(store: store)),
    ),
    _SettingsItem(
      'V',
      key: const Key('vehicles'),
      icon: Icons.local_shipping,
      color: AppColors.navy,
      title: 'Vehicles & Papers',
      subtitle:
          '${plural(store.vehicles.length, 'vehicle', 'vehicles')} - PUC, insurance ... renew dates',
      open: () => _push(context, VehiclesPage(store: store)),
    ),
    const _SettingsItem.head('Account'),
    _SettingsItem(
      'A',
      key: const Key('account'),
      icon: Icons.manage_accounts,
      color: AppColors.navy,
      title: session.auth.username ?? 'Account',
      subtitle: session.auth.isOwner
          ? 'Owner - password, users, log out'
          : 'Password, log out',
      open: () => _push(context, AccountPage(session: session)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = _items(context);
        return KeyPage(
          letters: {
            for (final it in items)
              if (it.letter != null) it.letter!.toLowerCase(): it.open!,
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            bottomNavigationBar: isWide(context)
                ? const KeyHints([
                    ('↑ ↓', 'Move'),
                    ('Enter', 'Open'),
                    ('Letter', 'Open it'),
                    ('Esc', 'Back'),
                  ])
                : null,
            body: PageWidth(
              max: 720,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                children: [
                  KeyList(
                    key: const Key('settingsList'),
                    autofocus: true,
                    itemCount: items.length,
                    selectable: (i) => items[i].open != null,
                    onOpen: (i) => items[i].open?.call(),
                    itemBuilder: (context, i, selected) {
                      final it = items[i];
                      if (it.open == null) return SectionTitle(it.title);
                      return _tile(it, selected && isWide(context));
                    },
                  ),
                  const SizedBox(height: 28),
                  const Center(child: LogoBadge(size: 64)),
                  const SizedBox(height: 8),
                  const Text(
                    'Daily Report',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Text(
                    'Panchal Enterprise  -  version $kAppVersion',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const Text(
                    'Data is saved securely in the cloud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(_SettingsItem it, bool selected) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      key: it.key,
      margin: EdgeInsets.zero,
      color: selected ? kSelectBg : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? kSelectLine : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: it.color.withValues(alpha: 0.12),
          child: Icon(it.icon, color: it.color),
        ),
        title: Text(
          it.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(it.subtitle, style: const TextStyle(fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (it.letter != null) KeyCap(it.letter!),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: it.open,
      ),
    ),
  );
}

// ------------------------------------------------------------- names

enum NamesKind { company, plant }

/// The list of companies or filling plants: Up / Down to move, Enter to
/// change the name, Delete to remove, N to add a new one. Companies: O =
/// the company's purchase orders.
class NamesPage extends StatefulWidget {
  final AppStore store;
  final NamesKind kind;
  const NamesPage({super.key, required this.store, required this.kind});

  @override
  State<NamesPage> createState() => _NamesPageState();
}

class _NamesPageState extends State<NamesPage> {
  final _list = GlobalKey<KeyListState>();
  AppStore get store => widget.store;
  bool get _isCompany => widget.kind == NamesKind.company;

  void _openPos(BuildContext context, NamedItem it) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PurchaseOrdersPage(store: store, companyId: it.id),
    ),
  );

  /// O: the purchase orders of the selected company.
  void _posOfSelected(BuildContext context) {
    final items = store.activeCompanies;
    final i = _list.currentState?.selected ?? 0;
    if (i < items.length) _openPos(context, items[i]);
  }

  Future<void> _add(BuildContext context) async {
    final name = await askText(
      context,
      title: _isCompany ? 'New company' : 'New filling plant',
      hint: 'Name',
      ok: 'Add',
    );
    if (name == null) return;
    if (_isCompany) {
      await store.addCompany(name);
    } else {
      await store.addPlant(name);
    }
  }

  Future<void> _edit(BuildContext context, NamedItem it) async {
    final name = await askText(
      context,
      title: 'Change name',
      initial: it.name,
      ok: 'Save',
    );
    if (name == null) return;
    if (_isCompany) {
      await store.renameCompany(it, name);
    } else {
      await store.renamePlant(it, name);
    }
  }

  Future<void> _remove(BuildContext context, NamedItem it) async {
    final ok = await confirm(
      context,
      title: 'Remove ${it.name}?',
      message:
          'It will not show in the list any more. '
          'Old entries keep the name.',
      yes: 'Remove',
      danger: true,
    );
    if (!ok) return;
    if (_isCompany) {
      await store.removeCompany(it);
    } else {
      await store.removePlant(it);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = _isCompany ? store.activeCompanies : store.activePlants;
        return KeyPage(
          letters: {
            'n': () => _add(context),
            if (_isCompany && items.isNotEmpty)
              'o': () => _posOfSelected(context),
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_isCompany ? 'Companies' : 'Filling Plants'),
            ),
            bottomNavigationBar: isWide(context)
                ? KeyHints([
                    ('↑ ↓', 'Move'),
                    ('Enter', 'Change name'),
                    if (_isCompany) ('O', 'Purchase orders (PO)'),
                    ('Del', 'Remove'),
                    ('N', 'Add new'),
                    ('Esc', 'Back'),
                  ])
                : null,
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('addName'),
              backgroundColor: AppColors.full,
              foregroundColor: Colors.white,
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              label: Text(
                _isCompany ? 'Add Company (N)' : 'Add Plant (N)',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            // The list is there (and has the cursor) even while it is empty,
            // so after N the new name can be chosen with the arrow keys.
            body: PageWidth(
              max: 720,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _isCompany
                            ? 'No companies yet.\nPress N (or tap "Add Company").'
                            : 'No filling plants yet.\nPress N (or tap "Add Plant").',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  KeyList(
                    key: _list,
                    autofocus: true,
                    itemCount: items.length,
                    onOpen: (i) => _edit(context, items[i]),
                    onDelete: (i) => _remove(context, items[i]),
                    itemBuilder: (context, i, selected) {
                      final it = items[i];
                      final pos = _isCompany ? store.posOf(it.id).length : 0;
                      return _row(
                        selected: selected,
                        // Companies: their purchase orders, under the name.
                        below: !_isCompany
                            ? null
                            : ExcludeFocus(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    key: Key('pos_${it.id}'),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                    ),
                                    onPressed: () => _openPos(context, it),
                                    icon: const Icon(
                                      Icons.assignment_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      pos == 0
                                          ? 'Purchase orders (O)'
                                          : '${plural(pos, 'purchase order', 'purchase orders')} (O)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.emptyBg,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        title: it.name,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeFocus(
                              child: IconButton(
                                tooltip: 'Change name (Enter)',
                                onPressed: () => _edit(context, it),
                                icon: const Icon(
                                  Icons.edit,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                            ExcludeFocus(
                              child: IconButton(
                                tooltip: 'Remove (Delete)',
                                onPressed: () => _remove(context, it),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
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
          ),
        );
      },
    );
  }
}

/// A row of a settings list, lit up when it is the selected one.
Widget _row({
  required bool selected,
  required Widget leading,
  required String title,
  Widget? below,
  Widget? trailing,
}) => Card(
  margin: const EdgeInsets.only(bottom: 8),
  color: selected ? kSelectBg : null,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: BorderSide(
      color: selected ? kSelectLine : Colors.transparent,
      width: 2,
    ),
  ),
  child: ListTile(
    leading: leading,
    title: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    subtitle: below,
    trailing: trailing,
  ),
);

/// Cash types (Deposit, Payment ...): Up / Down, Delete to remove, N to add.
class CashTypesPage extends StatelessWidget {
  final AppStore store;
  const CashTypesPage({super.key, required this.store});

  Future<void> _add(BuildContext context) async {
    final t = await askText(
      context,
      title: 'New cash type',
      hint: 'e.g. Advance, Old balance',
      ok: 'Add',
    );
    if (t != null) await store.addCashType(t);
  }

  Future<void> _remove(BuildContext context, String t) async {
    if (store.cashTypes.length <= 1) return;
    final ok = await confirm(
      context,
      title: 'Remove $t?',
      message: 'Old entries keep this name. It will not show in the list.',
      yes: 'Remove',
      danger: true,
    );
    if (ok) await store.removeCashType(t);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final types = store.cashTypes;
        return KeyPage(
          letters: {'n': () => _add(context)},
          child: Scaffold(
            appBar: AppBar(title: const Text('Cash Types')),
            bottomNavigationBar: isWide(context)
                ? const KeyHints([
                    ('↑ ↓', 'Move'),
                    ('Del', 'Remove'),
                    ('N', 'Add new'),
                    ('Esc', 'Back'),
                  ])
                : null,
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: AppColors.full,
              foregroundColor: Colors.white,
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Type (N)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            body: PageWidth(
              max: 720,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  KeyList(
                    autofocus: true,
                    itemCount: types.length,
                    onDelete: (i) => _remove(context, types[i]),
                    itemBuilder: (context, i, selected) => _row(
                      selected: selected,
                      leading: const Icon(
                        Icons.payments,
                        color: AppColors.amber,
                      ),
                      title: types[i],
                      trailing: types.length > 1
                          ? ExcludeFocus(
                              child: IconButton(
                                tooltip: 'Remove (Delete)',
                                onPressed: () => _remove(context, types[i]),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------- range export
