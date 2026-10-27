import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Login names are turned into an internal address on a domain that can
/// never receive email, so password-reset emails cannot be abused.
String loginEmail(String username) =>
    '${username.trim().toLowerCase()}@pe-systems.invalid';

final RegExp kUsernamePattern = RegExp(r'^[a-z0-9][a-z0-9_.-]{0,29}$');

/// Owner password length. The one other login may be as short as the owner
/// wants (the owner asked for a very simple login for the second user).
const int kMinPassword = 8;

/// Only two logins in total: the owner and one other user.
const int kMaxLogins = 2;

const String kUsernameHelp = 'Username: small letters or numbers (no spaces).';

class Member {
  final String username;
  final bool isOwner;
  const Member(this.username, this.isOwner);
}

/// A login problem shown to the user.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// Who is logged in, and account actions.
abstract class AuthService extends ChangeNotifier {
  bool get signedIn;
  String? get username;
  bool get isOwner;

  /// True when no account exists yet (first time only).
  Future<bool> setupNeeded();

  /// Returns null on success, or a message.
  Future<String?> createOwner(
    String setupCode,
    String username,
    String password,
  );
  Future<void> signIn(String username, String password);
  Future<void> signOut({bool everywhere = false});

  /// Returns null on success, or a message.
  Future<String?> changePassword(String oldPassword, String newPassword);

  Future<List<Member>> members();
  Future<void> addMember(String username, String password);
  Future<void> setPassword(String username, String password);
  Future<void> removeMember(String username);

  /// Reloads username / owner flag (after login or when coming online).
  Future<void> refreshMe();

  /// A current login token, to prove the login to the website (app
  /// download). Null when not logged in.
  Future<String?> freshAccessToken() async => null;
}

String _friendly(Object e) {
  final s = e.toString();
  if (s.contains('USERNAME_TAKEN')) return 'This username is already used.';
  if (s.contains('USERNAME_INVALID')) {
    return kUsernameHelp;
  }
  if (s.contains('PASSWORD_SHORT')) return 'Password is too short.';
  if (s.contains('USER_LIMIT')) {
    return 'Only $kMaxLogins logins are allowed. No more users can be added.';
  }
  if (s.contains('NOT_OWNER')) return 'Only the owner can do this.';
  if (s.contains('CANNOT_REMOVE_OWNER')) return 'The owner cannot be removed.';
  if (s.contains('USER_NOT_FOUND')) return 'User not found.';
  if (s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('AuthRetryableFetchException') ||
      s.contains('TimeoutException')) {
    return 'No internet. Please connect and try again.';
  }
  return 'Something went wrong. Please try again.';
}

class SupabaseAuthService extends AuthService {
  final SupabaseClient _db;
  final Future<String?> Function(String key) readCache;
  final Future<void> Function(String key, String? value) writeCache;
  String? _username;
  bool _owner = false;

  SupabaseAuthService(
    this._db, {
    required this.readCache,
    required this.writeCache,
  }) {
    _db.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        _username = null;
        _owner = false;
      }
      notifyListeners();
    });
  }

  /// Restores the remembered name/owner flag so the app works offline.
  Future<void> init() async {
    if (!signedIn) return;
    _username = await readCache('username');
    _owner = await readCache('isOwner') == 'true';
    _username ??= _db.auth.currentUser?.email?.split('@').first;
  }

  @override
  bool get signedIn => _db.auth.currentSession != null;
  @override
  String? get username => _username;
  @override
  bool get isOwner => _owner;

  @override
  Future<bool> setupNeeded() async {
    try {
      return await _db.rpc('pe_setup_needed') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> createOwner(
    String setupCode,
    String username,
    String password,
  ) async {
    try {
      final r = await _db.rpc(
        'pe_create_owner',
        params: {
          'p_setup_code': setupCode,
          'p_username': username,
          'p_password': password,
        },
      );
      switch (r) {
        case 'OK':
          return null;
        case 'WRONG_CODE':
          return 'Setup code is wrong.';
        case 'LOCKED':
          return 'Too many wrong codes. Setup is locked; ask for help.';
        case 'DONE':
          return 'Setup is already done. Please log in.';
      }
      return _friendly(r ?? '');
    } catch (e) {
      return _friendly(e);
    }
  }

  @override
  Future<void> signIn(String username, String password) async {
    try {
      await _db.auth.signInWithPassword(
        email: loginEmail(username),
        password: password,
      );
    } on AuthApiException catch (e) {
      if (e.code == 'invalid_credentials' || e.statusCode == '400') {
        throw const AuthFailure('Wrong username or password.');
      }
      throw AuthFailure(_friendly(e));
    } catch (e) {
      throw AuthFailure(_friendly(e));
    }
    await refreshMe();
    if (_username == null) {
      await _db.auth.signOut();
      throw const AuthFailure('This login has no access to Daily Report.');
    }
  }

  @override
  Future<void> refreshMe() async {
    try {
      final rows = await _db.rpc('pe_me') as List;
      if (rows.isEmpty) {
        _username = null;
        _owner = false;
      } else {
        final m = rows.first as Map;
        _username = m['username'] as String;
        _owner = m['is_owner'] == true;
      }
      await writeCache('username', _username);
      await writeCache('isOwner', '$_owner');
      notifyListeners();
    } catch (_) {
      // Offline: keep the remembered values.
    }
  }

  @override
  Future<String?> freshAccessToken() async {
    var s = _db.auth.currentSession;
    if (s == null) return null;
    if (s.isExpired) {
      try {
        s = (await _db.auth.refreshSession()).session;
      } catch (_) {
        return null;
      }
    }
    return s?.accessToken;
  }

  @override
  Future<void> signOut({bool everywhere = false}) async {
    try {
      await _db.auth.signOut(
        scope: everywhere ? SignOutScope.global : SignOutScope.local,
      );
    } catch (_) {
      await _db.auth.signOut(scope: SignOutScope.local);
    }
    _username = null;
    _owner = false;
    await writeCache('username', null);
    await writeCache('isOwner', null);
    notifyListeners();
  }

  @override
  Future<String?> changePassword(String oldPassword, String newPassword) async {
    try {
      final r = await _db.rpc(
        'pe_change_password',
        params: {'p_old': oldPassword, 'p_new': newPassword},
      );
      return switch (r) {
        'OK' => null,
        'WRONG_OLD' => 'Old password is wrong.',
        'PASSWORD_SHORT' =>
          'Password must be at least $kMinPassword characters.',
        'NOT_ALLOWED' => 'Only the owner can change passwords.',
        _ => 'Something went wrong. Please try again.',
      };
    } catch (e) {
      return _friendly(e);
    }
  }

  @override
  Future<List<Member>> members() async {
    try {
      final rows = await _db
          .from('pe_members')
          .select('username,is_owner')
          .order('username');
      return [
        for (final r in rows)
          Member(r['username'] as String, r['is_owner'] == true),
      ];
    } catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  Future<void> _call(String fn, Map<String, dynamic> params) async {
    try {
      await _db.rpc(fn, params: params);
    } catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<void> addMember(String username, String password) =>
      _call('pe_add_member', {'p_username': username, 'p_password': password});

  @override
  Future<void> setPassword(String username, String password) => _call(
    'pe_set_password',
    {'p_username': username, 'p_password': password},
  );

  @override
  Future<void> removeMember(String username) =>
      _call('pe_remove_member', {'p_username': username});
}

/// Login stand-in for tests and the offline demo build.
class FakeAuthService extends AuthService {
  final Map<String, ({String password, bool owner})> users = {};
  String? _user;
  String setupCode = 'TEST-CODE-0001';

  FakeAuthService({String? signedInAs}) {
    if (signedInAs != null) {
      users[signedInAs] = (password: 'password1', owner: true);
      _user = signedInAs;
    }
  }

  @override
  bool get signedIn => _user != null;
  @override
  String? get username => _user;
  @override
  bool get isOwner => users[_user]?.owner ?? false;

  /// Only accepted by the local update test server, never by the website.
  @override
  Future<String?> freshAccessToken() async =>
      _user == null ? null : 'fake-token';

  @override
  Future<bool> setupNeeded() async => users.isEmpty;

  @override
  Future<String?> createOwner(
    String code,
    String username,
    String password,
  ) async {
    if (users.isNotEmpty) return 'Setup is already done. Please log in.';
    if (code.trim().toUpperCase() != setupCode) return 'Setup code is wrong.';
    final u = username.trim().toLowerCase();
    if (!kUsernamePattern.hasMatch(u)) {
      return kUsernameHelp;
    }
    if (password.length < kMinPassword) {
      return 'Password must be at least $kMinPassword characters.';
    }
    users[u] = (password: password, owner: true);
    return null;
  }

  @override
  Future<void> signIn(String username, String password) async {
    final u = username.trim().toLowerCase();
    if (users[u]?.password != password) {
      throw const AuthFailure('Wrong username or password.');
    }
    _user = u;
    notifyListeners();
  }

  @override
  Future<void> signOut({bool everywhere = false}) async {
    _user = null;
    notifyListeners();
  }

  @override
  Future<String?> changePassword(String oldPassword, String newPassword) async {
    final me = users[_user];
    if (me != null && !me.owner) return 'Only the owner can change passwords.';
    if (me == null || me.password != oldPassword) {
      return 'Old password is wrong.';
    }
    if (newPassword.length < kMinPassword) {
      return 'Password must be at least $kMinPassword characters.';
    }
    users[_user!] = (password: newPassword, owner: me.owner);
    return null;
  }

  @override
  Future<List<Member>> members() async =>
      [for (final e in users.entries) Member(e.key, e.value.owner)]
        ..sort((a, b) => a.username.compareTo(b.username));

  @override
  Future<void> addMember(String username, String password) async {
    if (!isOwner) throw const AuthFailure('Only the owner can do this.');
    final u = username.trim().toLowerCase();
    if (users.length >= kMaxLogins) {
      throw const AuthFailure(
        'Only $kMaxLogins logins are allowed. No more users can be added.',
      );
    }
    if (!kUsernamePattern.hasMatch(u)) throw const AuthFailure(kUsernameHelp);
    if (users.containsKey(u)) {
      throw const AuthFailure('This username is already used.');
    }
    if (password.isEmpty) throw const AuthFailure('Password is too short.');
    users[u] = (password: password, owner: false);
  }

  @override
  Future<void> setPassword(String username, String password) async {
    if (!isOwner) throw const AuthFailure('Only the owner can do this.');
    final u = users[username];
    if (u == null) throw const AuthFailure('User not found.');
    if (password.length < (u.owner ? kMinPassword : 1)) {
      throw const AuthFailure('Password is too short.');
    }
    users[username] = (password: password, owner: u.owner);
  }

  @override
  Future<void> removeMember(String username) async {
    if (!isOwner) throw const AuthFailure('Only the owner can do this.');
    if (users[username]?.owner ?? false) {
      throw const AuthFailure('The owner cannot be removed.');
    }
    users.remove(username);
  }

  @override
  Future<void> refreshMe() async {}
}
