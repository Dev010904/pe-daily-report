import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/records.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/main.dart';
import 'package:daily_report/ui/entry_page.dart';
import 'package:daily_report/ui/gas_lines.dart';
import 'package:daily_report/ui/keys.dart';
import 'package:daily_report/ui/stock_tab.dart';
import 'package:daily_report/util/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The typing box that has the cursor.
Finder _focusedBox() => find.byWidgetPredicate(
  (w) => w is EditableText && w.focusNode.hasFocus,
  skipOffstage: false,
);

/// Types into whichever box has the cursor (like the keyboard does).
Future<void> type(WidgetTester t, String text) async {
  await t.enterText(_focusedBox(), text);
  await t.pumpAndSettle();
}

/// Enter inside the typing box that has the cursor.
Future<void> enter(WidgetTester t) async {
  await t.showKeyboard(_focusedBox());
  await t.testTextInput.receiveAction(TextInputAction.next);
  await t.pumpAndSettle();
}

/// A key press outside typing boxes (menu letters, Enter on buttons, Esc...).
Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pumpAndSettle();
}

/// A box in the Damaged page's "Declared damaged today" list (the 2nd).
Finder _inDeclared(String key) => find.descendant(
  of: find.byType(GasLinesEditor).at(1),
  matching: find.byKey(Key(key)),
);

String? focusedKey() {
  BuildContext? c = FocusManager.instance.primaryFocus?.context;
  String? found;
  c?.visitAncestorElements((e) {
    final k = e.widget.key;
    if (k is ValueKey<String>) {
      found = k.value;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  testWidgets('PC: the whole day with the keyboard only', (t) async {
    t.view.physicalSize = const Size(1366, 768) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final auth = FakeAuthService();
    auth.users['papa'] = (password: 'secret123', owner: true);
    await t.pumpWidget(
      DailyReportApp(
        env: AppEnv(
          auth: auth,
          openDb: () async => MemoryLocalDb(),
          newRemote: FakeRemote.new,
          autoSync: false,
        ),
      ),
    );
    await t.pumpAndSettle();

    // ---- login: the cursor starts in Username; Enter, password, Enter.
    expect(focusedKey(), 'username');
    await type(t, 'papa');
    await enter(t);
    expect(focusedKey(), 'password');
    await type(t, 'secret123');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byKey(const Key('menu_D')), findsOneWidget);

    // ---- O = opening stock: type, Enter to the next box, Ctrl+A saves.
    await press(t, LogicalKeyboardKey.keyO);
    expect(find.text('Save Opening Stock'), findsOneWidget);
    await type(t, '20');
    await enter(t);
    await type(t, '10');
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyA);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.text('Save Opening Stock'), findsNothing);

    // ---- N = new entry, Tally style.
    await press(t, LogicalKeyboardKey.keyN);
    expect(find.byType(EntryPage), findsOneWidget);
    expect(focusedKey(), 'company');
    await type(t, 'Sharma Steel');
    await enter(t);
    expect(find.text('New company?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter); // Yes
    expect(focusedKey(), 'challan');
    // Going back: Backspace in an empty box (or Up) = the box before.
    await press(t, LogicalKeyboardKey.backspace);
    expect(focusedKey(), 'company');
    await enter(t); // same company again
    expect(focusedKey(), 'challan');
    await type(t, '101');
    await enter(t);
    await press(t, LogicalKeyboardKey.keyY); // bill made
    expect(find.text('Yes - bill made'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(focusedKey(), 'gasPick0');
    await type(t, 'o2');
    await enter(t); // O2 from the list
    expect(focusedKey(), 'lineQty0_0');
    await type(t, '4');
    await enter(t);
    expect(focusedKey(), 'lineQty0_1');
    await type(t, '3');
    await enter(t);
    expect(focusedKey(), 'gasPick1');
    await press(t, LogicalKeyboardKey.arrowUp); // (list) - Backspace goes back
    await press(t, LogicalKeyboardKey.backspace);
    expect(focusedKey(), 'lineQty0_1');
    await press(t, LogicalKeyboardKey.arrowUp);
    expect(focusedKey(), 'bill'); // first line: Up leaves the list
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(focusedKey(), 'gasPick0');
    await enter(t); // Oxygen stays
    await enter(t);
    await enter(t);
    expect(focusedKey(), 'gasPick1');
    await enter(t); // empty gas = End of List: on to cash
    expect(focusedKey(), 'cashType0');
    await enter(t); // no cash: save
    expect(find.text('Save this entry?'), findsOneWidget);
    expect(find.text('Oxygen 4'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter); // Yes
    expect(find.byKey(const Key('savedBanner')), findsOneWidget);
    expect(focusedKey(), 'company'); // ready for the next company
    // Typing letter by letter right after a save stays in Company (the
    // 'Saved' message going away must not take the cursor away).
    await type(t, 'P');
    expect(focusedKey(), 'company');
    await type(t, 'Pa');
    expect(focusedKey(), 'company');
    expect(find.byKey(const Key('savedBanner')), findsNothing);

    // Esc on a half-typed entry asks first; N = stay.
    await type(t, 'Pat');
    // (an open company list closes on the first Esc)
    for (
      var i = 0;
      i < 2 && find.text('Quit without saving?').evaluate().isEmpty;
      i++
    ) {
      await press(t, LogicalKeyboardKey.escape);
    }
    expect(find.text('Quit without saving?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.keyN);
    expect(find.byType(EntryPage), findsOneWidget);
    for (
      var i = 0;
      i < 2 && find.text('Quit without saving?').evaluate().isEmpty;
      i++
    ) {
      await press(t, LogicalKeyboardKey.escape);
    }
    await press(t, LogicalKeyboardKey.keyY); // quit
    expect(find.byType(EntryPage), findsNothing);

    // ---- F = filling, step by step: 8 sent and later 2 more; 5 back and
    // later 3 more. Each number + Enter is added; Enter on empty moves on.
    await press(t, LogicalKeyboardKey.keyF);
    await press(t, LogicalKeyboardKey.enter); // Add plant / gas
    await type(t, 'Ambika');
    await enter(t); // new plant added
    expect(focusedKey(), 'plantGas0');
    await enter(t); // Oxygen (already chosen)
    expect(focusedKey(), 'plantSent0');
    await type(t, '8');
    await enter(t);
    await type(t, '2');
    await enter(t);
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('= 10'), findsOneWidget);
    expect(focusedKey(), 'plantSent0');
    await enter(t); // empty: next box
    expect(focusedKey(), 'plantFilled0');
    await type(t, '5');
    await enter(t);
    await type(t, '3');
    expect(
      find.text('0 + 8 + 2 − 5 − 3 = 2'),
      findsOneWidget,
    ); // typed 3 counts
    await enter(t);
    await enter(t); // empty on the last line: save?
    expect(find.text('Save filling?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.text('Save Filling'), findsNothing);

    // ---- K = stock shows every filling and the total.
    await press(t, LogicalKeyboardKey.keyK);
    expect(find.text('+5 +3'), findsOneWidget);
    expect(find.text('= +8'), findsOneWidget);
    expect(find.text('0 + 8 + 2 − 5 − 3 = 2'), findsOneWidget);

    // ---- X = damaged: 1 empty + 1 full Oxygen become damaged, then one is
    // repaired back into Oxygen. The gas is only chosen from the list: a
    // letter jumps to the gas, nothing can be written. LPG can't be a repair.
    await press(t, LogicalKeyboardKey.keyX);
    expect(focusedKey(), 'gasPick0');
    // The list stays closed until asked for (it would cover the page).
    expect(find.text('Choose gas  (↑ ↓, Enter)'), findsNothing);
    await press(t, LogicalKeyboardKey.keyO); // opens the list on Oxygen
    expect(find.text('Choose gas  (↑ ↓, Enter)'), findsOneWidget);
    expect(
      t.widget<EditableText>(_focusedBox()).controller.text,
      '',
    ); // not written
    await press(t, LogicalKeyboardKey.enter);
    expect(focusedKey(), 'lineQty0_0');
    await type(t, '1');
    await enter(t);
    await type(t, '1');
    await enter(t);
    expect(focusedKey(), 'gasPick1');
    await press(t, LogicalKeyboardKey.enter); // End of List: on to "Repaired"
    await press(t, LogicalKeyboardKey.keyL); // LPG / LC can't be repaired into
    expect(find.text('LPG'), findsNothing);
    await press(t, LogicalKeyboardKey.keyO);
    await press(t, LogicalKeyboardKey.enter);
    await type(t, '1');
    await enter(t);
    await press(t, LogicalKeyboardKey.enter); // End of List: save?
    expect(find.text('Save damaged cylinders?'), findsOneWidget);
    // Each damaged cylinder keeps its gas.
    expect(
      find.textContaining('Oxygen:  0 + 2 (1 empty + 1 full) − 1 repaired = 1'),
      findsOneWidget,
    );
    expect(find.textContaining('Total damaged: 1'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.text('Save Damaged Cylinders'), findsNothing);
    // Stock: a Damaged row at the bottom of the table.
    await t.scrollUntilVisible(
      find.byKey(const Key('damagedRow')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(StockTab),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    String textOf(String k) => t.widget<Text>(find.byKey(Key(k))).data!;
    expect(textOf('damagedStart'), '0');
    expect(textOf('damagedTodayCount'), '+2');
    expect(textOf('damagedRepaired'), '−1');
    expect(textOf('damagedTotal'), '1');
    expect(textOf('damagedTodayGases'), 'today: Oxygen 2');
    expect(textOf('damagedByGas'), 'Oxygen 1');
    expect(
      find.text('−1 damaged'),
      findsOneWidget,
    ); // under Oxygen closing full

    // X again: the cursor waits on the empty line, never on the saved
    // Oxygen line (choosing a gas there would replace it).
    await press(t, LogicalKeyboardKey.keyX);
    expect(focusedKey(), 'gasPick1');
    await press(t, LogicalKeyboardKey.escape); // closes the list
    await press(t, LogicalKeyboardKey.escape); // leaves (nothing changed)
    expect(find.text('Save Damaged Cylinders'), findsNothing);

    // ---- S = supply list: Space switches the bill mark.
    await press(t, LogicalKeyboardKey.keyS);
    expect(find.text('Sharma Steel'), findsOneWidget);
    await press(t, LogicalKeyboardKey.space);
    expect(find.text('Sharma Steel: bill to be made later'), findsOneWidget);

    // ---- D = dashboard shows it as a pending bill; Enter opens it.
    await press(t, LogicalKeyboardKey.keyD);
    expect(
      t
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('statBills')),
              matching: find.text('1'),
            ),
          )
          .data,
      '1',
    );
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byType(EntryPage), findsOneWidget);
    await press(t, LogicalKeyboardKey.escape);
    await press(t, LogicalKeyboardKey.escape);
    expect(find.byType(EntryPage), findsNothing);

    // ---- dates: ← = previous day (clearly marked OLD DATE), T = today.
    await press(t, LogicalKeyboardKey.escape); // back to the menu
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(find.text('OLD DATE'), findsOneWidget);
    expect(find.byKey(const Key('oldDateStrip')), findsOneWidget);
    await press(t, LogicalKeyboardKey.keyT);
    expect(find.text('TODAY'), findsOneWidget);

    // G = go to a typed date.
    await press(t, LogicalKeyboardKey.keyG);
    await type(t, fmtDmy(today().subtract(const Duration(days: 3))));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('OLD DATE'), findsOneWidget);
    expect(find.textContaining('3 days ago'), findsWidgets);
    await press(t, LogicalKeyboardKey.keyT);

    // ---- Q = log out, Enter = yes.
    await press(t, LogicalKeyboardKey.keyQ);
    expect(find.text('Log out?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(const Key('loginButton')), findsOneWidget);
    expect(focusedKey(), 'username');
  });

  testWidgets(
    'PC: a save that is refused can be fixed and saved with the keyboard',
    (t) async {
      t.view.physicalSize = const Size(1366, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        DailyReportApp(
          env: AppEnv(
            auth: FakeAuthService(signedInAs: 'papa'),
            openDb: () async => MemoryLocalDb(),
            newRemote: FakeRemote.new,
            autoSync: false,
          ),
        ),
      );
      await t.pumpAndSettle();

      // No stock at all yet: supplying Oxygen is refused.
      await press(t, LogicalKeyboardKey.keyN);
      await type(t, 'Sharma Steel');
      await enter(t);
      await press(t, LogicalKeyboardKey.enter); // yes, new company
      await type(t, '54');
      await enter(t);
      await press(t, LogicalKeyboardKey.enter); // bill: no
      await type(t, 'oxy');
      await enter(t);
      await type(t, '22');
      await enter(t);
      await enter(t);
      expect(focusedKey(), 'gasPick1');
      await enter(t); // End of List
      expect(focusedKey(), 'cashType0');
      await enter(t); // End of List: save?
      expect(find.text('Save this entry?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter); // yes
      expect(find.text('Cannot go below zero'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter); // OK
      expect(find.text('Cannot go below zero'), findsNothing);
      expect(focusedKey(), 'cashType0');

      // Back to the gas list and "End of List" again (it was picked before:
      // it must still work), then the cash "End of List" again.
      await press(t, LogicalKeyboardKey.backspace);
      expect(focusedKey(), 'gasPick1');
      await enter(t);
      expect(focusedKey(), 'cashType0');
      await enter(t);
      expect(find.text('Save this entry?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.escape); // no: back to cash
      expect(focusedKey(), 'cashType0');

      // Fix the numbers by going back: 0 full and 3 empty instead.
      await press(t, LogicalKeyboardKey.backspace); // gas line 2
      expect(focusedKey(), 'gasPick1');
      await press(t, LogicalKeyboardKey.backspace); // Oxygen empty (empty box)
      expect(focusedKey(), 'lineQty0_1');
      await press(t, LogicalKeyboardKey.backspace); // Oxygen full
      expect(focusedKey(), 'lineQty0_0');
      await type(t, '');
      await enter(t);
      expect(focusedKey(), 'lineQty0_1');
      await type(t, '3');
      await enter(t);
      expect(focusedKey(), 'gasPick1');
      await enter(t);
      expect(focusedKey(), 'cashType0');
      await enter(t);
      expect(find.text('Save this entry?'), findsOneWidget);
      // Only empties now: no bill needed, and no stock problem.
      expect(find.text('Not needed (only empty received)'), findsOneWidget);
    },
  );

  testWidgets(
    'PC: removing a gas line with the keyboard leaves the next line clean',
    (t) async {
      t.view.physicalSize = const Size(1366, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        DailyReportApp(
          env: AppEnv(
            auth: FakeAuthService(signedInAs: 'papa'),
            openDb: () async => MemoryLocalDb(),
            newRemote: FakeRemote.new,
            autoSync: false,
          ),
        ),
      );
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.keyN);
      await type(t, 'Patel');
      await enter(t);
      await press(t, LogicalKeyboardKey.enter); // yes, new company
      await type(t, '61');
      await enter(t);
      await press(t, LogicalKeyboardKey.enter); // bill
      await type(t, 'oxy');
      await enter(t);
      await type(t, '2');
      await enter(t);
      await type(t, '1');
      await enter(t);
      await type(t, 'co2');
      await enter(t);
      expect(focusedKey(), 'lineQty1_0');
      await press(t, LogicalKeyboardKey.backspace); // back to the CO2 gas box
      expect(focusedKey(), 'gasPick1');
      await type(t, ''); // erase the name
      expect(find.text('Remove this line'), findsOneWidget);
      await enter(t);
      // The CO2 line is gone; the empty line moved up and is really empty.
      expect(focusedKey(), 'gasPick1');
      final box = t.widget<EditableText>(_focusedBox());
      expect(box.controller.text, '');
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'CO2',
        ),
        findsNothing,
      );
      await enter(t); // End of List
      expect(focusedKey(), 'cashType0');
      await enter(t);
      expect(find.text('Save this entry?'), findsOneWidget);
    },
  );

  test('typed dates', () {
    final now = DateTime(2026, 10, 15);
    expect(parseTypedDate('12', now: now), DateTime(2026, 10, 12));
    expect(parseTypedDate('12-10', now: now), DateTime(2026, 10, 12));
    expect(parseTypedDate('12/10/26', now: now), DateTime(2026, 10, 12));
    expect(parseTypedDate('1.4.2026', now: now), DateTime(2026, 4, 1));
    expect(parseTypedDate('16', now: now), isNull); // future
    expect(parseTypedDate('31-02-2026', now: now), isNull);
    expect(parseTypedDate('abc', now: now), isNull);
  });
  testWidgets(
    'PC: old DA shows under Aims Oxygen; DA is typed in its plant line',
    (t) async {
      t.view.physicalSize = const Size(1366, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final date = dayKey(today());
      final month = date.substring(0, 7);
      final db = MemoryLocalDb();
      // Written before DA had a plant line: DA filled 5, DA empty given 6.
      db.rows['plant/p_aims'] = const LocalRow(
        Rec(Kind.plant, 'p_aims', {'name': 'Aims Oxygen P Ltd'}),
      );
      db.rows['day/$date'] = LocalRow(
        Rec(Kind.day, date, {
          'openFull': {'DA': 10},
          'openEmpty': {'DA': 20},
          'filling': {'DA': 5},
          'daEmptyGiven': 6,
        }),
      );
      await t.pumpWidget(
        DailyReportApp(
          env: AppEnv(
            auth: FakeAuthService(signedInAs: 'papa'),
            openDb: () async => db,
            newRemote: FakeRemote.new,
            autoSync: false,
          ),
        ),
      );
      await t.pumpAndSettle();
      String textOf(String k) => t.widget<Text>(find.byKey(Key(k))).data!;

      // ---- L = filling report: the old DA is at Aims Oxygen.
      await press(t, LogicalKeyboardKey.keyL);
      expect(find.byKey(const Key('plantRow_p_aims')), findsOneWidget);
      expect(textOf('plantFilled_p_aims'), '5');
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('EMPTY CYLINDERS AT THIS PLANT NOW'), findsOneWidget);
      expect(textOf('plantTotalFilled'), '5');
      expect(textOf('plantTotalSent'), '6');
      expect(
        textOf('plantNow'),
        '0 cylinders',
      ); // DA is swapped, none wait there

      // ---- Enter on the day: its filling, DA in the Aims line.
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('Save Filling'), findsOneWidget);
      expect(focusedKey(), 'plantSent0');
      expect(find.text('Aims Oxygen P Ltd'), findsWidgets);
      await type(t, '1');
      await enter(t); // 6 + 1 empty sent
      await enter(t);
      expect(focusedKey(), 'plantFilled0');
      await type(t, '2');
      await enter(t); // 5 + 2 filled back
      await enter(t); // last box: save?
      expect(find.text('Save filling?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('Save Filling'), findsNothing);
      expect(textOf('plantTotalFilled'), '7');
      expect(textOf('plantTotalSent'), '7');

      // Kept in the day (same DA logic), and Aims is remembered.
      expect(db.rows['day/$date']!.rec.data['daPlant'], 'p_aims');
      expect(db.rows['day/$date']!.rec.data['daEmptyGiven'], 7);
      expect(db.rows['setting/daPlant']!.rec.data, {
        'id': 'p_aims',
        'old': 'p_aims',
      });

      // ---- M = month-wise; Enter = that month's days; Backspace = up.
      await press(t, LogicalKeyboardKey.keyM);
      expect(find.byKey(Key('plantRow_$month')), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.byKey(Key('plantRow_$date')), findsOneWidget);
      await press(t, LogicalKeyboardKey.backspace);
      expect(find.byKey(Key('plantRow_$month')), findsOneWidget);
      await press(t, LogicalKeyboardKey.backspace);
      expect(textOf('plantPeriod'), 'All years');
      await press(t, LogicalKeyboardKey.keyD);
      expect(find.byKey(Key('plantRow_$date')), findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      expect(find.text('EMPTY CYLINDERS AT THIS PLANT NOW'), findsNothing);

      // ---- F = filling again: still one DA line, at Aims.
      await press(t, LogicalKeyboardKey.keyF);
      expect(find.byKey(const Key('plantSent0')), findsOneWidget);
      expect(find.byKey(const Key('plantSent1')), findsNothing);
    },
  );
  testWidgets(
    'PC: DA can be written at another plant when the Aims DA line is empty',
    (t) async {
      t.view.physicalSize = const Size(1366, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final date = dayKey(today());
      final db = MemoryLocalDb();
      db.rows['plant/p_aims'] = const LocalRow(
        Rec(Kind.plant, 'p_aims', {'name': 'Aims Oxygen P Ltd'}),
      );
      db.rows['plant/p_other'] = const LocalRow(
        Rec(Kind.plant, 'p_other', {'name': 'Other Gases'}),
      );
      db.rows['day/$date'] = LocalRow(
        Rec(Kind.day, date, {
          'openEmpty': {'DA': 10},
        }),
      );
      await t.pumpWidget(
        DailyReportApp(
          env: AppEnv(
            auth: FakeAuthService(signedInAs: 'papa'),
            openDb: () async => db,
            newRemote: FakeRemote.new,
            autoSync: false,
          ),
        ),
      );
      await t.pumpAndSettle();

      await press(t, LogicalKeyboardKey.keyF);
      expect(focusedKey(), 'plantSent0'); // the empty DA line at Aims
      await enter(t);
      await enter(t);
      expect(find.text('Save filling?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.keyA); // add a plant line
      await type(t, 'Other');
      await enter(t);
      expect(focusedKey(), 'plantGas1');
      await type(t, 'da');
      await enter(t);
      expect(focusedKey(), 'plantSent1');
      await type(t, '3');
      await enter(t);
      await enter(t);
      await type(t, '2');
      await enter(t);
      await enter(t);
      expect(find.text('Save filling?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('Save Filling'), findsNothing);

      final day = db.rows['day/$date']!.rec.data;
      expect(day['daPlant'], 'p_other');
      expect(day['daEmptyGiven'], 3);
      expect(day['filling'], {'DA': 2});
      // Next time DA starts at the new plant; old days stay at Aims.
      expect(db.rows['setting/daPlant']!.rec.data, {
        'id': 'p_other',
        'old': 'p_aims',
      });
    },
  );
  testWidgets(
    'Phone: the damaged gas list opens only when tapped and closes again',
    (t) async {
      t.view.physicalSize = const Size(411, 860) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final date = dayKey(today());
      final db = MemoryLocalDb();
      db.rows['day/$date'] = LocalRow(
        Rec(Kind.day, date, {
          'openEmpty': {'O2': 5, 'CO2': 5},
        }),
      );
      await t.pumpWidget(
        DailyReportApp(
          env: AppEnv(
            auth: FakeAuthService(signedInAs: 'papa'),
            openDb: () async => db,
            newRemote: FakeRemote.new,
            autoSync: false,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('Stock')),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('damagedRow')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(StockTab),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.ensureVisible(find.byKey(const Key('damagedRow')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('damagedRow')));
      await t.pumpAndSettle();
      const listTitle = 'Choose gas  (↑ ↓, Enter)';
      expect(find.text('Save Damaged Cylinders'), findsOneWidget);
      expect(find.text(listTitle), findsNothing); // nothing covers the page

      // Tap the box: the list opens; tap a gas: it closes, on to the number.
      await t.tap(_inDeclared('gasPick0'));
      await t.pumpAndSettle();
      expect(find.text(listTitle), findsOneWidget);
      await t.tap(
        find.descendant(
          of: find.byType(ChoiceList<GasChoice>),
          matching: find.text('Oxygen'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(listTitle), findsNothing);
      expect(focusedKey(), 'lineQty0_0');

      // Opened again, then a tap anywhere else closes it.
      await t.tap(_inDeclared('gasPick1'));
      await t.pumpAndSettle();
      expect(find.text(listTitle), findsOneWidget);
      await t.tap(find.textContaining('Damaged Cylinders  ·'));
      await t.pumpAndSettle();
      expect(find.text(listTitle), findsNothing);
      // Nothing was written in the box.
      expect(
        find.descendant(
          of: _inDeclared('gasPick1'),
          matching: find.byType(EditableText),
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<EditableText>(
              find.descendant(
                of: _inDeclared('gasPick1'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '',
      );
    },
  );
  testWidgets(
    'PC: loan cylinders taken from a plant, supplied, and shown apart',
    (t) async {
      t.view.physicalSize = const Size(1366, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final date = dayKey(today());
      final db = MemoryLocalDb();
      db.rows['plant/p_abc'] = const LocalRow(
        Rec(Kind.plant, 'p_abc', {'name': 'ABC Plant'}),
      );
      db.rows['company/c_sh'] = const LocalRow(
        Rec(Kind.company, 'c_sh', {'name': 'Sharma Steel'}),
      );
      db.rows['day/$date'] = LocalRow(
        Rec(Kind.day, date, {
          'openFull': {'AR_COMM': 5},
        }),
      );
      await t.pumpWidget(
        DailyReportApp(
          env: AppEnv(
            auth: FakeAuthService(signedInAs: 'papa'),
            openDb: () async => db,
            newRemote: FakeRemote.new,
            autoSync: false,
          ),
        ),
      );
      await t.pumpAndSettle();

      // ---- B = loan cylinders: 20 ARGON taken from ABC Plant.
      await press(t, LogicalKeyboardKey.keyB);
      expect(find.text('Save Loan Cylinders'), findsOneWidget);
      await press(
        t,
        LogicalKeyboardKey.enter,
      ); // add plant / gas (one plant: ABC)
      expect(focusedKey(), 'loanGas0');
      await type(t, 'argon');
      await enter(t);
      expect(focusedKey(), 'loanTaken0');
      await type(t, '20');
      await enter(t);
      await enter(t); // on to "given back empty"
      await enter(t); // on to "given back full"
      await enter(t); // last box: save?
      expect(find.text('Save loan cylinders?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('Save Loan Cylinders'), findsNothing);
      expect(db.rows['day/$date']!.rec.data['loanIn'], {
        'AR_COMM': {'p_abc': 20},
      });

      // ---- N = entry: 10 loan ARGON to Sharma Steel (none of ours).
      await press(t, LogicalKeyboardKey.keyN);
      await type(t, 'Sharma');
      await enter(t);
      expect(focusedKey(), 'challan');
      await type(t, '77');
      await enter(t);
      await press(t, LogicalKeyboardKey.enter); // bill: not made
      expect(
        find.text('Loan cylinders  (borrowed from a plant)'),
        findsOneWidget,
      );
      await enter(t); // our gas lines: none, on to loan
      await type(t, 'arg');
      expect(find.text('ARGON · ABC Plant'), findsWidgets);
      await enter(t);
      await type(t, '10');
      await enter(t);
      await enter(t); // no loan empties back
      await enter(t); // end of the loan list: to cash
      expect(focusedKey(), 'cashType0');
      await enter(t);
      expect(find.text('Save this entry?'), findsOneWidget);
      expect(find.text('LOAN full supplied'), findsOneWidget);
      expect(find.text('ARGON 10 (ABC Plant)'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      // Leave the fresh entry (the first Esc may only close its company list).
      for (
        var i = 0;
        i < 3 && find.byType(EntryPage).evaluate().isNotEmpty;
        i++
      ) {
        await press(t, LogicalKeyboardKey.escape);
      }
      expect(find.byType(EntryPage), findsNothing);
      final saved = db.rows.values
          .where((r) => r.rec.kind == Kind.entry && !r.rec.deleted)
          .single
          .rec
          .data;
      expect(saved['loanFull'], {
        'AR_COMM': {'p_abc': 10},
      });
      expect(saved['full'], isEmpty);

      // ---- K = stock: our ARGON untouched, the loan line under it.
      await press(t, LogicalKeyboardKey.keyK);
      String textOf(String k) => t.widget<Text>(find.byKey(Key(k))).data!;
      expect(textOf('loanFull_p_abc'), '0 + 20 − 10 = 10');
      expect(
        find.text('with companies 10  ·  to give back 20'),
        findsOneWidget,
      );

      // ---- C = companies: Sharma Steel has 10 loan ARGON.
      await press(t, LogicalKeyboardKey.keyC);
      expect(find.textContaining('LOAN  ARGON 10 (ABC Plant)'), findsOneWidget);
    },
  );
  testWidgets(
    'PC: vehicle papers remind daily; renew and add with the keyboard',
    (t) async {
      t.view.physicalSize = const Size(1366, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      String inDays(int n) => dayKey(today().add(Duration(days: n)));
      final db = MemoryLocalDb();
      db.rows['setting/vehicle_v1'] = LocalRow(
        Rec(Kind.setting, 'vehicle_v1', {
          'number': 'GJ 01 AB 1234',
          'papers': [
            {
              'id': 'puc',
              'type': 'PUC',
              'from': inDays(-170),
              'till': inDays(6),
            },
            {'id': 'ins', 'type': 'Insurance', 'till': inDays(-2)},
          ],
        }),
      );
      await t.pumpWidget(
        DailyReportApp(
          env: AppEnv(
            auth: FakeAuthService(signedInAs: 'papa'),
            openDb: () async => db,
            newRemote: FakeRemote.new,
            autoSync: false,
          ),
        ),
      );
      await t.pumpAndSettle();

      // ---- On opening: the day's reminder, the expired one marked URGENT.
      expect(find.text('URGENT: vehicle papers to renew'), findsOneWidget);
      expect(
        find.textContaining('URGENT – RENEW  ·  expired 2 days ago'),
        findsWidgets,
      );
      expect(find.textContaining('RENEW SOON  ·  6 days left'), findsWidgets);
      await press(t, LogicalKeyboardKey.keyV); // open the vehicles
      expect(find.text('Vehicles & Papers'), findsOneWidget);

      // ---- Enter = the vehicle; Enter on the expired insurance = Renewed.
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('Add paper (N)'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter); // soonest first: Insurance
      expect(find.textContaining('Renewed: Insurance'), findsOneWidget);
      expect(focusedKey(), 'paperTill');
      final till = today().add(const Duration(days: 365));
      await type(t, fmtDmy(till));
      await enter(t);
      expect(find.text('Save the renewed Insurance?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      final saved = db.rows['setting/vehicle_v1']!.rec.data;
      final ins = (saved['papers'] as List).cast<Map>().firstWhere(
        (p) => p['id'] == 'ins',
      );
      expect(ins['till'], dayKey(till));
      expect(
        ins['from'],
        dayKey(today()),
      ); // it had run out: new one from today
      expect(ins.containsKey('history'), isFalse); // old dates not kept

      // ---- N = another paper: Fitness, typed dates.
      await press(t, LogicalKeyboardKey.keyN);
      expect(focusedKey(), 'paperType');
      await type(t, 'fit');
      await enter(t);
      expect(focusedKey(), 'paperFrom');
      await type(t, fmtDmy(today()));
      await enter(t);
      await type(t, fmtDmy(today().add(const Duration(days: 8))));
      await enter(t);
      expect(find.text('Save Fitness (FC)?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('Fitness (FC)'), findsOneWidget);

      // ---- Back home: the Dashboard lists what is left to renew.
      await press(t, LogicalKeyboardKey.escape);
      await press(t, LogicalKeyboardKey.escape);
      await press(t, LogicalKeyboardKey.keyD);
      expect(find.text('VEHICLE PAPERS TO RENEW  (2)'), findsOneWidget);
      expect(
        t
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('statPapers')),
                matching: find.text('2'),
              ),
            )
            .data,
        '2',
      );
      // The reminder box does not come again the same day.
      expect(find.byType(AlertDialog), findsNothing);

      // ---- V, N: a new vehicle goes straight to its first paper.
      await press(t, LogicalKeyboardKey.keyV);
      await press(t, LogicalKeyboardKey.keyN);
      await type(t, 'gj 01 cd 5678');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(focusedKey(), 'paperType');
      await type(t, 'puc');
      await enter(t);
      await enter(t); // from: left empty
      await type(t, fmtDmy(today().add(const Duration(days: 180))));
      await enter(t);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('GJ 01 CD 5678'), findsOneWidget);
      expect(find.text('Valid · 180 days left'), findsOneWidget);
    },
  );
}
