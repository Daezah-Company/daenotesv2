import 'package:daenotes/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the original account keeps legacy offline data, other accounts isolate',
    () {
      expect(
        AppDatabase.databaseNameForAccount(userId: 12, legacyOwnerId: 12),
        'daenotes',
      );
      expect(
        AppDatabase.databaseNameForAccount(userId: 34, legacyOwnerId: 12),
        'daenotes_user_34',
      );
      expect(
        AppDatabase.databaseNameForAccount(userId: null, legacyOwnerId: 12),
        'daenotes',
      );
    },
  );
}
