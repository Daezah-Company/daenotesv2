import 'package:drift/drift.dart';

import '../../core/dae_types.dart';

/// Priority of a todo — wire values are `low|normal|high` (contract §3).
enum TodoPriority {
  low('low'),
  normal('normal'),
  high('high');

  const TodoPriority(this.wire);
  final String wire;

  static TodoPriority fromWire(String? v) => TodoPriority.values.firstWhere(
    (p) => p.wire == v,
    orElse: () => TodoPriority.normal,
  );
}

class DaeItemTypeConverter extends TypeConverter<DaeItemType, String> {
  const DaeItemTypeConverter();

  @override
  DaeItemType fromSql(String fromDb) =>
      DaeItemType.fromWire(fromDb) ?? DaeItemType.note;

  @override
  String toSql(DaeItemType value) => value.wire;
}

class TodoPriorityConverter extends TypeConverter<TodoPriority, String> {
  const TodoPriorityConverter();

  @override
  TodoPriority fromSql(String fromDb) => TodoPriority.fromWire(fromDb);

  @override
  String toSql(TodoPriority value) => value.wire;
}
