import 'package:daenotes/core/ds.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/providers.dart';
import 'package:daenotes/data/repos/links_repository.dart';
import 'package:daenotes/data/repos/notes_repository.dart';
import 'package:daenotes/data/repos/outbox.dart';
import 'package:daenotes/data/repos/todos_repository.dart';
import 'package:daenotes/features/notes/dae_inbox.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeded local store shared by the inbox tests. Everything here is offline —
/// no transport, no HTTP — so the UI renders straight from drift.
class _Local {
  _Local() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
    notes = NotesRepository(db, outbox);
    todos = TodosRepository(db, outbox);
    links = LinksRepository(db, outbox);
  }

  late final AppDatabase db;
  late final Outbox outbox;
  late final NotesRepository notes;
  late final TodosRepository todos;
  late final LinksRepository links;

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      notesRepositoryProvider.overrideWithValue(notes),
      todosRepositoryProvider.overrideWithValue(todos),
      linksRepositoryProvider.overrideWithValue(links),
    ],
    child: MaterialApp(theme: DsTheme.dark(), home: child),
  );

  Future<void> dispose() async => db.close();
}

/// Unmounts the tree inside the test body so drift's StreamQuery close timers
/// fire while we can still pump — otherwise they stay pending at teardown and
/// flutter_test asserts "A Timer is still pending".
Future<void> drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Local local;

  setUp(() => local = _Local());
  tearDown(() => local.dispose());

  Future<Color?> railColor(WidgetTester tester, String uuid) async {
    final row = find.byKey(ValueKey('row-$uuid'));
    final rail = find.descendant(of: row, matching: find.byType(ThreadRail));
    final box = find.descendant(of: rail, matching: find.byType(ColoredBox));
    expect(box, findsOneWidget, reason: 'row $uuid must render a rail');
    return tester.widget<ColoredBox>(box).color;
  }

  testWidgets(
    'linked note carries its thread colour; isolated note stays colourless',
    (tester) async {
      final a = await local.notes.create(title: 'Benang A');
      final b = await local.notes.create(title: 'Benang B');
      final isolated = await local.notes.create(title: 'Terisolasi');
      await local.links.link(
        sourceType: DaeItemType.note,
        sourceUuid: a,
        targetType: DaeItemType.note,
        targetUuid: b,
      );

      await tester.pumpWidget(local.wrap(const DaeInboxScreen()));
      await tester.pumpAndSettle();

      // Thread connections use the app's monochrome surface color.
      expect(await railColor(tester, a), Ds.paper);
      expect(await railColor(tester, b), Ds.paper);

      // The isolated item keeps the empty gutter — no colour.
      expect(await railColor(tester, isolated), const Color(0x00000000));
      await drain(tester);
    },
  );

  testWidgets('note linked to a todo reads moss on the rail', (tester) async {
    final note = await local.notes.create(title: 'Belanja mingguan');
    final todo = await local.todos.create(title: 'Ambil kopi');
    await local.links.link(
      sourceType: DaeItemType.note,
      sourceUuid: note,
      targetType: DaeItemType.todo,
      targetUuid: todo,
    );

    await tester.pumpWidget(local.wrap(const DaeInboxScreen()));
    await tester.pumpAndSettle();

    expect(await railColor(tester, note), Ds.paper);
    expect(await railColor(tester, todo), Ds.paper);
    await drain(tester);
  });
}
