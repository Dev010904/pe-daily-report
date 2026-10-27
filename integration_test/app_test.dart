import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/device_db.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/app_flow_test.dart' as flow;

/// Runs the full workflow on a real phone / emulator with the real on-phone
/// database (the cloud is a stand-in, so no real login is used).
/// It WIPES the app data on that device, so never run it on a phone in use.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full flow on device with the real phone database', (t) async {
    final db = await openDeviceDb();
    await db.wipe();
    final cloud = FakeRemote();
    await flow.runFlow(t,
        onDevice: AppEnv(
          auth: FakeAuthService(),
          openDb: () async => db,
          newRemote: () => cloud,
          autoSync: false,
        ));
    // The phone's database really holds the synced data.
    final again = await Session.start(AppEnv(
      auth: FakeAuthService(signedInAs: 'papa'),
      openDb: () async => db,
      autoSync: false,
    ));
    expect(again.store.activeCompanies.map((c) => c.name), contains('Sharma Steel'));
    expect(again.repo.pending, 0);
  });
}
