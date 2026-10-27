import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'config.dart';
import 'data/auth.dart';
import 'data/device_db.dart';
import 'data/remote.dart';
import 'data/session.dart';
import 'platform/ctrl_key.dart';
import 'platform/key_store.dart';
import 'platform/splash.dart';
import 'platform/web_storage.dart';
import 'ui/home_page.dart';
import 'ui/keys.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';
import 'ui/update_page.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  watchCtrlKey();
  runApp(DailyReportApp(env: await createEnv()));
  WidgetsBinding.instance.addPostFrameCallback((_) => hideWebSplash());
}

Future<AppEnv> createEnv() async {
  if (kDemoMode) {
    final cloud = FakeRemote();
    return AppEnv(
      auth: FakeAuthService(signedInAs: 'demo'),
      openDb: openDeviceDb,
      newRemote: () => cloud,
      readOld: readOldVersionData,
      retireOld: retireOldVersionData,
    );
  }
  // Website: never keep a login in the browser (always ask again).
  if (kIsWeb) wipeBrowserStorage();
  final keys = KeyStore();
  await Supabase.initialize(
    url: kSupabaseUrl,
    publishableKey: kSupabaseKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: kIsWeb
          ? const EmptyLocalStorage()
          : SecureSessionStorage(keys),
      detectSessionInUri: false,
    ),
  );
  final client = Supabase.instance.client;
  final auth = SupabaseAuthService(
    client,
    readCache: keys.read,
    writeCache: keys.write,
  );
  await auth.init();
  return AppEnv(
    auth: auth,
    openDb: openDeviceDb,
    newRemote: () => SupabaseRemote(client),
    readOld: readOldVersionData,
    retireOld: retireOldVersionData,
  );
}

final GlobalKey<NavigatorState> appNavigator = GlobalKey<NavigatorState>();

class DailyReportApp extends StatelessWidget {
  final AppEnv env;
  const DailyReportApp({super.key, required this.env});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: MaterialApp(
        title: 'Daily Report - Panchal Enterprise',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigator,
        theme: buildTheme(),
        // The app already uses big text; very large phone font settings
        // would push the tables off screen, so cap the extra scaling.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          // Every form: Up / Backspace in an empty box = previous box.
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (n, e) => fieldNavKey(e),
            // After login: a quiet look for a newer version; if there is
            // one, an "Update" bar stays under every page.
            child: UpdateBanner(
              auth: env.auth,
              navigator: appNavigator,
              enabled: !kDemoMode || kUpdateTest,
              child: child!,
            ),
          ),
        ),
        home: AuthGate(env: env),
      ),
    );
  }
}

/// Shows the login page until someone logs in, then the app with their data.
class AuthGate extends StatefulWidget {
  final AppEnv env;
  const AuthGate({super.key, required this.env});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  bool _starting = false;
  Object? _error;

  AuthService get auth => widget.env.auth;

  @override
  void initState() {
    super.initState();
    auth.addListener(_onAuth);
    _onAuth();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    super.dispose();
  }

  Future<void> _onAuth() async {
    if (auth.signedIn && _session == null && !_starting) {
      setState(() {
        _starting = true;
        _error = null;
      });
      try {
        final s = await Session.start(widget.env);
        if (!mounted) return;
        setState(() => _session = s);
        // Coming back online refreshes the user name / owner flag.
        auth.refreshMe();
      } catch (e) {
        if (mounted) setState(() => _error = e);
      } finally {
        if (mounted) setState(() => _starting = false);
      }
    } else if (!auth.signedIn && _session != null) {
      final s = _session!;
      appNavigator.currentState?.popUntil((r) => r.isFirst);
      setState(() => _session = null);
      await s.end();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!auth.signedIn) return LoginPage(auth: auth);
    final s = _session;
    if (s == null) {
      return Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LogoBadge(size: 84),
              const SizedBox(height: 20),
              if (_error == null)
                const CircularProgressIndicator(color: Colors.white)
              else ...[
                Text(
                  'Could not open data: $_error',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _onAuth,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return HomePage(session: s);
  }
}
