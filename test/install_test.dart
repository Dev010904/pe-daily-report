import 'dart:io';

import 'package:daily_report/config.dart';
import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/ui/install_page.dart';
import 'package:daily_report/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TokenAuth extends FakeAuthService {
  _TokenAuth() : super(signedInAs: 'd');
  @override
  Future<String?> freshAccessToken() async => 'token-for-test';
}

Future<Session> _session() => Session.start(
  AppEnv(
    auth: _TokenAuth(),
    openDb: () async => MemoryLocalDb(),
    autoSync: false,
  ),
);

Future<void> _open(WidgetTester t, Session s, {required bool web}) async {
  await t.binding.setSurfaceSize(const Size(400, 860));
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: InstallPage(session: s, web: web),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('app version and build number match pubspec.yaml', () {
    final m = RegExp(
      r'^version:\s*([0-9.]+)\+(\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(kAppVersion, m.group(1));
    // Auto-update compares this number with the website's version.json.
    expect(kBuildNumber, int.parse(m.group(2)!));
  });

  testWidgets('phone app: shows it is installed and the website link', (
    t,
  ) async {
    final s = await t.runAsync(_session);
    await _open(t, s!, web: false);
    expect(find.textContaining('installed on this phone'), findsOneWidget);
    expect(find.text(kWebsiteUrl), findsOneWidget);
    expect(find.byKey(const Key('downloadApk')), findsNothing);
  });

  testWidgets('website on an Android phone: one big download button', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    String? gotToken, gotName;
    downloadAndroidApp = (token, name) async {
      gotToken = token;
      gotName = name;
      return 'downloaded';
    };
    final s = await t.runAsync(_session);
    await _open(t, s!, web: true);
    expect(find.byKey(const Key('installHere')), findsNothing);
    await t.tap(find.byKey(const Key('downloadApk')));
    await t.pumpAndSettle();
    expect(gotToken, 'token-for-test');
    expect(gotName, 'PE Daily Report v$kAppVersion.apk');
    expect(find.textContaining('Open the downloaded file'), findsOneWidget);
    await t.tap(find.byKey(const Key('stepsOk')));
    await t.pumpAndSettle();

    // A login that ran out is explained instead of failing silently.
    downloadAndroidApp = (token, name) async => 'login';
    await t.tap(find.byKey(const Key('downloadApk')));
    await t.pumpAndSettle();
    expect(find.textContaining('log in again'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('website on a computer: install here, and the phone app file', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final s = await t.runAsync(_session);
    await _open(t, s!, web: true);
    expect(find.byKey(const Key('downloadApk')), findsOneWidget);
    // No browser offer in tests, so the steps are shown instead.
    await t.tap(find.byKey(const Key('installHere')));
    await t.pumpAndSettle();
    expect(find.textContaining('address bar'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
