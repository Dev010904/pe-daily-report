import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/auth.dart';
import '../data/updates.dart';
import '../platform/updater.dart';
import 'keys.dart';
import 'theme.dart';
import 'widgets.dart';

// The real updater; tests replace these.
Future<RemoteVersion?> Function() latestVersion = fetchLatestVersion;
Future<String> Function(String token, void Function(double) progress)
downloadNewApp = downloadUpdate;
bool Function() phoneSelfUpdates = () => selfUpdates;

/// Website only (tests replace it): reload into the new version.
bool Function(int build) reloadNewVersion = reloadIntoNewVersion;

/// Under every page, once a newer version is found: "New update available
/// - Update". The app looks for it quietly right after login (and when it
/// comes back to the front); nothing is downloaded until Update is pressed.
/// Phone: Update downloads and installs it. Website / PC: Update reloads.
class UpdateBanner extends StatefulWidget {
  final AuthService auth;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  final bool enabled;

  const UpdateBanner({
    super.key,
    required this.auth,
    required this.navigator,
    required this.child,
    this.enabled = true,
  });

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner>
    with WidgetsBindingObserver {
  RemoteVersion? _found;
  bool _checking = false;
  bool _updating = false;
  bool _reopen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_onAuth);
    if (widget.enabled) {
      cleanOldUpdate();
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (widget.auth.signedIn) {
      _check();
    } else if (mounted) {
      setState(() {}); // logged out: the bar waits for the next login
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!widget.enabled || _checking || _found != null || !mounted) return;
    if (!kIsWeb && !phoneSelfUpdates()) return;
    if (!widget.auth.signedIn) return;
    _checking = true;
    final v = await latestVersion();
    _checking = false;
    if (!mounted || v == null || !v.isNewer) return;
    setState(() => _found = v);
  }

  Future<void> _update() async {
    final v = _found;
    if (v == null || _updating) return;
    if (kIsWeb) {
      if (!reloadNewVersion(v.build)) setState(() => _reopen = true);
      return;
    }
    _updating = true;
    await widget.navigator.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => UpdatePage(version: v, auth: widget.auth),
      ),
    );
    _updating = false;
  }

  @override
  Widget build(BuildContext context) {
    final v = _found;
    if (v == null || !widget.auth.signedIn) return widget.child;
    return Column(
      children: [
        Expanded(
          // The bar takes the bottom edge, so the pages above do not.
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: widget.child,
          ),
        ),
        Material(
          key: const Key('updateBanner'),
          color: AppColors.full,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.system_update,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _reopen
                          ? 'New version ${v.version} is ready. Close Daily Report and open it again.'
                          : 'New update available  (version ${v.version})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (!_reopen) ...[
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      key: const Key('updateNow'),
                      onPressed: _update,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.full,
                      ),
                      icon: const Icon(Icons.download, size: 20),
                      label: const Text(
                        'Update',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _Step { download, permission, install, failed }

/// Phone app: downloads and installs the new version (opened by Update on
/// the bar). Back closes it.
class UpdatePage extends StatefulWidget {
  final RemoteVersion version;
  final AuthService auth;
  const UpdatePage({super.key, required this.version, required this.auth});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> with WidgetsBindingObserver {
  _Step _step = _Step.download;
  double _progress = 0;
  String? _path;
  bool _noLogin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the Android setting: install straight away.
    if (state == AppLifecycleState.resumed && _step == _Step.permission) {
      _install();
    }
  }

  Future<void> _run() async {
    setState(() {
      _step = _Step.download;
      _progress = 0;
      _noLogin = false;
    });
    String? path;
    for (var attempt = 0; attempt < 3 && path == null; attempt++) {
      try {
        final token = await widget.auth.freshAccessToken();
        if (token == null) {
          _noLogin = true;
          break;
        }
        path = await downloadNewApp(token, (p) {
          if (mounted) setState(() => _progress = p);
        });
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      if (!mounted) return;
    }
    if (path == null) {
      setState(() => _step = _Step.failed);
      return;
    }
    _path = path;
    await _install();
  }

  Future<void> _install() async {
    if (_path == null) return;
    if (!await canInstallUpdates()) {
      if (mounted) setState(() => _step = _Step.permission);
      return;
    }
    if (mounted) setState(() => _step = _Step.install);
    try {
      await installUpdate(_path!);
    } catch (_) {
      // The user can press "Install update" again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.version.version;
    return EscBack(
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: LogoBadge(size: 64)),
                        const SizedBox(height: 12),
                        const Text(
                          'Update available',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version $kAppVersion  →  $v',
                          key: const Key('updateVersion'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ..._body(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    const big = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
    switch (_step) {
      case _Step.download:
        return [
          const Text('Downloading the new version. Please wait...', style: big),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: _progress == 0 ? null : _progress,
            minHeight: 10,
          ),
          const SizedBox(height: 6),
          Text('${(_progress * 100).round()} %', textAlign: TextAlign.right),
        ];
      case _Step.permission:
        return [
          const Text(
            'One time only: Android must allow Daily Report to install its '
            'own updates.\n\n'
            '1. Tap the green button below.\n'
            '2. Turn ON "Allow from this source".\n'
            '3. Press Back. The update then installs.',
            style: big,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('updatePermission'),
            autofocus: true,
            onPressed: openInstallPermission,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.full,
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.settings),
            label: const Text(
              'Open the setting',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ];
      case _Step.install:
        return [
          const Text(
            'If a box opens, tap UPDATE (only the first time).\n\n'
            'The app closes for a moment while it updates. Then open Daily '
            'Report again (or tap the "Daily Report is updated" message). '
            'Your data is safe.',
            style: big,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('updateInstall'),
            autofocus: true,
            onPressed: _install,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.full,
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.system_update),
            label: const Text('Install update', style: TextStyle(fontSize: 18)),
          ),
        ];
      case _Step.failed:
        return [
          Text(
            _noLogin
                ? 'The login has run out, so the update cannot be downloaded.\n'
                      'Please log out, log in again and press Update again.'
                : 'Could not download the update. Please check the internet '
                      'and try again.',
            style: big,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('updateRetry'),
            autofocus: true,
            onPressed: _run,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('updateClose'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ];
    }
  }
}
