import 'package:daily_report/data/store.dart';
import 'package:daily_report/models/vehicle.dart';
import 'package:daily_report/util/dates.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final now = DateTime(2026, 10, 24);
  String inDays(int n) => dayKey(now.add(Duration(days: n)));

  test(
    'a paper is due from 10 days before its last day, and urgent once over',
    () {
      VehiclePaper p(int days) =>
          VehiclePaper(id: 'p', type: 'PUC', till: inDays(days));
      expect(p(11).isDue(now), isFalse);
      expect(p(10).isDue(now), isTrue); // the first reminder day
      expect(p(10).statusText(now), 'Expires in 10 days');
      expect(p(1).statusText(now), 'Expires in 1 day');
      expect(p(0).statusText(now), 'Expires TODAY');
      expect(p(-2).isDue(now), isTrue); // stays until renewed
      expect(p(-2).statusText(now), 'EXPIRED 2 days ago');
      expect(p(40).statusText(now), 'Valid · 40 days left');
    },
  );

  test(
    'vehicles and papers are saved, alerts come most urgent first',
    () async {
      final AppStore store = await newStore();
      final v = await store.addVehicle('gj 01 ab 1234');
      expect(v.number, 'GJ 01 AB 1234');
      expect(store.vehicleWithNumber('GJ01-AB-1234')?.id, v.id);

      final saved = store.vehicle(v.id)!
        ..papers.addAll([
          VehiclePaper(
            id: 'a',
            type: 'PUC',
            from: inDays(-180),
            till: inDays(6),
          ),
          VehiclePaper(id: 'b', type: 'Insurance', till: inDays(-3)),
          VehiclePaper(id: 'c', type: 'Fitness (FC)', till: inDays(200)),
        ]);
      await store.saveVehicle(saved);
      final t2 = await store.addVehicle('GJ 01 CD 5678');
      await store.saveVehicle(
        store.vehicle(t2.id)!
          ..papers.add(VehiclePaper(id: 'd', type: 'PUC', till: inDays(10))),
      );

      final alerts = store.paperAlerts(now: now);
      expect(
        alerts.map((a) => '${a.vehicle.number} ${a.paper.type} ${a.daysLeft}'),
        [
          'GJ 01 AB 1234 Insurance -3',
          'GJ 01 AB 1234 PUC 6',
          'GJ 01 CD 5678 PUC 10',
        ],
      );
      expect(store.paperTypes, contains('Fitness (FC)'));

      // Renewed: the new dates replace the old ones; nothing old is kept, and
      // the countdown starts again (no alert for a year).
      final renew = store.vehicle(v.id)!;
      final i = renew.papers.indexWhere((p) => p.id == 'b');
      renew.papers[i] = VehiclePaper(
        id: 'b',
        type: 'Insurance',
        from: inDays(0),
        till: inDays(364),
      );
      await store.saveVehicle(renew);
      final again = store.vehicle(v.id)!.papers.firstWhere((p) => p.id == 'b');
      expect(again.till, inDays(364));
      expect(again.toJson().keys, ['id', 'type', 'from', 'till']);
      expect(store.paperAlerts(now: now).length, 2);

      // Removing a vehicle removes its reminders.
      await store.removeVehicle(store.vehicle(t2.id)!);
      expect(store.vehicles.map((x) => x.number), ['GJ 01 AB 1234']);
      expect(store.paperAlerts(now: now).map((a) => a.paper.id), ['a']);
    },
  );

  test('stored form keeps parts from a newer app', () {
    final v = Vehicle.fromJson('v1', {
      'number': 'GJ 05 X 1',
      'papers': [
        {'id': 'p', 'type': 'PUC', 'till': '2027-01-01'},
        {'broken': true},
      ],
      'driver': 'Ramesh',
    });
    expect(v.papers.single.type, 'PUC');
    expect(v.toJson()['driver'], 'Ramesh');
  });
}
