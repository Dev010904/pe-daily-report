// The pop-up lists must always be fully on the screen: below the box, or
// above it when the box is low on the screen.
import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _focusedBox() => find.byWidgetPredicate(
  (w) => w is EditableText && w.focusNode.hasFocus,
  skipOffstage: false,
);

void main() {
  testWidgets('a list near the bottom opens above its box, on screen', (
    t,
  ) async {
    t.view.physicalSize = const Size(1503, 766);
    t.view.devicePixelRatio = 1;
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
    Future<void> type(String s) async {
      await t.enterText(_focusedBox(), s);
      await t.pumpAndSettle();
    }

    Future<void> enter() async {
      await t.showKeyboard(_focusedBox());
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
    }

    await t.sendKeyEvent(LogicalKeyboardKey.keyN);
    await t.pumpAndSettle();
    await type('Patel');
    await enter();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await type('60');
    await enter();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await type('oxy');
    await enter();
    await type('3');
    await enter();
    await enter();
    await enter(); // remarks: none
    await enter(); // to cash
    await type('dep');
    await enter();
    await type('500');
    await enter();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    final field = t.getRect(find.byKey(const Key('cashType1')));
    final title = find.text('Cash Types');
    expect(title, findsOneWidget);
    final box = title.evaluate().single.renderObject! as RenderBox;
    final top = box.localToGlobal(Offset.zero).dy;
    expect(top, greaterThanOrEqualTo(0)); // not off the top of the screen
    expect(top, lessThan(field.top)); // above the box
    expect(find.text('End of List (save)'), findsOneWidget);
  });
}
