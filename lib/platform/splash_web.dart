import 'package:web/web.dart' as web;

/// Removes the loading logo shown by index.html once the app has drawn.
void hideWebSplash() => web.document.getElementById('pe-splash')?.remove();
