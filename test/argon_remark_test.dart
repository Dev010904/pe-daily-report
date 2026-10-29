import 'dart:io';

import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/records.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/export/day_pdf.dart';
import 'package:daily_report/export/plant_pdf.dart';
import 'package:daily_report/logic/plant_report.dart';
import 'package:daily_report/main.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:daily_report/models/gas.dart';
import 'package:daily_report/util/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Finder _focusedBox() => find.byWidgetPredicate(
  (w) => w is EditableText && w.focusNode.hasFocus,
  skipOffstage: false,
);

Future<void> type(WidgetTester t, String text) async {
  await t.enterText(_focusedBox(), text);
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t) async {
  await t.showKeyboard(_focusedBox());
  await t.testTextInput.receiveAction(TextInputAction.next);
  await t.pumpAndSettle();
}

Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pumpAndSettle();
}

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

String _richText(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(Key(key))).textSpan!.toPlainText();

void main() {
  test('stock note: saved, kept on the next days, changed, cleared', () async {
    final store = await newStore();
    await store.saveDay(DayData('2026-10-01', openFull: {kArgon: 10}));
    expect(store.stockRemarkOn('2026-10-01', kArgon), isNull);

    await store.setStockRemark('2026-10-02', kArgon, ' SPL 4 FULL ');
    expect(store.stockRemarkOn('2026-10-01', kArgon), isNull);
    expect(store.stockRemarkOn('2026-10-02', kArgon), (
      text: 'SPL 4 FULL',
      from: '2026-10-02',
    ));
    // Carried on, also to days with nothing saved.
    expect(store.stockRemarkOn('2026-10-09', kArgon)?.from, '2026-10-02');

    await store.setStockRemark('2026-10-05', kArgon, 'SPL 2 FULL');
    expect(store.stockRemarkOn('2026-10-04', kArgon)?.text, 'SPL 4 FULL');
    expect(store.stockRemarkOn('2026-10-07', kArgon)?.text, 'SPL 2 FULL');

    // Cleared on the 8th: none from then on, the 5th is unchanged.
    await store.setStockRemark('2026-10-08', kArgon, '');
    expect(store.stockRemarkOn('2026-10-08', kArgon), isNull);
    expect(store.stockRemarkOn('2026-10-20', kArgon), isNull);
    expect(store.stockRemarkOn('2026-10-06', kArgon)?.text, 'SPL 2 FULL');
    expect(store.day('2026-10-08').stockRemarks, {kArgon: ''});

    // Clearing a note written that day with nothing before it: no trace.
    await store.setStockRemark('2026-09-20', kArgon, 'X');
    await store.setStockRemark('2026-09-20', kArgon, '');
    expect(store.day('2026-09-20').stockRemarks, isEmpty);
    expect(store.day('2026-09-20').metaEmpty, isTrue);

    // The stock itself does not change.
    expect(store.stock('2026-10-09').row(kArgon).closeFull, 10);

    // Saved and read back the same.
    final d = store.day('2026-10-08');
    expect(DayData.fromMeta(d.date, d.metaJson()).stockRemarks, {kArgon: ''});
  });

  test(
    'filling notes are kept per plant line and in the plant report',
    () async {
      final store = await newStore();
      final p = await store.addPlant('Ambika');
      await store.saveDay(
        DayData(
          '2026-10-01',
          openEmpty: {kArgon: 10},
          plantSent: {
            kArgon: {p.id: 5},
          },
          fillingRemarks: {fillingRemarkKey(kArgon, p.id): 'SPL 3'},
        ),
      );
      final day = store.day('2026-10-01');
      expect(day.fillingRemarkOf(kArgon, p.id), 'SPL 3');
      final days = store.plantDays(p.id);
      expect(days.single.remarks, {kArgon: 'SPL 3'});
      // Not added up into months.
      expect(groupPlantDays(days, PlantGroup.month).single.remarks, isEmpty);
      // Cleared together with the rest of the filling.
      day.clearFilling();
      expect(day.fillingRemarks, isEmpty);
    },
  );

  testWidgets('PC: M = ARGON remark on the stock; ARGON filling has Remarks', (
    t,
  ) async {
    t.view.physicalSize = const Size(1366, 768) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final date = dayKey(today());
    final yesterday = dayKey(today().subtract(const Duration(days: 1)));
    final db = MemoryLocalDb();
    db.rows['plant/p1'] = const LocalRow(
      Rec(Kind.plant, 'p1', {'name': 'Ambika'}),
    );
    db.rows['day/$yesterday'] = LocalRow(
      Rec(Kind.day, yesterday, {
        'openFull': {kArgon: 10, 'O2': 4},
        'openEmpty': {kArgon: 6, 'O2': 3},
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

    // ---- K = stock: ARGON has an empty remark line.
    await press(t, LogicalKeyboardKey.keyK);
    expect(find.byKey(const Key('argonRemarkRow')), findsOneWidget);
    expect(find.byKey(const Key('argonRemarkText')), findsNothing);

    // ---- M = write it; Enter saves.
    await press(t, LogicalKeyboardKey.keyM);
    expect(find.text('ARGON remark (stock)'), findsOneWidget);
    expect(focusedKey(), 'argonRemarkField');
    await type(t, 'SPL 4 FULL, 2 EMPTY');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('ARGON remark (stock)'), findsNothing);
    expect(_richText(t, 'argonRemarkText'), 'SPL 4 FULL, 2 EMPTY');
    expect(db.rows['day/$date']!.rec.data['stockRemarks'], {
      kArgon: 'SPL 4 FULL, 2 EMPTY',
    });

    // ---- The day before has none; Right = back to today.
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(const Key('argonRemarkText')), findsNothing);
    await press(t, LogicalKeyboardKey.arrowRight);

    // ---- F = filling: ARGON line - sent, filled back, Remarks, next.
    await press(t, LogicalKeyboardKey.keyF);
    await press(t, LogicalKeyboardKey.enter); // no lines yet: add one
    expect(focusedKey(), 'plantGas0'); // the only plant is taken
    // Oxygen first: no Remarks box (only ARGON has one).
    expect(find.byKey(const Key('plantRemark0')), findsNothing);
    await type(t, 'argon');
    await enter(t);
    expect(focusedKey(), 'plantSent0');
    expect(find.byKey(const Key('plantRemark0')), findsOneWidget);
    await type(t, '5');
    await enter(t);
    await enter(t);
    expect(focusedKey(), 'plantFilled0');
    await type(t, '3');
    await enter(t);
    await enter(t);
    expect(focusedKey(), 'plantRemark0');
    await type(t, 'SPL 2');
    await enter(t);
    expect(find.text('Save filling?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.text('Save Filling'), findsNothing);
    final saved = db.rows['day/$date']!.rec.data;
    expect(saved['fillingRemarks'], {'$kArgon|p1': 'SPL 2'});
    expect(saved['stockRemarks'], {kArgon: 'SPL 4 FULL, 2 EMPTY'});

    // The stock's ARGON plant line shows it.
    expect(_richText(t, 'plantRowName_${kArgon}_p1'), 'Ambika  · SPL 2');

    // ---- Filling opened again: the note is there.
    await press(t, LogicalKeyboardKey.keyF);
    final box = find.byKey(const Key('plantRemark0'));
    expect(t.widget<TextField>(box).controller!.text, 'SPL 2');
    await press(t, LogicalKeyboardKey.escape);
    expect(find.text('Save Filling'), findsNothing);

    // ---- M again: Clear.
    await press(t, LogicalKeyboardKey.keyM);
    await t.tap(find.byKey(const Key('argonRemarkClear')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('argonRemarkText')), findsNothing);
    expect(db.rows['day/$date']!.rec.data['stockRemarks'], isNull);
  });

  test('PDFs with the ARGON remarks', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final store = await newStore();
    final p = await store.addPlant('Ambika');
    await store.saveDay(
      DayData(
        '2026-10-01',
        openFull: {kArgon: 10},
        openEmpty: {kArgon: 6},
        plantSent: {
          kArgon: {p.id: 5},
        },
        plantFilled: {
          kArgon: {p.id: 3},
        },
        fillingRemarks: {fillingRemarkKey(kArgon, p.id): 'SPL 2'},
      ),
    );
    await store.setStockRemark('2026-10-01', kArgon, 'SPL 4 FULL, 2 EMPTY');
    await store.saveDay(DayData('2026-10-02'));
    final out = Directory('build/test_output')..createSync(recursive: true);
    for (final (name, bytes) in [
      ('day_argon.pdf', await buildDayPdf(store, ['2026-10-01', '2026-10-02'])),
      (
        'plant_argon.pdf',
        await buildPlantReportPdf(
          store,
          p.id,
          group: PlantGroup.day,
          period: 'October 2026',
        ),
      ),
    ]) {
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      File('${out.path}/$name').writeAsBytesSync(bytes);
    }
  });
}
