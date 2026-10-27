import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Phone: save to the app's temp folder and open the share sheet
/// (WhatsApp, Gmail, Drive...).
Future<String> deliverFileImpl(
  List<int> bytes,
  String name,
  String mime,
  String text,
) async {
  final dir = Directory(
    p.join((await getTemporaryDirectory()).path, 'exports'),
  );
  if (await dir.exists()) {
    // Clear old exports so the phone does not fill up.
    for (final f in dir.listSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  } else {
    await dir.create(recursive: true);
  }
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mime)],
      text: text,
      subject: text,
    ),
  );
  return 'shared';
}
