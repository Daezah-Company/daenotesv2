import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/token_storage.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'db/database.dart';
import 'repos/links_repository.dart';
import 'repos/notes_repository.dart';
import 'repos/outbox.dart';
import 'repos/reminders_repository.dart';
import 'repos/todos_repository.dart';
import 'sync/network_status.dart';
import 'sync/sync_engine.dart';
import 'sync/transport.dart';

/// Composition root for the data layer. Features watch these — never build
/// their own clients.
///
/// Swap any provider in tests with `ProviderScope(overrides: [...])`:
/// `databaseProvider` -> in-memory drift, `syncTransportProvider` -> fake,
/// `apiClientProvider` -> stub.

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokens: ref.watch(tokenStorageProvider),
    onUnauthorized: () =>
        ref.read(authControllerProvider.notifier).forceLoggedOut(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);

/// Session state: `AsyncValue<AuthSession?>`; `data == null` => signed out.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final outboxProvider = Provider<Outbox>(
  (ref) => Outbox(ref.watch(databaseProvider)),
);

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) =>
      NotesRepository(ref.watch(databaseProvider), ref.watch(outboxProvider)),
);

final todosRepositoryProvider = Provider<TodosRepository>(
  (ref) =>
      TodosRepository(ref.watch(databaseProvider), ref.watch(outboxProvider)),
);

final linksRepositoryProvider = Provider<LinksRepository>(
  (ref) =>
      LinksRepository(ref.watch(databaseProvider), ref.watch(outboxProvider)),
);

final remindersRepositoryProvider = Provider<RemindersRepository>(
  (ref) => RemindersRepository(
    ref.watch(databaseProvider),
    ref.watch(outboxProvider),
  ),
);

final networkStatusProvider = Provider<NetworkStatus>((ref) => NetworkStatus());

/// The wire seam — override with a fake transport in tests.
final syncTransportProvider = Provider<SyncTransport>(
  (ref) => ApiSyncTransport(ref.watch(apiClientProvider)),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    db: ref.watch(databaseProvider),
    transport: ref.watch(syncTransportProvider),
    outbox: ref.watch(outboxProvider),
    network: ref.watch(networkStatusProvider),
  );
  engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Live sync status for the shell badge / retry affordance.
final syncStatusProvider = StreamProvider<SyncState>(
  (ref) => ref.watch(syncEngineProvider).status,
);
