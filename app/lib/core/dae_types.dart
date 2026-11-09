import 'dart:ui' show Color;

/// The two item kinds DaeNotes knows about, plus the wire strings used by
/// the API and the drift schema (docs/CONTRACT.md section 3/4).
enum DaeItemType {
  note('note'),
  todo('todo');

  const DaeItemType(this.wire);
  final String wire;

  static DaeItemType? fromWire(String? value) {
    for (final t in DaeItemType.values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

/// Semantic relation role for a connection between two items. Rendering is
/// monochrome; item type remains available for semantics and graph behavior.
///
/// - note <-> note
/// - note <-> todo
/// - todo <-> todo
DaeThread daeThreadBetween(DaeItemType source, DaeItemType target) {
  if (source == DaeItemType.note && target == DaeItemType.note) {
    return DaeThread.noteToNote;
  }
  if (source == DaeItemType.todo && target == DaeItemType.todo) {
    return DaeThread.todoToTodo;
  }
  return DaeThread.noteToTodo;
}

enum DaeThread { noteToNote, noteToTodo, todoToTodo, reminder }

/// Monochrome role colors for NOTE / TODO chips. Kept dependency-free; the
/// widgets resolve contrast from the active theme.
abstract final class DaeTypeMarks {
  static const noteColor = Color(0xFF282828);
  static const todoColor = Color(0xFF282828);
  static const reminderColor = Color(0xFF282828);

  static Color forType(DaeItemType type) =>
      type == DaeItemType.note ? noteColor : todoColor;
}
