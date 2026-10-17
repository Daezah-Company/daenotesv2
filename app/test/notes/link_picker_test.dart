import 'package:daenotes/core/ds.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/providers.dart';
import 'package:daenotes/data/repos/links_repository.dart';
import 'package:daenotes/data/repos/notes_repository.dart';
import 'package:daenotes/data/repos/outbox.dart';
import 'package:daenotes/data/repos/todos_repository.dart';
import 'package:daenotes/features/notes/dae_item.dart';
import 'package:daenotes/features/notes/linking.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Outbox outbox;
  late NotesRepository notes;
  late LinksRepository links;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
    notes = NotesRepository(db, outbox);
    links = LinksRepository(db, outbox);
  });

  tearDown(() async => db.close());

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      notesRepositoryProvider.overrideWithValue(notes),
      todosRepositoryProvider.overrideWithValue(TodosRepository(db, outbox)),
      linksRepositoryProvider.overrideWithValue(links),
    ],
    child: MaterialApp(
      theme: DsTheme.dark(),
      home: Scaffold(body: child),
    ),
  );

  /// Unmounts the tree inside the test body so drift's StreamQuery close timers
  /// fire while we can still pump (otherwise flutter_test asserts "A Timer is
  /// still pending" at teardown).
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  test('LinksRepository.link dedupes a pair and never creates a second edge', () async {
    final a = await notes.create(title: 'Alpha');
    final b = await notes.create(title: 'Beta');

    final first = await links.link(
      sourceType: DaeItemType.note,
      sourceUuid: a,
      targetType: DaeItemType.note,
      targetUuid: b,
    );
    // Reverse direction is the same pair — the unique rule mirrors it locally.
    final second = await links.link(
      sourceType: DaeItemType.note,
      sourceUuid: b,
      targetType: DaeItemType.note,
      targetUuid: a,
    );

    expect(second, first, reason: 'duplicate pair returns the existing link');
    expect(await links.neighbors(DaeItemType.note, a), hasLength(1));
  });

  testWidgets('picker offers only connectable items: no self, no duplicate', (
    tester,
  ) async {
    final a = await notes.create(title: 'Sumber');
    final alreadyLinked = await notes.create(title: 'Sudah Connect');
    final fresh = await notes.create(title: 'Belum Connect');
    await links.link(
      sourceType: DaeItemType.note,
      sourceUuid: a,
      targetType: DaeItemType.note,
      targetUuid: alreadyLinked,
    );

    await tester.pumpWidget(
      wrap(LinkPickerSheet(from: DaeItemRef(DaeItemType.note, a))),
    );
    await tester.pumpAndSettle();

    // Self and the already-linked item are filtered out of the candidates.
    expect(find.text('Sumber'), findsNothing);
    expect(find.text('Sudah Connect'), findsNothing);
    // The unconnected item is offered.
    expect(find.text('Belum Connect'), findsOneWidget);

    // Tapping it connects without duplicating the excluded pair.
    await tester.tap(find.text('Belum Connect'));
    await tester.pumpAndSettle();

    expect(fresh, isNotEmpty);
    expect(await links.neighbors(DaeItemType.note, a), hasLength(2));
    expect(
      await links.neighbors(DaeItemType.note, alreadyLinked),
      hasLength(1),
    );
    await drain(tester);
  });
}
