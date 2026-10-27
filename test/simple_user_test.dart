import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart' show tapKey, typeIn, typeInDialog;

/// The owner's father logs in as "d" / "d": allowed, but only as a normal
/// user, and nobody else can be added after that.
void main() {
  test('rules for the second login', () async {
    final auth = FakeAuthService(signedInAs: 'dev');
    await auth.addMember('D', 'd');
    expect((await auth.members()).map((m) => '${m.username}:${m.isOwner}'), [
      'd:false',
      'dev:true',
    ]);
    expect(
      () => auth.addMember('third', 'password123'),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.message,
          'message',
          contains('Only 2 logins'),
        ),
      ),
    );
    await auth.signOut();
    await auth.signIn('d', 'd');
    expect(auth.isOwner, isFalse);
    expect(
      await auth.changePassword('d', 'newpass123'),
      'Only the owner can change passwords.',
    );
    expect(() => auth.addMember('x', 'y'), throwsA(isA<AuthFailure>()));
    expect(
      () => auth.setPassword('dev', 'hacked1234'),
      throwsA(isA<AuthFailure>()),
    );
    expect(() => auth.removeMember('dev'), throwsA(isA<AuthFailure>()));
  });

  testWidgets('owner adds "d" / "d"; "d" logs in and has no owner buttons', (
    t,
  ) async {
    t.view.physicalSize = const Size(411, 900) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final auth = FakeAuthService(signedInAs: 'dev');
    final cloud = FakeRemote();
    await t.pumpWidget(
      DailyReportApp(
        env: AppEnv(
          auth: auth,
          openDb: () async => MemoryLocalDb(),
          newRemote: () => cloud,
          autoSync: false,
        ),
      ),
    );
    await t.pumpAndSettle();

    // Owner adds the simple login.
    await tapKey(t, 'settings');
    await tapKey(t, 'account');
    await tapKey(t, 'addUser');
    await typeInDialog(t, 'dlgFirst', 'd');
    await typeInDialog(t, 'dlgNew', 'd');
    await typeInDialog(t, 'dlgAgain', 'd');
    await t.tap(find.byKey(const Key('dlgOk')));
    await t.pumpAndSettle();
    expect(find.text('User d added'), findsOneWidget);
    expect(find.byKey(const Key('usersLocked')), findsOneWidget);

    // Log out, log in as d / d.
    await tapKey(t, 'logout');
    await t.tap(find.byKey(const Key('choiceYes')));
    await t.pumpAndSettle();
    await typeIn(t, 'username', 'd');
    await typeIn(t, 'password', 'd');
    await tapKey(t, 'loginButton');
    expect(find.text('TODAY'), findsOneWidget);

    // "d" can work normally but sees no owner tools.
    await tapKey(t, 'settings');
    await tapKey(t, 'account');
    expect(find.text('User'), findsOneWidget);
    expect(find.byKey(const Key('changePassword')), findsNothing);
    expect(find.byKey(const Key('addUser')), findsNothing);
    expect(find.text('Users who can log in'.toUpperCase()), findsNothing);
    expect(find.byKey(const Key('logoutAll')), findsNothing);
    expect(find.byKey(const Key('logout')), findsOneWidget);
  });
}
