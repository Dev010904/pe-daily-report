import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'local_db.dart';
import 'records.dart';
import 'remote.dart';

enum SyncState { idle, syncing, offline, error }

/// Holds every record on this device and keeps it in step with the cloud.
/// Edits are saved on the device first (works without internet) and
/// uploaded in the background; changes from other devices are downloaded.
class Repo extends ChangeNotifier {
  final LocalDb _local;
  Remote? _remote;
  final bool autoSync;

  final Map<String, LocalRow> _rows = {};
  final Map<String, String> _meta = {};
  int _cursor = 0;

  SyncState state = SyncState.idle;
  String? lastError;
  DateTime? lastSynced;

  /// Goes up whenever the data itself changes (not just the sync status).
  int dataVersion = 0;

  Timer? _timer;
  Timer? _soon;
  StreamSubscription<void>? _sub;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// Changes from the last 10 seconds are always fetched again, so a change
  /// that was being saved while we downloaded is never missed.
  static const overlapMicros = 10 * 1000 * 1000;

  Repo(this._local, {this.autoSync = true});

  Future<void> open() async {
    final s = await _local.load();
    _rows
      ..clear()
      ..addAll(s.rows);
    _meta
      ..clear()
      ..addAll(s.meta);
    _cursor = int.tryParse(_meta['cursor'] ?? '') ?? 0;
    dataVersion++;
    _notify();
  }

  Iterable<Rec> get records => _rows.values.map((r) => r.rec);
  Rec? get(String kind, String id) => _rows[recKey(kind, id)]?.rec;
  bool get isEmpty => _rows.isEmpty;

  /// Changes saved on this device that have not reached the cloud yet.
  int get pending => _rows.values.where((r) => r.dirty).length;

  bool get online => _remote != null;

  String? meta(String key) => _meta[key];

  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      _meta.remove(key);
    } else {
      _meta[key] = value;
    }
    await _local.setMeta(key, value);
  }

  /// Saves edits on the device and uploads them soon.
  Future<void> put(List<Rec> recs) async {
    if (recs.isEmpty) return;
    final rows = <LocalRow>[];
    for (final r in recs) {
      final cur = _rows[r.key];
      final row = LocalRow(
        Rec(r.kind, r.id, r.data, deleted: r.deleted, rev: cur?.rec.rev ?? 0),
        dirty: true,
        version: (cur?.version ?? 0) + 1,
      );
      _rows[row.rec.key] = row;
      rows.add(row);
    }
    dataVersion++;
    _notify();
    await _local.write(rows);
    _syncSoon(const Duration(milliseconds: 300));
  }

  /// Starts talking to the cloud.
  void attach(Remote remote) {
    _remote = remote;
    _sub = remote.changes.listen(
      (_) => _syncSoon(const Duration(milliseconds: 400)),
    );
    if (autoSync) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
      sync();
    }
  }

  Future<void> detach() async {
    _timer?.cancel();
    _soon?.cancel();
    await _sub?.cancel();
    final r = _remote;
    _remote = null;
    await r?.close();
  }

  void _syncSoon(Duration d) {
    if (_remote == null || !autoSync) return;
    _soon?.cancel();
    _soon = Timer(d, sync);
  }

  Future<void> sync() async {
    final remote = _remote;
    if (remote == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = SyncState.syncing;
    _notify();
    try {
      do {
        _again = false;
        await _push(remote);
        await _pull(remote);
      } while (_again && _remote != null);
      state = SyncState.idle;
      lastError = null;
      lastSynced = DateTime.now();
    } on OfflineException {
      state = SyncState.offline;
    } catch (e) {
      state = SyncState.error;
      lastError = '$e';
    } finally {
      _running = false;
      _notify();
    }
  }

  Future<void> _push(Remote remote) async {
    final dirty = _rows.values.where((r) => r.dirty).toList();
    if (dirty.isEmpty) return;
    final sentVersion = {for (final d in dirty) d.rec.key: d.version};
    final saved = await remote.push([for (final d in dirty) d.rec]);
    final done = <LocalRow>[];
    for (final s in saved) {
      final cur = _rows[s.key];
      // Only mark as uploaded if it was not edited again meanwhile.
      if (cur != null && cur.version == sentVersion[s.key]) {
        final row = LocalRow(s, version: cur.version);
        _rows[s.key] = row;
        done.add(row);
      }
    }
    await _local.write(done);
  }

  Future<void> _pull(Remote remote) async {
    var since = max(0, _cursor - overlapMicros);
    var changed = false;
    while (true) {
      final page = await remote.pull(since);
      final updates = <LocalRow>[];
      for (final r in page) {
        if (r.rev > _cursor) _cursor = r.rev;
        final cur = _rows[r.key];
        if (cur != null && cur.dirty) continue; // our newer edit goes up next
        if (cur != null && cur.rec.rev == r.rev) continue;
        final row = LocalRow(r, version: cur?.version ?? 0);
        _rows[r.key] = row;
        updates.add(row);
        changed = true;
      }
      await _local.write(updates);
      if (page.length < 1000) break;
      final last = page.last.rev;
      since = last == since ? last + 1 : last;
    }
    await setMeta('cursor', '$_cursor');
    if (changed) dataVersion++;
  }

  /// Removes all data from this device (log out).
  Future<void> wipe() async {
    await detach();
    _rows.clear();
    _meta.clear();
    _cursor = 0;
    await _local.wipe();
    dataVersion++;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _soon?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
