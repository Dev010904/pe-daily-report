import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Website: web/install.js keeps window.peCtrl up to date before the app
/// sees each key.
void watchCtrlKey() {}

/// True when the browser says Ctrl (or Cmd) is held for the current key.
/// Some keyboards / remote tools send "Ctrl+A" without a separate Ctrl
/// press, which Flutter alone would miss.
bool get browserCtrlHeld =>
    (web.window as JSObject).getProperty<JSBoolean?>('peCtrl'.toJS)?.toDart ??
    false;
