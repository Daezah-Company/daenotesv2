import 'package:daenotes/core/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(Widget rail) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 240,
        height: 80,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rail,
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );

  group('ThreadRail', () {
    testWidgets('connected item: rail carries the thread colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(const ThreadRail(thread: Ds.threadAmber)),
      );

      final rail = find.descendant(
        of: find.byType(ThreadRail),
        matching: find.byType(ColoredBox),
      );
      expect(rail, findsOneWidget);
      expect(tester.widget<ColoredBox>(rail).color, Ds.threadAmber);
      expect(tester.getSize(find.byType(ThreadRail)).width, Ds.railWidth);
    });

    testWidgets('isolated item: rail stays empty (transparent gutter)', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const ThreadRail()));

      final rail = find.descendant(
        of: find.byType(ThreadRail),
        matching: find.byType(ColoredBox),
      );
      expect(rail, findsOneWidget);
      expect(
        tester.widget<ColoredBox>(rail).color,
        const Color(0x00000000),
      ); // gutter preserved, no colour
      expect(tester.getSize(find.byType(ThreadRail)).width, Ds.railWidth);
    });

    testWidgets('note <-> todo mixed pair resolves to moss', (tester) async {
      final color = Ds.threadColor(DaeItemType.note, DaeItemType.todo);
      expect(color, Ds.threadMoss);
      expect(
        Ds.threadColor(DaeItemType.note, DaeItemType.note),
        Ds.threadAmber,
      );
      expect(
        Ds.threadColor(DaeItemType.todo, DaeItemType.todo),
        Ds.threadSlate,
      );
    });

    testWidgets('DsCard composes the rail on its left edge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DsTheme.dark(),
          home: Scaffold(
            body: DsCard(
              thread: Ds.threadSlate,
              child: const SizedBox(height: 40),
            ),
          ),
        ),
      );

      expect(find.byType(ThreadRail), findsOneWidget);
    });

    testWidgets('draw-on inside a card measures by clip, not by height', (
      tester,
    ) async {
      // `DsCard` sizes its row with IntrinsicHeight, which asks the rail for
      // its intrinsic height. A rail that grows by laying out a shorter box
      // throws there; growing by clipping does not.
      await tester.pumpWidget(
        MaterialApp(
          theme: DsTheme.dark(),
          home: Scaffold(
            body: ListView(
              children: [
                DsCard(
                  thread: Ds.threadAmber,
                  drawOn: true,
                  child: const SizedBox(height: 60),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final clip = find.descendant(
        of: find.byType(ThreadRail),
        matching: find.byType(ClipRect),
      );
      expect(clip, findsOneWidget);
      final railHeight = tester.getSize(find.byType(ThreadRail)).height;
      double drawnHeight() => tester
          .widget<ClipRect>(clip)
          .clipper!
          .getClip(Size(Ds.railWidth, railHeight))
          .height;

      // The rail already occupies the card's full height; only the painted
      // slice has grown.
      expect(railHeight, greaterThan(60));
      expect(drawnHeight(), greaterThan(0));
      expect(drawnHeight(), lessThan(railHeight));

      await tester.pumpAndSettle();
      expect(drawnHeight(), railHeight);
      expect(tester.getSize(find.byType(ThreadRail)).height, railHeight);
    });
  });
}
