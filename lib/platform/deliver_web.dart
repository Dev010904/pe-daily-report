import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// PC browser: download the file to the Downloads folder.
Future<String> deliverFileImpl(
  List<int> bytes,
  String name,
  String mime,
  String text,
) async {
  final blob = web.Blob(
    <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  a.style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return 'downloaded';
}
