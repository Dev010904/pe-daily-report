import '../util/dates.dart';

/// A paper is shown on the Dashboard from this many days before it expires
/// (and stays there, in red, once expired, until it is renewed).
const int kPaperAlertDays = 10;

/// Papers offered in the list (any other name can be typed).
const List<String> kPaperTypes = [
  'PUC',
  'Insurance',
  'Fitness (FC)',
  'Permit',
  'Road Tax',
  'RC Book',
];

/// Whole days from [from] to [to] (negative when [to] is earlier).
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// A paper of a vehicle that has to be renewed: PUC, insurance, fitness...
/// Renewing it simply replaces the dates (the old ones are not kept), so the
/// countdown starts again from the new last day.
class VehiclePaper {
  final String id;
  String type;

  /// Valid from / till (yyyy-MM-dd). Till is the last valid day; from may be
  /// unknown.
  String? from;
  String till;

  VehiclePaper({
    required this.id,
    required this.type,
    this.from,
    required this.till,
  });

  /// Days until the last valid day (0 = expires today, below 0 = expired).
  int daysLeft([DateTime? now]) =>
      daysBetween(now ?? today(), parseDayKey(till));

  /// Shown on the Dashboard: expires within [kPaperAlertDays], or expired.
  bool isDue([DateTime? now]) => daysLeft(now) <= kPaperAlertDays;

  /// "Expires in 4 days", "Expires TODAY", "EXPIRED 2 days ago", "Valid".
  String statusText([DateTime? now]) {
    final d = daysLeft(now);
    if (d < 0) return 'EXPIRED ${-d} ${-d == 1 ? 'day' : 'days'} ago';
    if (d == 0) return 'Expires TODAY';
    if (d <= kPaperAlertDays) return 'Expires in $d ${d == 1 ? 'day' : 'days'}';
    return 'Valid · $d days left';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'from': ?from,
    'till': till,
  };

  static VehiclePaper? fromJson(Object? raw) {
    if (raw is! Map || raw['till'] is! String) return null;
    return VehiclePaper(
      id: raw['id']?.toString() ?? '${raw['type']}',
      type: raw['type'] as String? ?? 'Paper',
      from: raw['from'] is String ? raw['from'] as String : null,
      till: raw['till'] as String,
    );
  }
}

/// A delivery vehicle and its papers.
class Vehicle {
  final String id;

  /// Registration number as written, e.g. "GJ 01 AB 1234".
  String number;
  List<VehiclePaper> papers;

  /// Parts written by a newer version of the app, kept as they are.
  final Map<String, dynamic> _extra;

  Vehicle({
    required this.id,
    required this.number,
    List<VehiclePaper>? papers,
    Map<String, dynamic>? extra,
  }) : papers = papers ?? [],
       _extra = extra ?? {};

  /// Number without spaces or dashes, upper case (to find duplicates).
  static String norm(String number) =>
      number.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Papers in the order they run out (soonest first).
  List<VehiclePaper> get byExpiry =>
      [...papers]..sort((a, b) => a.till.compareTo(b.till));

  Map<String, dynamic> toJson() => {
    ..._extra,
    'number': number,
    'papers': [for (final p in papers) p.toJson()],
  };

  factory Vehicle.fromJson(String id, Map<String, dynamic> j) => Vehicle(
    id: id,
    number: j['number'] as String? ?? '',
    papers: [
      for (final p in (j['papers'] as List? ?? const []))
        ?VehiclePaper.fromJson(p),
    ],
    extra: {
      for (final e in j.entries)
        if (e.key != 'number' && e.key != 'papers') e.key: e.value,
    },
  );

  Vehicle copy() => Vehicle.fromJson(id, toJson());
}

/// A paper to renew soon (or already expired), for the Dashboard.
class PaperAlert {
  final Vehicle vehicle;
  final VehiclePaper paper;
  final int daysLeft;
  const PaperAlert(this.vehicle, this.paper, this.daysLeft);
}
