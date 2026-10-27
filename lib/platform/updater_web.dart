import 'package:web/web.dart' as web;

/// The website never installs anything; it reloads into the new version.
bool get selfUpdates => false;

/// Reloads the page so the browser loads the new version. The "u" mark in
/// the address stops it from reloading again and again if the new files
/// are not there yet.
bool reloadIntoNewVersion(int build) {
  final loc = web.window.location;
  final url = Uri.parse(loc.href);
  if (url.queryParameters['u'] == '$build') return false;
  loc.replace(url.replace(queryParameters: {'u': '$build'}).toString());
  return true;
}

Future<void> cleanOldUpdate() async {}

Future<String> downloadUpdate(String token, void Function(double) progress) =>
    throw UnsupportedError('website');

Future<bool> canInstallUpdates() async => false;

Future<void> openInstallPermission() async {}

Future<void> installUpdate(String path) async {}
