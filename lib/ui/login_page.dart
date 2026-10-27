import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/auth.dart';
import 'theme.dart';
import 'widgets.dart';

/// Username + password login, and the one-time owner setup.
class LoginPage extends StatefulWidget {
  final AuthService auth;
  const LoginPage({super.key, required this.auth});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _code = TextEditingController();
  final _passNode = FocusNode();
  final _pass2Node = FocusNode();
  bool _setupMode = false;
  bool _setupAvailable = false;
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.auth.setupNeeded().then((v) {
      if (mounted) setState(() => _setupAvailable = v);
    });
  }

  @override
  void dispose() {
    for (final c in [_user, _pass, _pass2, _code]) {
      c.dispose();
    }
    _passNode.dispose();
    _pass2Node.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final u = _user.text.trim().toLowerCase();
    if (u.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signIn(u, _pass.text);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setup() async {
    final u = _user.text.trim().toLowerCase();
    String? err;
    if (_code.text.trim().isEmpty) {
      err = 'Enter the setup code.';
    } else if (!kUsernamePattern.hasMatch(u)) {
      err = kUsernameHelp;
    } else if (_pass.text.length < kMinPassword) {
      err = 'Password must be at least $kMinPassword characters.';
    } else if (_pass.text != _pass2.text) {
      err = 'The two passwords are not the same.';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.auth.createOwner(_code.text, u, _pass.text);
    if (r != null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = r;
        });
      }
      return;
    }
    await _login();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const LogoBadge(size: 84),
                  const SizedBox(height: 14),
                  const Text(
                    'Daily Report',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Panchal Enterprise',
                    style: TextStyle(fontSize: 15, color: Color(0xFFE9D9A6)),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _setupMode ? 'First time setup' : 'Login',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (_setupMode) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'Create the owner account. You need the setup code.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                key: const Key('setupCode'),
                                controller: _code,
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: const TextStyle(
                                  fontSize: 18,
                                  letterSpacing: 1.5,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Setup code',
                                  prefixIcon: Icon(Icons.vpn_key),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            TextField(
                              key: const Key('username'),
                              controller: _user,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _passNode.requestFocus(),
                              onEditingComplete: () {},
                              autofillHints: const [AutofillHints.username],
                              keyboardType: TextInputType.visiblePassword,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                              ],
                              style: const TextStyle(fontSize: 18),
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('password'),
                              controller: _pass,
                              focusNode: _passNode,
                              obscureText: !_show,
                              autofillHints: [
                                _setupMode
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              onSubmitted: (_) => _setupMode
                                  ? _pass2Node.requestFocus()
                                  : _login(),
                              style: const TextStyle(fontSize: 18),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: ExcludeFocus(
                                  child: IconButton(
                                    tooltip: _show ? 'Hide' : 'Show',
                                    icon: Icon(
                                      _show
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () =>
                                        setState(() => _show = !_show),
                                  ),
                                ),
                              ),
                            ),
                            if (_setupMode) ...[
                              const SizedBox(height: 12),
                              TextField(
                                key: const Key('password2'),
                                controller: _pass2,
                                focusNode: _pass2Node,
                                onSubmitted: (_) => _setup(),
                                obscureText: !_show,
                                style: const TextStyle(fontSize: 18),
                                decoration: const InputDecoration(
                                  labelText: 'Password again',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Use at least $kMinPassword characters. Write it down safely.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _error!,
                                  key: const Key('loginError'),
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              key: const Key('loginButton'),
                              onPressed: _busy
                                  ? null
                                  : (_setupMode ? _setup : _login),
                              child: _busy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _setupMode
                                          ? 'Create owner account'
                                          : 'Login',
                                    ),
                            ),
                            if (_setupAvailable || _setupMode)
                              TextButton(
                                key: const Key('setupToggle'),
                                onPressed: () => setState(() {
                                  _setupMode = !_setupMode;
                                  _error = null;
                                }),
                                child: Text(
                                  _setupMode
                                      ? 'Back to login'
                                      : 'First time? Set up the owner account',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user,
                        color: Color(0xFFB9C6DA),
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Secure login · data saved in the cloud',
                          style: TextStyle(color: Color(0xFFB9C6DA)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
