import 'dart:io';

import 'package:daily_report/data/auth.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/records.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/export/company_pdf.dart';
import 'package:daily_report/export/day_pdf.dart';
import 'package:daily_report/export/register_pdf.dart';
import 'package:daily_report/main.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:daily_report/models/purchase_order.dart';
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

void main() {
  test('extra full: off the godown empties, on to full stock', () async {
    final store = await newStore();
    await store.saveDay(
      DayData(
        '2026-10-01',
        openFull: {'O2': 5},
        openEmpty: {'O2': 10},
        extraFull: {'O2': 3},
      ),
    );
    final r = store.stock('2026-10-01').row('O2');
    expect(r.extraFull, 3);
    expect(r.closeFull, 8);
    expect(r.closeGodown, 7);
    expect(
      r.emptyCalcText(ascii: true, labelPlant: true),
      '10 - 3 (extra full) = 7',
    );
    expect(store.stock('2026-10-01').extraFullToday, {'O2': 3});
    // Carried on to the next day.
    expect(store.stock('2026-10-02').row('O2').openFull, 8);
    expect(store.stock('2026-10-02').row('O2').openGodown, 7);

    // More found full than there are empties: refused.
    final d = store.day('2026-10-01')..extraFull = {'O2': 11};
    final p = store.problemsIfSaved(d);
    expect(p, isNotEmpty);
    expect(p.first.message, contains('11 found full'));
    // Saved and read back the same.
    expect(
      DayData.fromMeta('x', store.day('2026-10-01').metaJson()).extraFull,
      {'O2': 3},
    );
  });

  test('purchase orders: supplied, left, alerts, links', () async {
    final store = await newStore();
    final c = await store.addCompany('Sharma Steel');
    final other = await store.addCompany('Patel');
    expect(store.hasPos(c.id), isFalse);
    expect(store.defaultPo(c.id), isNull);

    final a = await store.addPo(c.id, '4500', {'O2': 10, 'CO2': 5});
    final b = await store.addPo(c.id, '4600', {'O2': 20});
    final co2 = await store.addPo(c.id, '7700', {'CO2': 50});
    expect(store.posOf(c.id).map((p) => p.number), ['4500', '4600', '7700']);
    expect(store.hasPos(other.id), isFalse);
    expect(store.defaultPo(c.id), a.id);

    // Chosen PO has the gas: it; else the oldest PO still open for it.
    expect(store.poLinksFor(c.id, ['O2', 'CO2', 'N2_COMM'], chosen: b.id), {
      'O2': b.id,
      'CO2': a.id,
    });
    expect(store.poLinksFor(c.id, ['O2'], chosen: kNoPo), isEmpty);

    Entry supply(String id, Map<String, int> full, Map<String, String> po) =>
        Entry(
          id: id,
          companyId: c.id,
          company: c.name,
          full: full,
          po: po,
          poNo: {for (final e in po.entries) e.key: store.po(e.value)!.number},
        );
    await store.saveDay(
      DayData(
        '2026-10-01',
        openFull: {'O2': 50, 'CO2': 50},
        entries: [
          supply('e1', {'O2': 9, 'CO2': 2}, {'O2': a.id, 'CO2': a.id}),
        ],
      ),
    );
    expect(store.poSupplied(a.id, 'O2'), 9);
    expect(store.poSupplied(a.id, 'O2', exceptEntry: 'e1'), 0);
    final l = store.poLine(a, 'O2');
    expect(l.left, 1);
    expect(l.nearlyDone, isTrue);
    expect(l.done, isFalse);
    expect(store.poAlerts().map((x) => '${x.po.number} ${x.gas}'), ['4500 O2']);

    // 2 more Oxygen: PO 4500 is done (over by 1); the next one is 4600.
    await store.saveDay(
      store.day('2026-10-01')
        ..entries.add(supply('e2', {'O2': 2}, {'O2': a.id})),
    );
    expect(store.poLine(a, 'O2').left, -1);
    expect(store.poAlerts().first.done, isTrue);
    expect(store.poLinksFor(c.id, ['O2']), {'O2': b.id});
    expect(store.defaultPo(c.id), a.id); // CO2 of 4500 is still open

    // Removed: no longer tracked, but the entry keeps the number.
    await store.removePo(a);
    expect(store.po(a.id), isNull);
    expect(store.posOf(c.id).map((p) => p.number), ['4600', '7700']);
    final e1 = store.day('2026-10-01').entries.firstWhere((e) => e.id == 'e1');
    expect(store.poNumberOf(e1, 'O2'), '4500');
    expect(store.poAlerts(), isEmpty);
    expect(co2.hasGas('CO2'), isTrue);

    // Kept when saved and read back.
    final back = Entry.fromJson('e1', e1.toJson());
    expect(back.po, {'O2': a.id, 'CO2': a.id});
    expect(back.poNo, {'O2': '4500', 'CO2': '4500'});
  });

  testWidgets('PC: U = extra full; PO added in Settings, used in an entry', (
    t,
  ) async {
    t.view.physicalSize = const Size(1366, 768) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final y = dayKey(today().subtract(const Duration(days: 1)));
    final db = MemoryLocalDb();
    db.rows['company/c1'] = const LocalRow(
      Rec(Kind.company, 'c1', {'name': 'Sharma Steel'}),
    );
    db.rows['day/$y'] = LocalRow(
      Rec(Kind.day, y, {
        'openFull': {'O2': 20},
        'openEmpty': {'O2': 5},
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

    // ---- U = extra full: 2 Oxygen "empties" were full.
    await press(t, LogicalKeyboardKey.keyU);
    expect(find.text('Save Extra Full Cylinders'), findsOneWidget);
    expect(focusedKey(), 'gasPick0');
    await press(t, LogicalKeyboardKey.keyO);
    await press(t, LogicalKeyboardKey.enter);
    await type(t, '2');
    await enter(t);
    expect(focusedKey(), 'gasPick1');
    await press(t, LogicalKeyboardKey.enter); // End of List: save?
    expect(find.text('Save extra full cylinders?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.text('Save Extra Full Cylinders'), findsNothing);
    await press(t, LogicalKeyboardKey.keyK);
    expect(find.text('+2 extra'), findsOneWidget);
    expect(find.text('22'), findsOneWidget); // 20 + 2 full
    expect(find.text('= 3'), findsOneWidget); // 5 − 2 empty

    // ---- No PO yet: the entry has no PO box.
    await press(t, LogicalKeyboardKey.keyN);
    await type(t, 'Sharma');
    await enter(t);
    expect(focusedKey(), 'challan');
    expect(find.byKey(const Key('poPick')), findsNothing);
    await press(t, LogicalKeyboardKey.escape);
    expect(find.text('Quit without saving?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter); // Quit

    // ---- E = Settings, C = Companies, O = its POs, N = new PO.
    await press(t, LogicalKeyboardKey.keyE);
    await press(t, LogicalKeyboardKey.keyC);
    expect(find.text('Sharma Steel'), findsOneWidget);
    await press(t, LogicalKeyboardKey.keyO);
    expect(find.textContaining('Purchase Orders  ·'), findsOneWidget);
    await press(t, LogicalKeyboardKey.keyN);
    expect(focusedKey(), 'poNumber');
    await type(t, '4500');
    await enter(t);
    expect(focusedKey(), 'gasPick0');
    await press(t, LogicalKeyboardKey.keyO);
    await press(t, LogicalKeyboardKey.enter);
    await type(t, '10');
    await enter(t);
    await press(t, LogicalKeyboardKey.enter); // End of List: save?
    expect(find.text('Save PO 4500?'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(const Key('po_4500')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const Key('poLeft_4500_O2'))).data,
      '10 left',
    );
    await press(t, LogicalKeyboardKey.escape);
    expect(find.text('1 purchase order (O)'), findsOneWidget);
    await press(t, LogicalKeyboardKey.escape);
    await press(t, LogicalKeyboardKey.escape);

    // ---- N = entry: after Bill comes the PO box (PO 4500 chosen).
    await press(t, LogicalKeyboardKey.keyN);
    await type(t, 'Sharma');
    await enter(t);
    await type(t, '101');
    await enter(t);
    await press(t, LogicalKeyboardKey.keyY);
    await press(t, LogicalKeyboardKey.enter);
    expect(focusedKey(), 'poPick');
    expect(t.widget<EditableText>(_focusedBox()).controller.text, 'PO 4500');
    await press(t, LogicalKeyboardKey.enter); // keeps it
    expect(focusedKey(), 'gasPick0');
    await type(t, 'o2');
    await enter(t);
    await type(t, '9');
    await enter(t);
    await enter(t); // no empty
    await enter(t); // no remark
    expect(find.text('Oxygen → PO 4500  (1 left after this)'), findsOneWidget);
    await enter(t); // End of List
    await enter(t); // no cash: save?
    expect(find.text('Save this entry?'), findsOneWidget);
    expect(find.text('Purchase order'), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    final saved = [
      for (final r in db.rows.values)
        if (r.rec.kind == Kind.entry) r.rec.data,
    ].single;
    expect((saved['po'] as Map).length, 1);
    expect(saved['poNo'], {'O2': '4500'});
    // Back from the fresh entry (an open company list closes first).
    for (
      var i = 0;
      i < 3 && find.text('Save Entry').evaluate().isNotEmpty;
      i++
    ) {
      await press(t, LogicalKeyboardKey.escape);
    }
    expect(find.text('Save Entry'), findsNothing);

    // ---- D = dashboard: PO 4500 almost done (1 left).
    await press(t, LogicalKeyboardKey.keyD);
    expect(
      find.textContaining('PURCHASE ORDERS - ALMOST DONE'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dashPo_4500_O2')), findsOneWidget);
    expect(find.text('1 left'), findsOneWidget);

    // ---- S = supply list shows the PO.
    await press(t, LogicalKeyboardKey.keyS);
    expect(find.text('PO 4500'), findsOneWidget);
  });

  testWidgets(
    'PC: changing an old entry keeps the PO it was supplied against',
    (t) async {
      t.view.physicalSize = const Size(1366, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final date = dayKey(today());
      final db = MemoryLocalDb();
      db.rows['company/c1'] = const LocalRow(
        Rec(Kind.company, 'c1', {'name': 'Sharma Steel'}),
      );
      // PO 4500 (p1) was removed; PO 4600 (p2) is the new one.
      db.rows['setting/po_p2'] = const LocalRow(
        Rec(Kind.setting, 'po_p2', {
          'company': 'c1',
          'number': '4600',
          'items': {'O2': 50},
          'made': 2,
        }),
      );
      db.rows['day/'] = LocalRow(
        Rec(Kind.day, date, {
          'openFull': {'O2': 30},
        }),
      );
      db.rows['entry/e1'] = LocalRow(
        Rec(Kind.entry, 'e1', {
          'date': date,
          'sort': 1,
          'companyId': 'c1',
          'company': 'Sharma Steel',
          'challan': '101',
          'full': {'O2': 5},
          'empty': {},
          'po': {'O2': 'p1'},
          'poNo': {'O2': '4500'},
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
      await press(t, LogicalKeyboardKey.keyS);
      expect(find.text('PO 4500'), findsOneWidget); // the removed PO's number
      await press(t, LogicalKeyboardKey.enter); // open it
      expect(focusedKey(), 'company');
      expect(find.text('Oxygen → PO 4500'), findsOneWidget);
      await enter(t);
      await type(t, '202');
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyA);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      final e = db.rows['entry/e1']!.rec.data;
      expect(e['challan'], '202');
      expect(e['po'], {'O2': 'p1'}); // not moved to PO 4600
      expect(e['poNo'], {'O2': '4500'});
    },
  );

  test('PDFs with extra full and POs', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final store = await newStore();
    final c = await store.addCompany('Sharma Steel');
    final a = await store.addPo(c.id, '4500', {'O2': 10});
    await store.saveDay(
      DayData(
        '2026-10-01',
        openFull: {'O2': 20},
        openEmpty: {'O2': 6},
        extraFull: {'O2': 2},
        entries: [
          Entry(
            id: 'e1',
            companyId: c.id,
            company: c.name,
            challan: '101',
            full: {'O2': 10},
            po: {'O2': a.id},
            poNo: {'O2': '4500'},
          ),
        ],
      ),
    );
    final out = Directory('build/test_output')..createSync(recursive: true);
    for (final (name, bytes) in [
      ('day_po.pdf', await buildDayPdf(store, ['2026-10-01'])),
      (
        'register_po.pdf',
        await buildRegisterPdf(store, '2026-10-01', '2026-10-31'),
      ),
      ('company_po.pdf', await buildCompanyStatementPdf(store, c.id)),
    ]) {
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      File('${out.path}/$name').writeAsBytesSync(bytes);
    }
  });
}
