import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/session.dart';
import '../platform/install.dart';
import 'keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// Downloads the Android app from the website. Tests replace this.
Future<String> Function(String? token, String fileName) downloadAndroidApp =
    downloadAndroidAppImpl;

String get apkFileName => 'PE Daily Report v$kAppVersion.apk';

/// Install App: on the website, puts the app on this computer (desktop
/// icon) or downloads the Android app; in the phone app, shows that it is
/// installed and how to open it on a computer.
class InstallPage extends StatefulWidget {
  final Session session;

  /// Website or phone app (tests can choose).
  final bool web;
  const InstallPage({super.key, required this.session, this.web = kIsWeb});

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  bool _busy = false;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _iphone => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _installHere() async {
    if (canOfferInstall()) {
      final yes = await offerInstall();
      if (!mounted) return;
      if (yes) {
        toast(context, 'Installed. Open Daily Report from the desktop icon.');
        setState(() {});
      }
      return;
    }
    await _steps('Install on this computer', const [
      'At the top, look at the right end of the address bar for the '
          'install icon (a small screen with a down arrow) and click it.',
      'If it is not there: open the browser menu (⋮ or ≡), then "Save and '
          'share" → "Install page as app" (Brave: "Install Daily Report").',
      'Click "Install". A Daily Report icon comes on the desktop.',
    ]);
  }

  Future<void> _downloadApk() async {
    setState(() => _busy = true);
    final token = await widget.session.auth.freshAccessToken();
    final r = await downloadAndroidApp(token, apkFileName);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case 'downloaded':
        await _steps(
          'App downloaded',
          _android
              ? const [
                  'Open the downloaded file: tap the download message at the '
                      'top or bottom, or open Files → Downloads.',
                  'If the phone asks, allow "Install unknown apps" for this '
                      'browser (only the first time).',
                  'Tap "Install" (or "Update" if the app is already there). '
                      'Data is not lost.',
                  'Open Daily Report and log in.',
                ]
              : [
                  'The file "$apkFileName" is in the Downloads folder.',
                  'Send it on WhatsApp to the phone.',
                  'On the phone, open it and tap "Install" (or "Update"). '
                      'Data is not lost.',
                ],
        );
      case 'login':
        toast(
          context,
          'Login has run out. Please log out, log in again and try.',
        );
      default:
        toast(context, 'Could not download. Check the internet and try again.');
    }
  }

  Future<void> _steps(String title, List<String> steps) => showDialog<void>(
    context: context,
    builder: (ctx) => KeyDialog(
      onEnter: () => Navigator.pop(ctx),
      child: AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.navy,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          steps[i],
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('stepsOk'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    if (!widget.web) {
      cards.addAll([
        _done('Daily Report is installed on this phone.\nVersion $kAppVersion'),
        _websiteCard(),
      ]);
    } else {
      final installed = runningAsInstalledApp();
      if (installed) cards.add(_done('You are using the installed app.'));
      final apk = _apkCard();
      if (_android) {
        cards.add(apk);
      } else if (_iphone) {
        cards.add(_iphoneCard());
      } else {
        if (!installed) cards.add(_computerCard());
        cards.add(apk);
      }
    }
    return EscBack(
      child: Scaffold(
        appBar: AppBar(title: const Text('Install App')),
        body: PageWidth(
          max: 720,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              for (final c in cards) ...[c, const SizedBox(height: 14)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
    required Widget action,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 14),
          action,
        ],
      ),
    ),
  );

  Widget _bigButton({
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) => FilledButton.icon(
    key: key,
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      minimumSize: const Size.fromHeight(58),
    ),
    icon: Icon(icon, size: 28),
    label: Text(label, style: const TextStyle(fontSize: 19)),
  );

  Widget _done(String text) => Card(
    color: AppColors.fullBg,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.full, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _computerCard() => _card(
    icon: Icons.desktop_windows,
    color: AppColors.navy,
    title: 'On this computer',
    text:
        'Put Daily Report on this computer like a normal app, with its '
        'own icon on the desktop. It still asks for the login every time.',
    action: _bigButton(
      key: const Key('installHere'),
      icon: Icons.install_desktop,
      label: 'Install on this computer',
      color: AppColors.navy,
      onPressed: _installHere,
    ),
  );

  Widget _apkCard() => _card(
    icon: Icons.phone_android,
    color: AppColors.full,
    title: _android ? 'App for this phone' : 'Android phone app',
    text:
        'The phone app works at the godown even without internet and '
        'stays logged in. If it is already on the phone, this updates it '
        'without losing any data.',
    action: _busy
        ? const SizedBox(
            height: 58,
            child: Center(child: CircularProgressIndicator()),
          )
        : _bigButton(
            key: const Key('downloadApk'),
            icon: Icons.download,
            label: 'Download Android App',
            color: AppColors.full,
            onPressed: _downloadApk,
          ),
  );

  Widget _iphoneCard() => _card(
    icon: Icons.phone_iphone,
    color: AppColors.navy,
    title: 'On this iPhone',
    text:
        '1. Tap the Share button (square with an arrow) at the bottom.\n'
        '2. Tap "Add to Home Screen".\n'
        '3. Tap "Add". A Daily Report icon comes on the home screen.',
    action: const SizedBox.shrink(),
  );

  Widget _websiteCard() => _card(
    icon: Icons.desktop_windows,
    color: AppColors.navy,
    title: 'Use on a computer',
    text:
        'Open this address in Chrome or Brave on the computer and log '
        'in. Then Settings → Install App puts an icon on the desktop.',
    action: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.emptyBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            kWebsiteUrl,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.empty,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _bigButton(
          key: const Key('shareWebsite'),
          icon: Icons.share,
          label: 'Send website link',
          color: AppColors.navy,
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              text: 'Daily Report - Panchal Enterprise\n$kWebsiteUrl',
            ),
          ),
        ),
      ],
    ),
  );
}
