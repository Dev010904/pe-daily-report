import 'dart:convert';

import 'records.dart';

/// Converts data from version 1 of the app (phone only, before cloud) into
/// cloud records. Old number ids become fixed text ids so converting the
/// same data twice gives the same records.
List<Rec> convertV1({
  required Map<String, String> days,
  required Map<String, String> meta,
}) {
  List<dynamic> list(String key) =>
      meta[key] == null ? const [] : jsonDecode(meta[key]!) as List;
  return _convert(
    companies: list('companies'),
    plants: list('plants'),
    cashTypes: meta['cashTypes'] == null ? null : list('cashTypes'),
    days: {
      for (final e in days.entries)
        e.key: Map<String, dynamic>.from(jsonDecode(e.value) as Map),
    },
  );
}

String v1CompanyId(Object old) => 'v1c-$old';
String v1PlantId(Object old) => 'v1p-$old';

List<Rec> _convert({
  required List<dynamic> companies,
  required List<dynamic> plants,
  required List<dynamic>? cashTypes,
  required Map<String, Map<String, dynamic>> days,
}) {
  final out = <Rec>[];
  for (final c in companies) {
    final m = c as Map;
    out.add(
      Rec(Kind.company, v1CompanyId(m['id']), {
        'name': m['name'],
        'active': m['active'] ?? true,
      }),
    );
  }
  for (final p in plants) {
    final m = p as Map;
    out.add(
      Rec(Kind.plant, v1PlantId(m['id']), {
        'name': m['name'],
        'active': m['active'] ?? true,
      }),
    );
  }
  if (cashTypes != null) {
    out.add(Rec(Kind.setting, 'cashTypes', {'values': cashTypes}));
  }
  for (final d in days.entries) {
    final date = d.key;
    final j = d.value;
    final entries = j['entries'] as List? ?? const [];
    for (var i = 0; i < entries.length; i++) {
      final e = Map<String, dynamic>.from(entries[i] as Map);
      final id = (e['id'] ?? '$date-$i').toString();
      out.add(
        Rec(Kind.entry, 'v1e-$id', {
          'date': date,
          'sort': i,
          'companyId': e['companyId'] == null
              ? null
              : v1CompanyId(e['companyId']),
          'company': e['company'] ?? '',
          'challan': e['challan'] ?? '',
          'billed': e['billed'] ?? false,
          'full': e['full'] ?? {},
          'empty': e['empty'] ?? {},
          if (e['cash'] != null) 'cash': e['cash'],
        }),
      );
    }
    final meta = <String, dynamic>{
      if (j['filling'] != null) 'filling': j['filling'],
      if (j['daEmptyGiven'] != null) 'daEmptyGiven': j['daEmptyGiven'],
      if (j['openFull'] != null) 'openFull': j['openFull'],
      if (j['openEmpty'] != null) 'openEmpty': j['openEmpty'],
      if (j['plant'] is Map)
        'plant': {
          for (final g in (j['plant'] as Map).entries)
            g.key: {
              for (final p in (g.value as Map).entries)
                v1PlantId(p.key): p.value,
            },
        },
    };
    if (meta.isNotEmpty) out.add(Rec(Kind.day, date, meta));
  }
  return out;
}
