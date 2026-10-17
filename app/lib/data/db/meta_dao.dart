import 'database.dart';

/// Key/value bookkeeping on [Metas] — last sync cursor lives here.
extension MetaDao on AppDatabase {
  Future<String?> metaGet(String key) async {
    final row = await (select(
      metas,
    )..where((t) => t.metaKey.equals(key))).getSingleOrNull();
    return row?.metaValue;
  }

  Future<void> metaSet(String key, String value) => into(metas)
      .insertOnConflictUpdate(
        MetasCompanion.insert(metaKey: key, metaValue: value),
      );

  Future<DateTime?> readLastSyncedAt() async {
    final raw = await metaGet(MetaKeys.lastSyncedAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncedAt(DateTime value) =>
      metaSet(MetaKeys.lastSyncedAt, value.toUtc().toIso8601String());
}
