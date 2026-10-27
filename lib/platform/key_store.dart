import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Small private values (login session, username). On the phone they are
/// kept in Android's encrypted storage. On the website they are kept only in
/// memory, so closing or refreshing the page always asks for the login.
class KeyStore {
  static const _secure = FlutterSecureStorage();
  final Map<String, String> _memory = {};

  Future<String?> read(String key) async {
    if (kIsWeb) return _memory[key];
    return _secure.read(key: 'pe_$key');
  }

  Future<void> write(String key, String? value) async {
    if (kIsWeb) {
      if (value == null) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
      return;
    }
    if (value == null) {
      await _secure.delete(key: 'pe_$key');
    } else {
      await _secure.write(key: 'pe_$key', value: value);
    }
  }
}

/// Keeps the Supabase login session in encrypted storage on the phone.
class SecureSessionStorage extends LocalStorage {
  final KeyStore _keys;
  SecureSessionStorage(this._keys);

  static const _k = 'session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _keys.read(_k)) != null;

  @override
  Future<String?> accessToken() => _keys.read(_k);

  @override
  Future<void> removePersistedSession() => _keys.write(_k, null);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _keys.write(_k, persistSessionString);
}
