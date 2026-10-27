import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/auth.dart';
import '../data/session.dart';
import 'keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// Logged-in user, password change, user management (owner) and log out.
class AccountPage extends StatefulWidget {
  final Session session;
  const AccountPage({super.key, required this.session});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AuthService get auth => widget.session.auth;
  List<Member>? _members;
  String? _membersError;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    if (!auth.isOwner) return;
    try {
      final m = await auth.members();
      if (mounted) setState(() => _members = m);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _membersError = e.message);
    }
  }

  Future<void> _changePassword() async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) =>
          const _PasswordDialog(askOld: true, title: 'Change my password'),
    );
    if (r == null) return;
    final err = await auth.changePassword(r.$1, r.$2);
    if (mounted) toast(context, err ?? 'Password changed');
  }

  Future<void> _addUser() async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _PasswordDialog(
        askUsername: true,
        title: 'Add a user',
        minLength: 1,
      ),
    );
    if (r == null) return;
    try {
      await auth.addMember(r.$1, r.$2);
      if (mounted) toast(context, 'User ${r.$1.toLowerCase()} added');
      await _loadMembers();
    } on AuthFailure catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _resetPassword(Member m) async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _PasswordDialog(
        title: 'New password for ${m.username}',
        minLength: m.isOwner ? kMinPassword : 1,
      ),
    );
    if (r == null) return;
    try {
      await auth.setPassword(m.username, r.$2);
      if (mounted) toast(context, 'Password changed for ${m.username}');
    } on AuthFailure catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _remove(Member m) async {
    final ok = await confirm(
      context,
      title: 'Remove ${m.username}?',
      message: 'This login will stop working on every device.',
      yes: 'Remove',
      danger: true,
    );
    if (!ok) return;
    try {
      await auth.removeMember(m.username);
      await _loadMembers();
    } on AuthFailure catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _logout({bool everywhere = false}) async {
    final pending = widget.session.repo.pending;
    final ok = await confirm(
      context,
      title: everywhere ? 'Log out on all devices?' : 'Log out?',
      message: pending > 0
          ? '$pending change(s) are NOT uploaded yet and will be lost. '
                'Connect to internet and wait for the green cloud first.'
          : everywhere
          ? 'Every phone and PC using this login will need the password again.'
          : 'You will need your username and password to come back.',
      yes: 'Log out',
      danger: true,
    );
    if (!ok || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).clearSnackBars();
    await auth.signOut(everywhere: everywhere);
  }

  @override
  Widget build(BuildContext context) {
    final members = _members ?? const <Member>[];
    return KeyPage(
      // Owner: the users list has the cursor (letters still work).
      autofocus: !auth.isOwner,
      letters: {
        if (auth.isOwner) 'c': _changePassword,
        if (auth.isOwner && _members != null && _members!.length < kMaxLogins)
          'u': _addUser,
        'q': _logout,
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Account & Users')),
        bottomNavigationBar: isWide(context)
            ? KeyHints([
                if (auth.isOwner) ('C', 'Change my password'),
                if (auth.isOwner) ('↑ ↓', 'Users'),
                if (auth.isOwner) ('Enter', 'New password for user'),
                if (auth.isOwner) ('Del', 'Remove user'),
                if (auth.isOwner) ('U', 'Add user'),
                ('Q', 'Log out'),
                ('Esc', 'Back'),
              ])
            : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.emptyBg,
                  child: Icon(Icons.person, color: AppColors.navy),
                ),
                title: Text(
                  auth.username ?? '-',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  auth.isOwner ? 'Owner' : 'User',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
            if (auth.isOwner) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('changePassword'),
                onPressed: _changePassword,
                icon: const Icon(Icons.password),
                label: const Text('Change my password (C)'),
              ),
              const SectionTitle('Users who can log in'),
              if (_membersError != null)
                Text(
                  _membersError!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              if (_members == null && _membersError == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              KeyList(
                autofocus: true,
                itemCount: members.length,
                onOpen: (i) => _resetPassword(members[i]),
                onDelete: (i) {
                  if (!members[i].isOwner) _remove(members[i]);
                },
                itemBuilder: (context, i, selected) {
                  final m = members[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      color: selected ? kSelectBg : null,
                      child: ListTile(
                        leading: Icon(
                          m.isOwner
                              ? Icons.workspace_premium
                              : Icons.person_outline,
                          color: m.isOwner ? AppColors.gold : AppColors.navy,
                        ),
                        title: Text(
                          m.username,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(m.isOwner ? 'Owner' : 'User'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Set new password',
                              onPressed: () => _resetPassword(m),
                              icon: const Icon(
                                Icons.lock_reset,
                                color: AppColors.navy,
                              ),
                            ),
                            if (!m.isOwner)
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _remove(m),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (_members != null && _members!.length < kMaxLogins)
                OutlinedButton.icon(
                  key: const Key('addUser'),
                  onPressed: _addUser,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add a user (U)'),
                )
              else if (_members != null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.lock, color: AppColors.muted, size: 18),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Locked: only 2 logins are allowed (you + 1 user).',
                          key: Key('usersLocked'),
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SectionTitle('Log out'),
            OutlinedButton.icon(
              key: const Key('logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Log out of this device (Q)'),
            ),
            if (auth.isOwner) const SizedBox(height: 8),
            if (auth.isOwner)
              TextButton.icon(
                key: const Key('logoutAll'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _logout(everywhere: true),
                icon: const Icon(Icons.devices),
                label: const Text('Log out on ALL devices (lost phone)'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a password (twice), optionally the old one or a username.
class _PasswordDialog extends StatefulWidget {
  final String title;
  final bool askOld;
  final bool askUsername;
  final int minLength;
  const _PasswordDialog({
    required this.title,
    this.askOld = false,
    this.askUsername = false,
    this.minLength = kMinPassword,
  });

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _first = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  void _ok() {
    final first = _first.text.trim();
    if (widget.askUsername && !kUsernamePattern.hasMatch(first.toLowerCase())) {
      setState(() => _error = kUsernameHelp);
      return;
    }
    if (widget.askOld && _first.text.isEmpty) {
      setState(() => _error = 'Enter your old password.');
      return;
    }
    if (_new.text.length < widget.minLength) {
      setState(
        () => _error = widget.minLength <= 1
            ? 'Enter a password.'
            : 'Password must be at least ${widget.minLength} characters.',
      );
      return;
    }
    if (_new.text != _again.text) {
      setState(() => _error = 'The two passwords are not the same.');
      return;
    }
    Navigator.pop(context, (
      widget.askUsername ? first.toLowerCase() : _first.text,
      _new.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.askUsername || widget.askOld) ...[
              TextField(
                key: const Key('dlgFirst'),
                controller: _first,
                autofocus: true,
                textInputAction: TextInputAction.next,
                obscureText: widget.askOld,
                keyboardType: TextInputType.visiblePassword,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                decoration: InputDecoration(
                  labelText: widget.askOld ? 'Old password' : 'Username',
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              key: const Key('dlgNew'),
              controller: _new,
              autofocus: !(widget.askUsername || widget.askOld),
              textInputAction: TextInputAction.next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('dlgAgain'),
              controller: _again,
              obscureText: true,
              // Enter in the last box saves.
              onSubmitted: (_) => _ok(),
              decoration: const InputDecoration(
                labelText: 'New password again',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('dlgOk'),
          onPressed: _ok,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
