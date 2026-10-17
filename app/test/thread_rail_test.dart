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
  });
}
