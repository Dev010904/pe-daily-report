import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/main.dart';
import 'package:daily_report/ui/share.dart' as share;
import 'package:daily_report/util/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder inField(String key, [Type type = TextField]) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byType(type),
  matchRoot: true,
);

/// Scrolls the page until [f] is built and on screen (lists are lazy).
Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    final pages = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    // On the PC the menu is a scroll area too: try each one, last first.
    final count = pages.evaluate().length;
    for (var p = count - 1; p >= 0 && f.evaluate().isEmpty; p--) {
      final page = pages.at(p);
      for (final step in const [-200.0, 200.0]) {
        for (var i = 0; i < 25 && f.evaluate().isEmpty; i++) {
          if (page.evaluate().isEmpty) break;
          await t.drag(page, Offset(0, step), warnIfMissed: false);
          await t.pumpAndSettle();
        }
      }
    }
  }
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await reveal(t, find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)).first);
  await t.pumpAndSettle();
}

Future<void> typeIn(WidgetTester t, String key, String text) async {
  final f = inField(key);
  await reveal(t, f);
  await t.enterText(f, text);
  await t.pumpAndSettle();
}

/// Types into a box with a pop-up list and presses Enter (takes the
/// highlighted choice).
Future<void> pickIn(WidgetTester t, String key, String text) async {
  await typeIn(t, key, text);
  await t.testTextInput.receiveAction(TextInputAction.next);
  await t.pumpAndSettle();
}

Future<void> typeInDialog(WidgetTester t, String key, String text) async {
  await t.enterText(inField(key), text);
  await t.pumpAndSettle();
}

Future<void> yes(WidgetTester t) async {
  await t.tap(find.byKey(const Key('choiceYes')));
  await t.pumpAndSettle();
}

/// Captures sent / downloaded files instead of opening WhatsApp.
final sent = <({String name, List<int> bytes})>[];

Future<void> tapAndWaitForFile(WidgetTester t, Finder f) async {
  await reveal(t, f);
  final before = sent.length;
  await t.runAsync(() async {
    await t.tap(f);
    for (var i = 0; i < 300 && sent.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await t.pumpAndSettle();
  expect(sent.length, before + 1, reason: 'a PDF should have been made');
  expect(String.fromCharCodes(sent.last.bytes.take(5)), '%PDF-');
}

/// Opens a part of the app: phone = tab / icon, PC = menu letter.
Future<void> open(WidgetTester t, bool wide, String what) async {
  if (wide) {
    const letters = {
      'Dashboard': 'D',
      'Supply': 'S',
      'Stock': 'K',
      'Companies': 'C',
      'Filling': 'L',
      'settings': 'E',
      'account': 'A',
      'shareDay': 'P',
    };
    await tapKey(t, 'menu_${letters[what]}');
    return;
  }
  switch (what) {
    case 'settings':
    case 'shareDay':
      await tapKey(t, what);
    case 'account':
      await tapKey(t, 'settings');
      await tapKey(t, 'account');
    default:
      await t.tap(
        find
            .descendant(
              of: find.byType(TabBar),
              matching: find.textContaining(what),
            )
            .first,
      );
      await t.pumpAndSettle();
  }
}

/// The whole daily workflow through the real screens.
Future<void> runFlow(WidgetTester t, {Size? screen, AppEnv? onDevice}) async {
  if (screen != null) {
    t.view.physicalSize = screen * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }
  final wide =
      (screen ?? t.view.physicalSize / t.view.devicePixelRatio).width >= 900;
  share.deliverFile = (bytes, name, mime, text) async {
    sent.add((name: name, bytes: bytes));
    return 'shared';
  };
  final cloud = FakeRemote();
  final env =
      onDevice ??
      AppEnv(
        auth: FakeAuthService(),
        openDb: () async => MemoryLocalDb(),
        newRemote: () => cloud,
        autoSync: false,
      );
  await t.pumpWidget(DailyReportApp(env: env));
  await t.pumpAndSettle();

  // ---- first time: create the owner account
  expect(find.text('Login'), findsWidgets);
  await tapKey(t, 'setupToggle');
  await typeIn(t, 'setupCode', 'WRONG-CODE');
  await typeIn(t, 'username', 'papa');
  await typeIn(t, 'password', 'secret123');
  await typeIn(t, 'password2', 'secret123');
  await tapKey(t, 'loginButton');
  expect(find.text('Setup code is wrong.'), findsOneWidget);
  await typeIn(t, 'setupCode', 'TEST-CODE-0001');
  await typeIn(t, 'password2', 'secret1234');
  await tapKey(t, 'loginButton');
  expect(find.text('The two passwords are not the same.'), findsOneWidget);
  await typeIn(t, 'password2', 'secret123');
  await tapKey(t, 'loginButton');
  expect(find.text('TODAY'), findsOneWidget);

  // ---- opening stock
  await open(t, wide, 'Stock');
  await tapKey(t, 'setOpening');
  await typeIn(t, 'openFull_O2', '20');
  await typeIn(t, 'openEmpty_O2', '10');
  await typeIn(t, 'openFull_DA', '6');
  await typeIn(t, 'openEmpty_DA', '9');
  await typeIn(t, 'openFull_AR_COMM', '10');
  await tapKey(t, 'saveOpening');

  // ---- a new entry: company, challan, then one line per gas
  if (wide) {
    await tapKey(t, 'menu_N');
  } else {
    await open(t, wide, 'Supply');
    await tapKey(t, 'addEntry');
  }
  await pickIn(t, 'company', 'Sharma Steel');
  expect(find.text('New company?'), findsOneWidget);
  await yes(t);
  await typeIn(t, 'challan', '101');
  await pickIn(t, 'gasPick0', 'o2');
  await typeIn(t, 'lineQty0_0', '2');
  await typeIn(t, 'lineQty0_1', '1');
  await pickIn(t, 'gasPick1', 'da');
  await typeIn(t, 'lineQty1_0', '3');
  await pickIn(t, 'gasPick2', 'ar c');
  await typeIn(t, 'lineQty2_0', '4');
  expect(find.text('ARGON'), findsWidgets);

  // LPG has no stock: refused, nothing may go below zero.
  await pickIn(t, 'gasPick3', 'lpg');
  await typeIn(t, 'lineQty3_0', '1');
  await tapKey(t, 'saveEntry');
  expect(find.text('Save this entry?'), findsOneWidget);
  await yes(t);
  expect(find.text('Cannot go below zero'), findsOneWidget);
  expect(
    find.text('LPG FULL: only 0 in stock, but 1 supplied (short by 1).'),
    findsOneWidget,
  );
  await t.tap(find.byKey(const Key('stockProblemOk')));
  await t.pumpAndSettle();
  await tapKey(t, 'lineDel3');

  // A company cannot return empties it never got.
  await typeIn(t, 'lineQty1_1', '4');
  await tapKey(t, 'saveEntry');
  await yes(t);
  expect(
    find.textContaining('Sharma Steel – DA: they have only 3 with them'),
    findsOneWidget,
  );
  await t.tap(find.byKey(const Key('stockProblemOk')));
  await t.pumpAndSettle();
  await typeIn(t, 'lineQty1_1', '2');
  // Totals: full 2 + 3 + 4, empty 1 + 2.
  expect(t.widget<Text>(find.byKey(const Key('lineTotal0'))).data, '9');
  expect(t.widget<Text>(find.byKey(const Key('lineTotal1'))).data, '3');

  // Cash (always a line ready): type, amount, then switch to GPay.
  await pickIn(t, 'cashType0', 'dep');
  await typeIn(t, 'cashAmount0', '2000');
  await tapKey(t, 'cashMode0');
  expect(find.text('GPay'), findsOneWidget);
  await tapKey(t, 'saveEntry');
  expect(find.text('Deposit ₹2,000 (GPay)'), findsOneWidget);
  await yes(t);
  if (wide) {
    // PC: a fresh entry opens for the next company, Esc goes back.
    expect(find.byKey(const Key('savedBanner')), findsOneWidget);
    // First Esc closes the company list, the second goes back.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
  }

  final session = find.byType(AuthGate).evaluate().isEmpty ? null : true;
  expect(session, isTrue);
  await open(t, wide, 'Supply');
  if (wide) {
    expect(find.text('Cash Received'), findsOneWidget);
    expect(find.text('Sharma Steel'), findsOneWidget);
  } else {
    expect(find.text('Supply (1)'), findsOneWidget);
    expect(find.text('CASH RECEIVED'), findsOneWidget);
  }

  // ---- bill tick in the list
  await t.tap(
    find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('bill_'),
    ),
  );
  await t.pumpAndSettle();
  expect(find.text('Sharma Steel: bill made ✔'), findsOneWidget);

  // ---- stock and filling with a plant
  await open(t, wide, 'Stock');
  expect(find.text('= 11'), findsNWidgets(2)); // O2: 10 + 1, DA: 9 + 2
  await tapKey(t, 'editFilling');
  await tapKey(t, 'addPlantLine');
  // No plants yet: the plant list opens straight away.
  await typeIn(t, 'pickSearch', 'Ambika Plant');
  await t.tap(find.text('Add "Ambika Plant"'));
  await t.pumpAndSettle();
  // 8 O2 empties sent to the plant, 5 came back filled: 3 still there.
  await typeIn(t, 'plantSent0', '8');
  await typeIn(t, 'plantFilled0', '5');
  expect(find.text('0 + 8 − 5 = 3'), findsOneWidget);
  // DA is a line like the others: 7 empty given, 4 filled received.
  await tapKey(t, 'addPlantLine');
  await pickIn(t, 'plantGas1', 'DA');
  await typeIn(t, 'plantSent1', '7');
  await typeIn(t, 'plantFilled1', '4');
  expect(find.textContaining('DA is swapped at the plant'), findsOneWidget);
  await tapKey(t, 'saveFilling');
  expect(find.text('+5'), findsOneWidget);
  expect(find.text('Ambika Plant'), findsOneWidget);
  expect(find.text('0 + 8 − 5 = 3'), findsOneWidget);
  expect(find.text('= 3'), findsOneWidget); // O2 godown: 11 − 8

  // ---- filling report: plants, then one plant day / month / year-wise
  await open(t, wide, 'Filling');
  String textOf(String key) => t.widget<Text>(find.byKey(Key(key))).data!;
  expect(textOf('plantsFilledTotal'), '9 cylinders'); // 5 Oxygen + 4 DA
  await reveal(t, find.text('Ambika Plant'));
  await t.tap(find.text('Ambika Plant'));
  await t.pumpAndSettle();
  expect(find.text('EMPTY CYLINDERS AT THIS PLANT NOW'), findsOneWidget);
  expect(textOf('plantNow'), '3 cylinders'); // Oxygen only: DA is swapped
  expect(textOf('plantTotalFilled'), '9');
  expect(textOf('plantTotalSent'), '15');
  await reveal(t, find.byKey(Key('plantRow_${dayKey(today())}')));
  await tapKey(t, 'plantView_month');
  await reveal(
    t,
    find.byKey(Key('plantRow_${dayKey(today()).substring(0, 7)}')),
  );
  await tapKey(t, 'plantView_year');
  expect(textOf('plantPeriod'), 'All years');
  expect(textOf('plantTotalFilled'), '9');
  await tapAndWaitForFile(t, find.byKey(const Key('plantPdf')));
  expect(sent.last.name, startsWith('PE_Plant_Ambika_Plant_'));
  await t.pageBack();
  await t.pumpAndSettle();

  // ---- today's PDF
  if (wide) {
    await reveal(t, find.byKey(const Key('menu_P')));
    final before = sent.length;
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('menu_P')));
      for (var i = 0; i < 300 && sent.length == before; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pumpAndSettle();
    expect(sent.length, before + 1);
  } else {
    await tapAndWaitForFile(t, find.byKey(const Key('shareDay')));
  }
  expect(sent.last.name, 'PE_Daily_Report_${fmtDmy(today())}.pdf');

  // ---- dashboard: the entry has a challan and its bill is made
  await open(t, wide, 'Dashboard');
  await reveal(t, find.text('All bills are made ✔'));
  await reveal(t, find.text('Every entry has a challan number ✔'));
  await reveal(t, find.text('Ambika Plant'));

  // ---- companies and a company page
  await open(t, wide, 'Companies');
  expect(find.text('Sharma Steel'), findsOneWidget);
  await tapAndWaitForFile(t, find.byKey(const Key('companySummaryPdf')));
  expect(sent.last.name, startsWith('PE_Companies_Cylinders_'));
  await t.tap(find.text('Sharma Steel'));
  await t.pumpAndSettle();
  expect(find.text('CYLINDER STOCK AT THIS COMPANY NOW'), findsOneWidget);
  await tapKey(t, 'editOpeningBalance');
  await pickIn(t, 'gasPick0', 'o2');
  await typeIn(t, 'lineQty0_0', '5');
  await tapKey(t, 'saveStartingBalance');
  expect(find.text('Save starting stock?'), findsOneWidget);
  await yes(t);
  await tapAndWaitForFile(t, find.byKey(const Key('companyPdf')));
  expect(sent.last.name, startsWith('PE_Company_Sharma_Steel_'));
  await t.pageBack();
  await t.pumpAndSettle();

  // ---- settings: send PDF for a month / business year
  await open(t, wide, 'settings');
  await tapKey(t, 'sendPdf');
  expect(find.text('Send / Download PDF'), findsWidgets);
  await tapAndWaitForFile(t, find.byKey(const Key('sendPdf')));
  await tapKey(t, 'option_year');
  await tapAndWaitForFile(t, find.byKey(const Key('sendPdf')));
  final fy = today().month >= 4 ? today().year : today().year - 1;
  expect(sent.last.name, 'PE_Daily_Report_01-04-${fy}_to_31-03-${fy + 1}.pdf');
  await t.pageBack();
  await t.pumpAndSettle();
  await t.pageBack();
  await t.pumpAndSettle();

  // ---- account: password, users, sync, log out, log in again
  await open(t, wide, 'account');
  expect(find.text('papa'), findsWidgets);
  await tapKey(t, 'changePassword');
  await typeInDialog(t, 'dlgFirst', 'secret123');
  await typeInDialog(t, 'dlgNew', 'newpass123');
  await typeInDialog(t, 'dlgAgain', 'newpass123');
  await t.tap(find.byKey(const Key('dlgOk')));
  await t.pumpAndSettle();
  expect(find.text('Password changed'), findsOneWidget);
  await tapKey(t, 'addUser');
  await typeInDialog(t, 'dlgFirst', 'Raju');
  await typeInDialog(t, 'dlgNew', 'rajupass1');
  await typeInDialog(t, 'dlgAgain', 'rajupass1');
  await t.tap(find.byKey(const Key('dlgOk')));
  await t.pumpAndSettle();
  expect(find.text('raju'), findsOneWidget);
  // Only 2 logins: adding more is locked.
  expect(find.byKey(const Key('addUser')), findsNothing);
  expect(find.byKey(const Key('usersLocked')), findsOneWidget);
  await t.pageBack();
  await t.pumpAndSettle();
  if (!wide) {
    await t.pageBack();
    await t.pumpAndSettle();
  }

  // Upload everything with "Sync now".
  await t.tap(find.byKey(const Key('syncBadge')));
  await t.pumpAndSettle();
  await t.runAsync(() async {
    await t.tap(find.byKey(const Key('syncNow')));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await t.pumpAndSettle();
  expect(find.text('All saved'), findsOneWidget);
  await t.tapAt(const Offset(5, 5)); // close the sheet
  await t.pumpAndSettle();
  if (onDevice == null) expect(cloud.rows, isNotEmpty);

  await open(t, wide, 'account');
  await tapKey(t, 'logout');
  await yes(t);
  expect(find.byKey(const Key('loginButton')), findsOneWidget);

  await typeIn(t, 'username', 'papa');
  await typeIn(t, 'password', 'secret123'); // old password no longer works
  await tapKey(t, 'loginButton');
  expect(find.text('Wrong username or password.'), findsOneWidget);
  await typeIn(t, 'password', 'newpass123');
  await tapKey(t, 'loginButton');
  expect(find.text('TODAY'), findsOneWidget);

  // Data comes back from the cloud.
  await t.tap(find.byKey(const Key('syncBadge')));
  await t.pumpAndSettle();
  await t.runAsync(() async {
    await t.tap(find.byKey(const Key('syncNow')));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await t.pumpAndSettle();
  await t.tapAt(const Offset(5, 5));
  await t.pumpAndSettle();
  await open(t, wide, 'Supply');
  if (!wide) expect(find.text('Supply (1)'), findsOneWidget);
  expect(find.text('Sharma Steel'), findsOneWidget);
}

void main() {
  testWidgets('full flow on a normal phone (411 wide)', (t) async {
    await runFlow(t, screen: const Size(411, 900));
  });

  testWidgets('full flow on a small phone (360 wide)', (t) async {
    await runFlow(t, screen: const Size(360, 740));
  });

  testWidgets('full flow on a PC screen (1366 wide)', (t) async {
    await runFlow(t, screen: const Size(1366, 768));
  });
}
