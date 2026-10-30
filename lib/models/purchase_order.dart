import 'day_data.dart';

/// A company's purchase order (PO): its number and how many cylinders of
/// each gas were ordered. A company can have several (e.g. one for Oxygen,
/// another for CO2), or none. Stored as a settings record "po_" + id, so
/// the cloud needs no change and older app versions leave it alone.
class PurchaseOrder {
  final String id;
  final String companyId;
  String number;

  /// Ordered cylinders: gas code -> qty.
  Map<String, int> items;

  /// When it was added: the company's POs are used oldest first.
  final int made;

  /// Parts written by a newer version of the app, kept as they are.
  final Map<String, dynamic> _extra;

  PurchaseOrder({
    required this.id,
    required this.companyId,
    required this.number,
    required this.items,
    required this.made,
    Map<String, dynamic>? extra,
  }) : _extra = extra ?? {};

  bool hasGas(String gas) => (items[gas] ?? 0) > 0;

  static const _known = {'company', 'number', 'items', 'made'};

  Map<String, dynamic> toJson() => {
    ..._extra,
    'company': companyId,
    'number': number,
    'items': items,
    'made': made,
  };

  factory PurchaseOrder.fromJson(String id, Map<String, dynamic> j) =>
      PurchaseOrder(
        id: id,
        companyId: j['company']?.toString() ?? '',
        number: j['number']?.toString() ?? '',
        items: intMap(j['items']),
        made: (j['made'] as num?)?.toInt() ?? 0,
        extra: {
          for (final e in j.entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      );

  PurchaseOrder copy() => PurchaseOrder.fromJson(id, toJson());
}

/// One gas of a PO and how much of it has been supplied.
class PoLine {
  final PurchaseOrder po;
  final String gas;
  final int supplied;
  const PoLine(this.po, this.gas, this.supplied);

  int get ordered => po.items[gas] ?? 0;
  int get left => ordered - supplied;

  /// Everything ordered has been supplied (or more).
  bool get done => left <= 0;

  /// Almost finished: 10% or less left (at least 1), time for a new PO.
  bool get nearlyDone => !done && left <= poNearLimit(ordered);
}

/// How few cylinders left counts as "almost finished".
int poNearLimit(int ordered) {
  final tenth = (ordered + 9) ~/ 10;
  return tenth < 1 ? 1 : tenth;
}

/// Marks "No PO" in a PO choice.
const String kNoPo = '';
