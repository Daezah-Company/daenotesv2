import 'package:daenotes/core/dae_types.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/providers.dart';
import 'package:daenotes/features/graph/graph_canvas.dart';
import 'package:daenotes/features/graph/graph_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Widget-level checks for the graph screen, all against an in-memory drift
/// database — the offline path, no transport touched.
void main() {
  late AppDatabase db;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // `closeStreamsSynchronously` stops drift from leaving a zero-duration GC
    // timer behind when a watch stream loses its last listener — widget tests
    // fail on pending timers otherwise.
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<Widget> harness(Widget child) async {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: child,
      ),
    );
  }

  Future<void> seed({
    List<(String, String)> notes = const [],
    List<(String, String)> todos = const [],
    List<(String, DaeItemType, String, DaeItemType, String)> links = const [],
  }) async {
    final now = DateTime(2026, 10, 1);
    for (final (uuid, title) in notes) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              uuid: uuid,
              title: Value(title),
              updatedAt: now,
            ),
          );
    }
    for (final (uuid, title) in todos) {
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              uuid: uuid,
              title: Value(title),
              updatedAt: now,
            ),
          );
    }
    for (final (uuid, st, su, tt, tu) in links) {
      await db
          .into(db.links)
          .insert(
            LinksCompanion.insert(
              uuid: uuid,
              sourceType: st,
              sourceUuid: su,
              targetType: tt,
              targetUuid: tu,
              updatedAt: now,
            ),
          );
    }
  }

  GraphCanvasState canvasState(WidgetTester tester) =>
      tester.state<GraphCanvasState>(find.byType(GraphCanvas));

  Offset nodeAt(WidgetTester tester, String uuid) {
    final state = canvasState(tester);
    final body = state.sim!.body(uuid)!;
    return state.view.worldToScreen(body.position);
  }

  /// This flutter_test build has no `doubleTapAt` — two taps inside the
  /// double-tap window trigger the recognizer.
  Future<void> doubleTapAt(WidgetTester tester, Offset where) async {
    await tester.tapAt(where);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(where);
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// A single tap only resolves once the double-tap recogniser gives up
  /// (~300 ms), and its countdown timer must drain before the test ends.
  Future<void> settleGestures(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 450));

  testWidgets('empty vault shows the invitation, not a dead canvas', (
    tester,
  ) async {
    await tester.pumpWidget(await harness(const GraphScreen()));
    await tester.pump(); // let the drift watch streams deliver
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Belum ada yang terhubung'), findsOneWidget);
  });

  testWidgets('live data renders the canvas, settles, and stops ticking', (
    tester,
  ) async {
    await seed(
      notes: [('n-1', 'Alpha'), ('n-2', 'Beta')],
      todos: [('t-1', 'Gamma')],
      links: [
        ('l-1', DaeItemType.note, 'n-1', DaeItemType.note, 'n-2'),
        ('l-2', DaeItemType.note, 'n-1', DaeItemType.todo, 't-1'),
      ],
    );
    await tester.pumpWidget(await harness(const GraphScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CustomPaint, skipOffstage: false), findsWidgets);
    // Reveal + simulation are both bounded: pumpAndSettle must return.
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(canvasState(tester).sim!.settled, isTrue);
    expect(canvasState(tester).revealActive, isFalse);
  });

  testWidgets('tap selects a node and surfaces its neighbours; double-tap '
      'opens via callback', (tester) async {
    final opened = <(DaeItemType, String)>[];
    await seed(
      notes: [('n-1', 'Alpha'), ('n-2', 'Beta')],
      links: [('l-1', DaeItemType.note, 'n-1', DaeItemType.note, 'n-2')],
    );
    await tester.pumpWidget(
      await harness(GraphScreen(onOpenItem: (t, u) => opened.add((t, u)))),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    await tester.tapAt(nodeAt(tester, 'n-1'));
    await settleGestures(tester);
    expect(canvasState(tester).selectedUuid, 'n-1');
    // Neighbour surfaced in the panel.
    expect(find.text('Beta'), findsWidgets);
    // DsEyebrow renders its label uppercased.
    expect(find.text('1 BENANG LANGSUNG'), findsOneWidget);

    await doubleTapAt(tester, nodeAt(tester, 'n-2'));
    await settleGestures(tester);
    expect(opened, [(DaeItemType.note, 'n-2')]);
  });

  testWidgets('selection state is announced through node Semantics', (
    tester,
  ) async {
    await seed(
      notes: [('n-1', 'Alpha'), ('n-2', 'Beta')],
      links: [('l-1', DaeItemType.note, 'n-1', DaeItemType.note, 'n-2')],
    );
    await tester.pumpWidget(await harness(const GraphScreen()));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    canvasState(tester).select('n-1');
    await tester.pump();
    final sel = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.contains('terpilih') ?? false) &&
          (w.properties.label?.contains('Alpha') ?? false),
    );
    expect(sel, findsWidgets);
    final unlinked = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.contains('belum tertaut') ?? false),
    );
    expect(unlinked, findsNothing); // both nodes have a thread here
  });

  testWidgets('focusOn centres the deep-linked node', (tester) async {
    await seed(
      notes: [('n-1', 'Alpha'), ('n-2', 'Beta')],
      links: [('l-1', DaeItemType.note, 'n-1', DaeItemType.note, 'n-2')],
    );
    await tester.pumpWidget(await harness(const GraphScreen()));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    final state = canvasState(tester);
    state.focusOn('n-2');
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    final screen = state.view.worldToScreen(state.sim!.body('n-2')!.position);
    final vp = state.view.viewport;
    final center = Offset(vp.width / 2, vp.height / 2);
    expect((screen - center).distance, lessThan(2));
  });

  testWidgets('reduce-motion skips the thread draw entirely', (tester) async {
    await seed(
      notes: [('n-1', 'Alpha'), ('n-2', 'Beta')],
      links: [('l-1', DaeItemType.note, 'n-1', DaeItemType.note, 'n-2')],
    );
    await tester.pumpWidget(
      await harness(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: GraphScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final state = canvasState(tester);
    expect(state.revealActive, isFalse);
    expect(state.revealValue.value, 1.0);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(state.sim!.settled, isTrue);
  });

  testWidgets('isolated nodes are modelled and visible in semantics', (
    tester,
  ) async {
    await seed(
      notes: [('n-1', 'Linked One'), ('n-2', 'Linked Two'), ('n-3', 'Alone')],
      links: [('l-1', DaeItemType.note, 'n-1', DaeItemType.note, 'n-2')],
    );
    await tester.pumpWidget(await harness(const GraphScreen()));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('1 item tak tertaut di tepi kanvas'), findsOneWidget);
    final alone = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.contains('Alone') ?? false) &&
          (w.properties.label?.contains('belum tertaut') ?? false),
    );
    expect(alone, findsWidgets);
  });
}
