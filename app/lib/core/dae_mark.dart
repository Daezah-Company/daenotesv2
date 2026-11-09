import 'package:flutter/material.dart';

/// The user's DaeNotes monogram, framed on paper so it remains clear in the
/// dark-first app chrome.
class DaeMark extends StatelessWidget {
  const DaeMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.18),
        child: Image.asset(
          'assets/branding/daenotes_monogram.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}
