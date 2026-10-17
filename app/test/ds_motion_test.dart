import 'package:daenotes/core/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The motion pass rests on one rule the rest of the app leans on: calm, shared
/// timing, and nothing moves under reduce-motion. These tests lock the
/// vocabulary so a later widget can't quietly invent its own curve or a press
/// that survives an accessibility request.
void main() {
  Widget wrap(Widget child, {bool reduceMotion = false}) {
    Widget content = child;
    if (reduceMotion) {
      // Inside MaterialApp's own MediaQuery so only disableAnimations flips —
      // the switch every Ds* motion widget listens to.
      content = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child,
        ),
      );
    }
    return MaterialApp(
      theme: DsTheme.dark(),
      home: Scaffold(body: Center(child: content)),
    );
  }

  group('DsMotion vocabulary', () {
    test('entrance decelerates, exit accelerates', () {
      expect(DsMotion.enter.transform(0.25), greaterThan(0.25));
      expect(DsMotion.exit.transform(0.25), lessThan(0.25));
    });

    test('a long list still finishes its cascade inside half a second', () {
      expect(DsMotion.staggerDelay(40), DsMotion.staggerDelay(99));
      expect(
        DsMotion.panel + DsMotion.staggerDelay(40),
        lessThanOrEqualTo(const Duration(milliseconds: 600)),
      );
    });
  });

  group('DsEnter', () {
    testWidgets('a later row waits for the earlier one, then all land', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: const [
              DsEnter(index: 0, child: Text('a')),
              DsEnter(index: 3, child: Text('b')),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      double opacityOf(String label) {
        final finder = find.ancestor(
          of: find.text(label),
          matching: find.byType(Opacity),
        );
        final opacities = tester.widgetList<Opacity>(finder).toList();
        return opacities.last.opacity;
      }

      expect(opacityOf('a'), greaterThan(0.5));
      expect(opacityOf('b'), 0.0); // still inside its stagger delay

      await tester.pumpAndSettle();
      expect(opacityOf('a'), 1.0);
      expect(opacityOf('b'), 1.0);
    });

    testWidgets('reduce-motion renders it in place, no animation at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const DsEnter(index: 4, child: Text('a')), reduceMotion: true),
      );
      await tester.pump();

      expect(find.text('a'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DsEnter),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('DsPressable', () {
    Future<void> press(WidgetTester tester) async {
      final center = tester.getRect(find.byType(SizedBox)).center;
      final gesture = await tester.startGesture(center);
      await tester.pump(DsMotion.press);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('shrinks under the finger and settles back to 1', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          DsPressable(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      );
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);

      final center = tester.getRect(find.byType(SizedBox)).center;
      final gesture = await tester.startGesture(center);
      await tester.pump(DsMotion.press);
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        0.975,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });

    testWidgets('a disabled control never moves', (tester) async {
      await tester.pumpWidget(
        wrap(
          DsPressable(
            enabled: false,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      final center = tester.getRect(find.byType(SizedBox)).center;
      final gesture = await tester.startGesture(center);
      await tester.pump(DsMotion.press);

      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('reduce-motion keeps the tap and drops the squeeze', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          DsPressable(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
          reduceMotion: true,
        ),
      );
      await press(tester);
      expect(taps, 1);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });
  });

  group('DsTabBar', () {
    testWidgets('one underline travels to the chosen tab', (tester) async {
      var index = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: DsTheme.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, setState) => DsTabBar(
                    labels: const ['Beranda', 'Graf', 'Pengingat'],
                    currentIndex: index,
                    onChanged: (i) => setState(() => index = i),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The underline is the only ColoredBox inside the strip.
      final underline = find.descendant(
        of: find.byType(DsTabBar),
        matching: find.byType(ColoredBox),
      );
      expect(underline, findsOneWidget);
      final start = tester.getRect(underline).left;

      await tester.tap(find.text('GRAF'));
      await tester.pump();
      await tester.pump(DsMotion.panel ~/ 2);
      final midway = tester.getRect(underline).left;
      expect(midway, greaterThan(start));
      expect(midway, lessThan(start + 100));

      await tester.pumpAndSettle();
      expect(tester.getRect(underline).left, closeTo(start + 100, 0.5));
    });

    testWidgets('reduce-motion jumps the underline instead of sliding', (
      tester,
    ) async {
      var index = 0;
      Widget bar() => Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: SizedBox(
            width: 300,
            child: DsTabBar(
              labels: const ['Beranda', 'Graf', 'Pengingat'],
              currentIndex: index,
              onChanged: (i) => index = i,
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: DsTheme.dark(),
          home: Scaffold(body: Center(child: bar())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedPositioned), findsNothing);
      expect(find.byType(Positioned), findsWidgets);
    });
  });

  group('DsRouteTransition', () {
    testWidgets('drifts in, and the page behind settles back', (tester) async {
      final incoming = AnimationController(
        vsync: const TestVSync(),
        value: 0.4,
        duration: DsMotion.page,
      );
      final outgoing = AnimationController(
        vsync: const TestVSync(),
        value: 0.5,
        duration: DsMotion.page,
      );
      addTearDown(incoming.dispose);
      addTearDown(outgoing.dispose);

      await tester.pumpWidget(
        wrap(
          DsRouteTransition(
            animation: incoming,
            secondaryAnimation: outgoing,
            child: const SizedBox(width: 60, height: 60),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(DsRouteTransition),
          matching: find.byType(FractionalTranslation),
        ),
        findsOneWidget,
      );
      // Incoming drift+fade and the outgoing settle+dim, all inside this one
      // transition (MaterialApp has its own route fade above us).
      expect(
        find.descendant(
          of: find.byType(DsRouteTransition),
          matching: find.byType(Opacity),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('reduce-motion keeps the fade, drops the displacement', (
      tester,
    ) async {
      final incoming = AnimationController(
        vsync: const TestVSync(),
        value: 0.4,
        duration: DsMotion.page,
      );
      addTearDown(incoming.dispose);

      await tester.pumpWidget(
        wrap(
          DsRouteTransition(
            animation: incoming,
            child: const SizedBox(width: 60, height: 60),
          ),
          reduceMotion: true,
        ),
      );

      expect(
        find.descendant(
          of: find.byType(DsRouteTransition),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DsRouteTransition),
          matching: find.byType(FractionalTranslation),
        ),
        findsNothing,
      );
    });
  });
}
