import 'package:web/web.dart' as web;

/// The website must ask for the login every time it is opened, so nothing
/// about the login may stay in the browser. Removes anything an older
/// version saved (session tokens, username).
void wipeBrowserStorage() {
  web.window.localStorage.clear();
  web.window.sessionStorage.clear();
}
