import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'records.dart';

/// The cloud copy of the data.
abstract class Remote {
  /// Uploads records; returns them with the server's change numbers.
  Future<List<Rec>> push(List<Rec> recs);

  /// Records changed at or after [sinceRev], oldest first, at most [limit].
  Future<List<Rec>> pull(int sinceRev, {int limit = 1000});

  /// Fires when another device changed something.
  Stream<void> get changes;

  Future<void> close();
}

/// Thrown when the cloud cannot be reached (no internet etc.).
class OfflineException implements Exception {
  final Object cause;
  OfflineException(this.cause);
  @override
  String toString() => 'Offline: $cause';
}

const _table = 'dr_records';

class SupabaseRemote implements Remote {
  final SupabaseClient _db;
  final _changes = StreamController<void>.broadcast();
  RealtimeChannel? _channel;

  SupabaseRemote(this._db) {
    _channel = _db
        .channel('dr-records')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _table,
          callback: (_) => _changes.add(null),
        )
        .subscribe();
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<Rec>> push(List<Rec> recs) async {
    final out = <Rec>[];
    for (var i = 0; i < recs.length; i += 200) {
      final part = recs.sublist(
        i,
        i + 200 > recs.length ? recs.length : i + 200,
      );
      final rows = await _guard(
        () => _db
            .from(_table)
            .upsert([for (final r in part) r.toRow()], onConflict: 'kind,id')
            .select('kind,id,data,deleted,rev'),
      );
      out.addAll([for (final r in rows) Rec.fromRow(r)]);
    }
    return out;
  }

  @override
  Future<List<Rec>> pull(int sinceRev, {int limit = 1000}) async {
    final rows = await _guard(
      () => _db
          .from(_table)
          .select('kind,id,data,deleted,rev')
          .gte('rev', sinceRev)
          .order('rev')
          .order('kind')
          .order('id')
          .limit(limit),
    );
    return [for (final r in rows) Rec.fromRow(r)];
  }

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run().timeout(const Duration(seconds: 30));
    } on PostgrestException {
      rethrow;
    } catch (e) {
      throw OfflineException(e);
    }
  }

  @override
  Future<void> close() async {
    if (_channel != null) await _db.removeChannel(_channel!);
    await _changes.close();
  }
}

/// In-memory cloud for tests and the offline demo build.
class FakeRemote implements Remote {
  final Map<String, Rec> rows = {};
  final _changes = StreamController<void>.broadcast();
  int _clock = 1000000;
  bool online = true;
  int pushes = 0;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<Rec>> push(List<Rec> recs) async {
    if (!online) throw OfflineException('offline');
    pushes++;
    final out = <Rec>[];
    for (final r in recs) {
      final saved = r.withRev(++_clock);
      rows[r.key] = saved;
      out.add(saved);
    }
    _changes.add(null);
    return out;
  }

  @override
  Future<List<Rec>> pull(int sinceRev, {int limit = 1000}) async {
    if (!online) throw OfflineException('offline');
    final list = rows.values.where((r) => r.rev >= sinceRev).toList()
      ..sort((a, b) => a.rev.compareTo(b.rev));
    return list.take(limit).toList();
  }

  @override
  Future<void> close() async {}
}
