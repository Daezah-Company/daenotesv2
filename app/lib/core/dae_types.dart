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

/// Which coloured thread a connection between two items carries.
/// Contract section 5: colour appears only on connection threads, type marks
/// and status — never on chrome.
///
/// - note <-> note  -> amber
/// - note <-> todo  -> moss
/// - todo <-> todo  -> slate
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

/// Type mark colour for the NOTE / TODO chips (contract: type marks may carry
/// colour; note reads amber, todo reads slate, reminder/status reads rose).
/// Kept in a plain function so the core layer stays dependency-free.
abstract final class DaeTypeMarks {
  static const noteColor = Color(0xFFE3B23C); // threadAmber
  static const todoColor = Color(0xFF7FA0C8); // threadSlate
  static const reminderColor = Color(0xFFC9768F); // threadRose

  static Color forType(DaeItemType type) =>
      type == DaeItemType.note ? noteColor : todoColor;
}
