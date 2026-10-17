import 'package:daenotes/core/ds.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/providers.dart';
import 'package:daenotes/data/repos/links_repository.dart';
import 'package:daenotes/data/repos/notes_repository.dart';
import 'package:daenotes/data/repos/outbox.dart';
import 'package:daenotes/data/repos/todos_repository.dart';
import 'package:daenotes/features/notes/dae_inbox.dart';
import 'package:daenotes/features/notes/widgets/dae_widgets.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Outbox outbox;
  late TodosRepository todos;
  late NotesRepository notes;
  late LinksRepository links;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
    todos = TodosRepository(db, outbox);
    notes = NotesRepository(db, outbox);
    links = LinksRepository(db, outbox);
  });

  tearDown(() async => db.close());

  test('toggle persists through the repository and stamps done_at', () async {
    final uuid = await todos.create(title: 'Kirim laporan');

    var row = await todos.byUuid(uuid);
    expect(row?.done, isFalse);
    expect(row?.doneAt, isNull);

    await todos.toggle(uuid);
    row = await todos.byUuid(uuid);
    expect(row?.done, isTrue);
    expect(row?.doneAt, isNotNull);

    await todos.toggle(uuid);
    row = await todos.byUuid(uuid);
    expect(row?.done, isFalse);
    expect(row?.doneAt, isNull);

    // Local writes are queued to the outbox automatically.
    expect(await outbox.all(), isNotEmpty);
  });

  testWidgets('completing a todo in the inbox is instant and persisted', (
    tester,
  ) async {
    final uuid = await todos.create(title: 'Siram tanaman');

    Widget wrap(Widget child) => ProviderScope(
      overrides: [
        todosRepositoryProvider.overrideWithValue(todos),
        notesRepositoryProvider.overrideWithValue(notes),
        linksRepositoryProvider.overrideWithValue(links),
      ],
      child: MaterialApp(theme: DsTheme.dark(), home: child),
    );

    await tester.pumpWidget(wrap(const DaeInboxScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DsCheckToggle));
    await tester.pumpAndSettle();

    // Reflected back through the repository, not just the widget tree.
    final row = await todos.byUuid(uuid);
    expect(row?.done, isTrue);

    // The rail/row repaint: tapping the check toggles it back.
    await tester.tap(find.byType(DsCheckToggle));
    await tester.pumpAndSettle();
    expect((await todos.byUuid(uuid))?.done, isFalse);

    // Unmount inside the body so drift's stream-close timers fire before the
    // test teardown, then advance the fake clock to drain them.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
