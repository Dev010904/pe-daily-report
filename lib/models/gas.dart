/// The gases Panchal Enterprise deals in, in the exact order they are shown
/// everywhere (stock table, entry form and PDFs).
class Gas {
  final String code;
  final String label;

  /// 'AR' or 'N2' for the gases that have sub-types.
  final String? group;

  const Gas(this.code, this.label, {this.group});

  /// DA cylinders are swapped at the plant, so filling and empties are
  /// entered by hand instead of being linked.
  bool get isDA => code == 'DA';

  /// Empties of every gas except DA can be left waiting at a filling plant.
  bool get canKeepAtPlant => !isDA;
}

const List<Gas> kGases = [
  Gas('O2', 'Oxygen'),
  Gas('CO2', 'CO2'),
  Gas('AR_COMM', 'ARGON', group: 'AR'),
  Gas('AR_MIX', 'AR Mix.', group: 'AR'),
  Gas('DA', 'DA'),
  Gas('N2_COMM', 'NITROGEN', group: 'N2'),
  Gas('N2_0AIR', 'N2 0 AIR', group: 'N2'),
  Gas('H2', 'H2'),
  Gas('LPG', 'LPG'),
  Gas('LC', 'LC'),
];

/// ARGON: the only gas with a note in the stock and filling (to keep count
/// of ARGON SPL, which is counted in ARGON).
const String kArgon = 'AR_COMM';

/// AR SPL is no longer a gas (counted as ARGON since 2026-10-29); kept only
/// to read old records (see logic/argon_spl.dart).
const Gas kRetiredArgonSpl = Gas('AR_SPL', 'AR SPL', group: 'AR');

final Map<String, Gas> _byCode = {
  for (final g in [...kGases, kRetiredArgonSpl]) g.code: g,
};

Gas? gasByCode(String code) => _byCode[code];

String gasLabel(String code) => _byCode[code]?.label ?? code;

/// Sorts a gas->qty map into the standard gas order, dropping zero quantities.
List<MapEntry<String, int>> orderedQty(Map<String, int> qty) => [
  for (final g in kGases)
    if ((qty[g.code] ?? 0) != 0) MapEntry(g.code, qty[g.code]!),
];
