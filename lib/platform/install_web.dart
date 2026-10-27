import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The browser's own "install this app" offer, kept by web/install.js.
JSObject? _offer() {
  final keeper = (web.window as JSObject).getProperty<JSObject?>(
    'peInstall'.toJS,
  );
  return keeper?.getProperty<JSObject?>('offer'.toJS);
}

/// True when the browser (Chrome, Brave, Edge) can install the website as
/// an app right now.
bool canOfferInstall() => _offer() != null;

/// Shows the browser's install box. True when the user said yes.
Future<bool> offerInstall() async {
  final offer = _offer();
  if (offer == null) return false;
  offer.callMethod<JSAny?>('prompt'.toJS);
  final choice = await offer
      .getProperty<JSPromise<JSObject>>('userChoice'.toJS)
      .toDart;
  return choice.getProperty<JSString>('outcome'.toJS).toDart == 'accepted';
}

/// True when this page was opened from the installed app icon.
bool runningAsInstalledApp() =>
    web.window.matchMedia('(display-mode: standalone)').matches;

/// Downloads the Android app from this website. The website only hands it
/// out to a logged-in user, so the login token is sent along (in the
/// request body, never in the address). Returns 'downloaded', 'login' when
/// the login has run out, or 'error'.
Future<String> downloadAndroidAppImpl(String? token, String fileName) async {
  if (token == null) return 'login';
  try {
    final headers = web.Headers()..append('Content-Type', 'application/json');
    final res = await web.window
        .fetch(
          'download/android'.toJS,
          web.RequestInit(
            method: 'POST',
            headers: headers,
            body: jsonEncode({'token': token}).toJS,
            cache: 'no-store',
            credentials: 'omit',
          ),
        )
        .toDart;
    if (res.status == 401) return 'login';
    if (!res.ok) return 'error';
    final blob = await res.blob().toDart;
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    a.style.display = 'none';
    web.document.body!.append(a);
    a.click();
    a.remove();
    Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
    return 'downloaded';
  } catch (_) {
    return 'error';
  }
}
