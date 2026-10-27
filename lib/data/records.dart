/// Kinds of item stored for the Daily Report. Each item is one record that
/// syncs on its own, so two devices editing different things never clash.
abstract final class Kind {
  static const company = 'company';
  static const plant = 'plant';
  static const entry = 'entry';
  static const day = 'day';
  static const setting = 'setting';
}

class Rec {
  final String kind;
  final String id;
  final Map<String, dynamic> data;
  final bool deleted;

  /// Server change number (microseconds). 0 = never reached the server.
  final int rev;

  const Rec(
    this.kind,
    this.id,
    this.data, {
    this.deleted = false,
    this.rev = 0,
  });

  String get key => recKey(kind, id);

  Rec withRev(int rev) => Rec(kind, id, data, deleted: deleted, rev: rev);

  /// Row sent to / read from the cloud table.
  Map<String, dynamic> toRow() => {
    'kind': kind,
    'id': id,
    'data': data,
    'deleted': deleted,
  };

  factory Rec.fromRow(Map<String, dynamic> r) => Rec(
    r['kind'] as String,
    r['id'] as String,
    Map<String, dynamic>.from(r['data'] as Map? ?? const {}),
    deleted: r['deleted'] as bool? ?? false,
    rev: (r['rev'] as num?)?.toInt() ?? 0,
  );
}

String recKey(String kind, String id) => '$kind/$id';

/// A record as kept on this device, plus whether it still has to be uploaded.
class LocalRow {
  final Rec rec;

  /// True while the change has not reached the cloud.
  final bool dirty;

  /// Bumped on every local edit so an upload that finished late does not
  /// mark a newer edit as uploaded.
  final int version;

  const LocalRow(this.rec, {this.dirty = false, this.version = 0});
}
