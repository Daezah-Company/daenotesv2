import 'package:intl/intl.dart';

/// Utility formatting for the mono caption voice: relative time ("2h",
/// "tomorrow"), due labels, IDs. Kept in core so every feature formats
/// timestamps identically.
abstract final class DsTime {
  /// Compact relative time for list rows: `now`, `12m`, `2h`, `3d`, `2w`.
  static String relative(DateTime time, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = n.difference(time);
    if (diff.isNegative || diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 70) return '${(diff.inDays / 7).floor()}w';
    return DateFormat('d MMM y').format(time);
  }

  /// Due-date label for todos: `today`, `tomorrow`, `yesterday`, `Mon 4`,
  /// or `4 Jan` for later dates.
  static String dueLabel(DateTime due, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final d = DateTime(due.year, due.month, due.day);
    final today = DateTime(n.year, n.month, n.day);
    final days = d.difference(today).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'tomorrow';
    if (days == -1) return 'yesterday';
    if (days > 1 && days < 7) return DateFormat('EEE').format(d);
    return DateFormat('d MMM').format(d);
  }

  static String clock(DateTime time) => DateFormat('HH:mm').format(time);

  /// ISO-8601 for API payloads.
  static String iso(DateTime time) => time.toUtc().toIso8601String();
}
