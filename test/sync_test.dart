import 'package:daily_report/data/legacy.dart';
import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/records.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/repo.dart';
import 'package:daily_report/data/session.dart';
import 'package:daily_report/data/auth.dart';
import 'package:daily_report/models/day_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('two devices share one cloud', () {
    test('phone entry shows on PC, PC edit shows on phone', () async {
      final cloud = FakeRemote();
      final phone = await newStore(cloud: cloud);
      final pc = await newStore(cloud: cloud);

      final c = await phone.addCompany('Patel Steel');
      final d = DayData('2026-10-13', openFull: {'O2': 10});
      d.entries.add(entry('Patel Steel', companyId: c.id, full: {'O2': 2}));
      await phone.saveDay(d);
      expect(phone.repo.pending, greaterThan(0));
      await phone.repo.sync();
      expect(phone.repo.pending, 0);

      await pc.repo.sync();
      expect(pc.activeCompanies.single.name, 'Patel Steel');
      expect(pc.day('2026-10-13').entries.single.full, {'O2': 2});
      expect(pc.stock('2026-10-13').row('O2').closeFull, 8);

      // PC ticks the bill; phone sees it after syncing.
      final onPc = pc.day('2026-10-13');
      onPc.entries.single.billed = true;
      await pc.saveDay(onPc);
      await pc.repo.sync();
      await phone.repo.sync();
      expect(phone.day('2026-10-13').entries.single.billed, isTrue);

      // Deleting on the phone removes it on the PC too.
      final del = phone.day('2026-10-13')..entries.clear();
      await phone.saveDay(del);
      await phone.repo.sync();
      await pc.repo.sync();
      expect(pc.day('2026-10-13').entries, isEmpty);
      expect(pc.stock('2026-10-13').row('O2').closeFull, 10);
    });

    test('works offline and uploads when internet comes back', () async {
      final cloud = FakeRemote()..online = false;
      final phone = await newStore(cloud: cloud);
      final d = DayData('2026-10-13', filling: {'O2': 3}, openEmpty: {'O2': 5});
      await phone.saveDay(d);
      await phone.repo.sync();
      expect(phone.repo.state, SyncState.offline);
      expect(phone.repo.pending, 1);
      expect(phone.stock('2026-10-13').row('O2').closeFull, 3); // still usable

      cloud.online = true;
      await phone.repo.sync();
      expect(phone.repo.state, SyncState.idle);
      expect(phone.repo.pending, 0);
      expect(cloud.rows.length, 1);
    });

    test('changes saved on the phone survive closing the app', () async {
      final db = MemoryLocalDb();
      final first = await newStore(db: db);
      await first.addCompany('Shree Ganesh');
      final again = await newStore(db: db);
      expect(again.activeCompanies.single.name, 'Shree Ganesh');
      expect(again.repo.pending, 1); // still waiting to upload
    });

    test(
      'same record edited on two devices ends up the same everywhere',
      () async {
        final cloud = FakeRemote();
        final a = await newStore(cloud: cloud);
        final b = await newStore(cloud: cloud);
        final c = await a.addCompany('Old');
        await a.repo.sync();
        await b.repo.sync();

        await a.renameCompany(a.company(c.id)!, 'Name from A');
        await b.renameCompany(b.company(c.id)!, 'Name from B');
        await a.repo.sync();
        await b.repo.sync(); // B uploads last, so B wins
        await a.repo.sync();
        expect(a.company(c.id)!.name, 'Name from B');
        expect(b.company(c.id)!.name, 'Name from B');
      },
    );

    test('downloads more than one page of changes', () async {
      final cloud = FakeRemote();
      final a = await newStore(cloud: cloud);
      await a.repo.put([
        for (var i = 0; i < 2500; i++)
          Rec(Kind.entry, 'x$i', {
            'date': '2026-09-01',
            'sort': i,
            'company': 'C$i',
            'full': {'O2': 1},
          }),
      ]);
      await a.repo.sync();
      final b = await newStore(cloud: cloud);
      await b.repo.sync();
      expect(b.day('2026-09-01').entries.length, 2500);
    });

    test('an edit made while uploading is not lost', () async {
      final cloud = _SlowRemote();
      final a = await newStore(cloud: cloud);
      final c = await a.addCompany('First');
      final syncing = a.repo.sync();
      await a.renameCompany(a.company(c.id)!, 'Second'); // during upload
      await syncing;
      expect(a.repo.pending, 1);
      await a.repo.sync();
      expect(a.repo.pending, 0);
      expect(cloud.rows[recKey(Kind.company, c.id)]!.data['name'], 'Second');
    });
  });

  group('update from version 1 (phone only)', () {
    final v1Days = {
      '2026-10-10':
          '{"entries":[{"id":"111","companyId":1,"company":"Patel Steel",'
          '"challan":"55","billed":true,"full":{"O2":2},"empty":{"O2":1},'
          '"cash":[{"type":"Deposit","amount":500,"mode":"gpay"}]}],'
          '"openFull":{"O2":10},"openEmpty":{"O2":4},"filling":{"CO2":3},'
          '"plant":{"CO2":{"1":2}}}',
      '2026-10-11':
          '{"entries":[{"id":"222","companyId":2,"company":"Om Sai",'
          '"challan":"","full":{"O2":1},"empty":{}}]}',
    };
    final v1Meta = {
      'companies': '[{"id":1,"name":"Patel Steel","active":true},{"id":2,"name":"Om Sai","active":true}]',
      'plants': '[{"id":1,"name":"Ambika","active":true}]',
      'cashTypes': '["Deposit","Payment","Advance"]',
    };

    test('old phone data is converted with all details', () {
      final recs = convertV1(days: v1Days, meta: v1Meta);
      final byKey = {for (final r in recs) r.key: r};
      expect(byKey['company/v1c-1']!.data['name'], 'Patel Steel');
      expect(byKey['plant/v1p-1']!.data['name'], 'Ambika');
      final e = byKey['entry/v1e-111']!.data;
      expect(e['date'], '2026-10-10');
      expect(e['companyId'], 'v1c-1');
      expect(e['billed'], true);
      expect(byKey['day/2026-10-10']!.data['plant'], {
        'CO2': {'v1p-1': 2},
      });
      expect(byKey['setting/cashTypes']!.data['values'], [
        'Deposit',
        'Payment',
        'Advance',
      ]);
      expect(
        byKey.containsKey('day/2026-10-11'),
        isFalse,
      ); // only entries that day
    });

    test(
      'first login after the update moves the data once and uploads it',
      () async {
        final cloud = FakeRemote();
        final db = MemoryLocalDb();
        var retired = 0;
        var old = convertV1(days: v1Days, meta: v1Meta);
        AppEnv env() => AppEnv(
          auth: FakeAuthService(signedInAs: 'papa'),
          openDb: () async => db,
          newRemote: () => cloud,
          readOld: () async => retired == 0 ? old : null,
          retireOld: () async => retired++,
          autoSync: false,
        );
        final s = await Session.start(env());
        expect(retired, 1);
        final st = s.store;
        expect(st.activeCompanies.map((c) => c.name), [
          'Om Sai',
          'Patel Steel',
        ]);
        expect(st.stock('2026-10-10').row('O2').closeFull, 8);
        expect(st.stock('2026-10-10').row('CO2').plantLines.single.close, 2);
        expect(st.plantName('v1p-1'), 'Ambika');
        expect(st.day('2026-10-10').entries.single.cash.single.mode, kModeGpay);
        await s.repo.sync();
        expect(cloud.rows.length, old.length);

        // Opening again does not import twice.
        old = [];
        final again = await Session.start(env());
        expect(again.store.savedDates, ['2026-10-10', '2026-10-11']);
        expect(again.repo.pending, 0);
      },
    );

    test('log out removes the data from the device', () async {
      final db = MemoryLocalDb();
      final s = await Session.start(
        AppEnv(
          auth: FakeAuthService(signedInAs: 'papa'),
          openDb: () async => db,
          autoSync: false,
        ),
      );
      await s.store.addCompany('X');
      await s.end();
      expect(db.rows, isEmpty);
    });
  });
}

/// Cloud whose uploads take a moment, to test edits made meanwhile.
class _SlowRemote extends FakeRemote {
  @override
  Future<List<Rec>> push(List<Rec> recs) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.push(recs);
  }
}
