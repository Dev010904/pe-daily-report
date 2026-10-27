import 'dart:convert';

import 'records.dart';

/// Storage on this device: a copy of every record plus a few settings.
/// The phone keeps working without internet using this copy.
abstract class LocalDb {
  Future<({Map<String, LocalRow> rows, Map<String, String> meta})> load();
  Future<void> write(Iterable<LocalRow> rows);
  Future<void> setMeta(String key, String? value);

  /// Removes everything (used on log out).
  Future<void> wipe();
}

/// Kept in memory only: used on the PC website (always online) and in tests.
class MemoryLocalDb implements LocalDb {
  final Map<String, LocalRow> rows = {};
  final Map<String, String> meta = {};

  @override
  Future<({Map<String, LocalRow> rows, Map<String, String> meta})>
  load() async => (rows: Map.of(rows), meta: Map.of(meta));

  @override
  Future<void> write(Iterable<LocalRow> list) async {
    for (final r in list) {
      rows[r.rec.key] = r;
    }
  }

  @override
  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      meta.remove(key);
    } else {
      meta[key] = value;
    }
  }

  @override
  Future<void> wipe() async {
    rows.clear();
    meta.clear();
  }
}

String encodeData(Map<String, dynamic> data) => jsonEncode(data);

Map<String, dynamic> decodeData(String s) =>
    Map<String, dynamic>.from(jsonDecode(s) as Map);
