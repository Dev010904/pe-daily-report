import 'package:daily_report/data/local_db.dart';
import 'package:daily_report/data/remote.dart';
import 'package:daily_report/data/repo.dart';
import 'package:daily_report/data/store.dart';
import 'package:daily_report/models/day_data.dart';

/// A store on a fresh in-memory device, optionally linked to [cloud].
Future<AppStore> newStore({FakeRemote? cloud, MemoryLocalDb? db}) async {
  final repo = Repo(db ?? MemoryLocalDb(), autoSync: false);
  await repo.open();
  if (cloud != null) repo.attach(cloud);
  return AppStore(repo);
}

var _n = 0;

Entry entry(
  String company, {
  String? companyId,
  Map<String, int>? full,
  Map<String, int>? empty,
  List<CashItem>? cash,
  bool billed = false,
}) => Entry(
  id: 'e${++_n}',
  sort: _n,
  companyId: companyId,
  company: company,
  full: full,
  empty: empty,
  cash: cash,
  billed: billed,
);
