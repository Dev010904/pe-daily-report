import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config.dart';

const _channel = MethodChannel('pe/update');

/// The phone app updates itself (Android only).
bool get selfUpdates => Platform.isAndroid;

/// Website only: reload into the new version.
bool reloadIntoNewVersion(int build) => false;

Future<File> _apkFile() async =>
    File(p.join((await getTemporaryDirectory()).path, 'pe_update.apk'));

/// Removes a downloaded update that is no longer needed.
Future<void> cleanOldUpdate() async {
  try {
    final f = await _apkFile();
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Downloads the new app from the website (only handed out to a logged-in
/// user, so the login token goes in the request body). Returns the file
/// path, or throws.
Future<String> downloadUpdate(
  String token,
  void Function(double) progress,
) async {
  final client = http.Client();
  try {
    final req = http.Request('POST', Uri.parse('$kUpdateUrl/download/android'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'token': token});
    final res = await client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) throw const HttpException('login');
    if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
    final total = res.contentLength ?? 0;
    final file = await _apkFile();
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress(got / total);
      }
    } finally {
      await sink.close();
    }
    // A real APK is a zip file of several MB.
    final head = await file.openRead(0, 2).first;
    if (got < 1000000 ||
        head.length < 2 ||
        head[0] != 0x50 ||
        head[1] != 0x4B) {
      throw const HttpException('bad file');
    }
    return file.path;
  } finally {
    client.close();
  }
}

/// True when Android lets this app install its own updates.
Future<bool> canInstallUpdates() async =>
    await _channel.invokeMethod<bool>('canInstall') ?? false;

/// Opens the Android screen "Install unknown apps → Daily Report".
Future<void> openInstallPermission() => _channel.invokeMethod('openSettings');

/// Hands the downloaded file to Android's installer. Android checks that it
/// is signed with the same key as the installed app.
Future<void> installUpdate(String path) =>
    _channel.invokeMethod('install', {'path': path});
