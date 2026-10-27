import 'auth.dart';
import 'local_db.dart';
import 'records.dart';
import 'remote.dart';
import 'repo.dart';
import 'store.dart';

/// Everything the app needs from the outside world (swapped in tests).
class AppEnv {
  final AuthService auth;
  final Future<LocalDb> Function() openDb;
  final Remote Function()? newRemote;

  /// Data from version 1 of the app (phone only, before cloud).
  final Future<List<Rec>?> Function() readOld;
  final Future<void> Function() retireOld;
  final bool autoSync;

  AppEnv({
    required this.auth,
    required this.openDb,
    this.newRemote,
    Future<List<Rec>?> Function()? readOld,
    Future<void> Function()? retireOld,
    this.autoSync = true,
  }) : readOld = readOld ?? (() async => null),
       retireOld = retireOld ?? (() async {});
}

/// The data of the logged-in user on this device.
class Session {
  final AppEnv env;
  final Repo repo;
  final AppStore store;

  Session._(this.env, this.repo, this.store);

  AuthService get auth => env.auth;

  static Future<Session> start(AppEnv env) async {
    final repo = Repo(await env.openDb(), autoSync: env.autoSync);
    await repo.open();

    // First start after updating from version 1: move the phone's old data
    // into the new storage once; it is uploaded with the next sync.
    final old = await env.readOld();
    if (old != null) {
      await repo.put([
        for (final r in old)
          if (repo.get(r.kind, r.id) == null) r,
      ]);
      await env.retireOld();
    }

    final store = AppStore(repo);
    final remote = env.newRemote?.call();
    if (remote != null) repo.attach(remote);
    return Session._(env, repo, store);
  }

  /// Stops syncing and removes this user's data from the device.
  Future<void> end() async {
    await repo.wipe();
    store.dispose();
    repo.dispose();
  }
}
