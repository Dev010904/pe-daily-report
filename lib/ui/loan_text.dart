import '../data/store.dart';
import '../models/day_data.dart';
import '../models/gas.dart';

/// Loan cylinders (borrowed from a filling plant) in lists and boxes.
///
/// In a gas list a loan line is a choice like "ARGON · ABC Plant", stored
/// as the code "AR_COMM|plantId".
String loanCode(String gas, String plantId) => '$gas|$plantId';

(String gas, String plantId) loanSplit(String code) {
  final i = code.indexOf('|');
  return (code.substring(0, i), code.substring(i + 1));
}

Gas loanChoice(AppStore store, String gas, String plantId) => Gas(
  loanCode(gas, plantId),
  '${gasLabel(gas)} · ${store.plantName(plantId)}',
  group: gasByCode(gas)?.group,
);

/// gas -> plant -> qty as "code -> qty" for loan choices.
Map<String, int> loanCodes(PlantQty m) => {
  for (final g in m.entries)
    for (final p in g.value.entries)
      if (p.value != 0) loanCode(g.key, p.key): p.value,
};

/// "code -> qty" back to gas -> plant -> qty.
PlantQty loanFromCodes(Map<String, int> m) {
  final out = <String, Map<String, int>>{};
  m.forEach((code, v) {
    if (v == 0) return;
    final (gas, plant) = loanSplit(code);
    addPlantQty(out, gas, plant, v);
  });
  return out;
}

/// "ARGON 10 (ABC Plant)" for each gas / plant, in the usual gas order.
List<String> loanTexts(AppStore store, PlantQty m) => [
  for (final g in kGases)
    for (final p in (m[g.code] ?? const <String, int>{}).entries)
      if (p.value != 0) '${g.label} ${p.value} (${store.plantName(p.key)})',
];

String loanText(
  AppStore store,
  PlantQty m, {
  String sep = ',  ',
  String none = '-',
}) {
  final t = loanTexts(store, m);
  return t.isEmpty ? none : t.join(sep);
}
