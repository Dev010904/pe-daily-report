import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'legacy.dart';
import 'local_db.dart';
import 'records.dart';

/// Phone storage (SQLite in the app's private folder).
Future<LocalDb> openDeviceDb() async => SqliteLocalDb._(
  await openDatabase(
    p.join(await getDatabasesPath(), 'pe_daily_report_v2.db'),
    version: 1,
    onCreate: (db, v) async {
      await db.execute(
        'CREATE TABLE rows (key TEXT PRIMARY KEY, kind TEXT, '
        'id TEXT, data TEXT, deleted INTEGER, rev INTEGER, dirty INTEGER, '
        'version INTEGER)',
      );
      await db.execute(
        'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
  ),
);

class SqliteLocalDb implements LocalDb {
  final Database _db;
  SqliteLocalDb._(this._db);

  @override
  Future<({Map<String, LocalRow> rows, Map<String, String> meta})>
  load() async {
    final rows = <String, LocalRow>{};
    for (final r in await _db.query('rows')) {
      final rec = Rec(
        r['kind'] as String,
        r['id'] as String,
        decodeData(r['data'] as String),
        deleted: (r['deleted'] as int) == 1,
        rev: r['rev'] as int,
      );
      rows[rec.key] = LocalRow(
        rec,
        dirty: (r['dirty'] as int) == 1,
        version: r['version'] as int,
      );
    }
    final meta = {
      for (final r in await _db.query('meta'))
        r['key'] as String: r['value'] as String,
    };
    return (rows: rows, meta: meta);
  }

  @override
  Future<void> write(Iterable<LocalRow> list) async {
    final batch = _db.batch();
    for (final r in list) {
      batch.insert('rows', {
        'key': r.rec.key,
        'kind': r.rec.kind,
        'id': r.rec.id,
        'data': encodeData(r.rec.data),
        'deleted': r.rec.deleted ? 1 : 0,
        'rev': r.rec.rev,
        'dirty': r.dirty ? 1 : 0,
        'version': r.version,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await _db.delete('meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('meta', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<void> wipe() async {
    await _db.delete('rows');
    await _db.delete('meta');
  }
}

/// Reads the data saved by version 1 of the app (before cloud), once.
/// Returns null when there is none.
Future<List<Rec>?> readOldVersionData() async {
  final path = p.join(await getDatabasesPath(), 'daily_report.db');
  if (!await File(path).exists()) return null;
  final db = await openDatabase(path, readOnly: true, singleInstance: false);
  try {
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    if (!tables.contains('days') || !tables.contains('meta')) return null;
    final days = {
      for (final r in await db.query('days'))
        r['date'] as String: r['data'] as String,
    };
    final meta = {
      for (final r in await db.query('meta'))
        r['key'] as String: r['value'] as String,
    };
    return convertV1(days: days, meta: meta);
  } finally {
    await db.close();
  }
}

/// Keeps the old file (renamed) so it is never imported twice.
Future<void> retireOldVersionData() async {
  final path = p.join(await getDatabasesPath(), 'daily_report.db');
  final f = File(path);
  if (await f.exists()) {
    await f.rename(
      p.join(await getDatabasesPath(), 'daily_report_v1_imported.db'),
    );
  }
}
