import 'local_db.dart';
import 'records.dart';

/// The PC website is always online, so it keeps data in memory and loads
/// everything from the cloud after login.
Future<LocalDb> openDeviceDb() async => MemoryLocalDb();

Future<List<Rec>?> readOldVersionData() async => null;

Future<void> retireOldVersionData() async {}
