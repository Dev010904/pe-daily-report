import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// The newest version on the website (from its version.json).
class RemoteVersion {
  final String version;
  final int build;
  const RemoteVersion(this.version, this.build);

  bool get isNewer => build > kBuildNumber;
}

/// Asks the website which version is newest. Null when offline or on any
/// problem, so the app simply carries on.
Future<RemoteVersion?> fetchLatestVersion({http.Client? client}) async {
  final base = kIsWeb
      ? Uri.base.resolve('/version.json')
      : Uri.parse('$kUpdateUrl/version.json');
  final url = base.replace(
    queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
  );
  final c = client ?? http.Client();
  try {
    final r = await c.get(url).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    if (j is! Map) return null;
    final build = int.tryParse('${j['build_number']}');
    final version = j['version'];
    if (build == null || version is! String) return null;
    return RemoteVersion(version, build);
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
