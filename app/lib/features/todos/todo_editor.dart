import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/model/enums.dart';
import '../../data/providers.dart';
import '../collaboration/share_item_sheet.dart';
import '../notes/dae_providers.dart';
import '../notes/dae_save.dart';
import '../notes/linking.dart';
import '../notes/widgets/dae_widgets.dart';
import '../reminders/reminders_controller.dart';

/// Quick-capture todo sheet. Creates the row lazily on the first keystroke,
/// autosaves title + note, and lets priority be set before it's even opened
/// in full.
class TodoEditorSheet extends ConsumerStatefulWidget {
  const TodoEditorSheet({super.key, this.initialTitle = ''});

  final String initialTitle;

  static Future<void> show(BuildContext context, {String initialTitle = ''}) {
    return showDsSheet<void>(
      context,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: TodoEditorSheet(initialTitle: initialTitle),
      ),
    );
  }

  @override
  ConsumerState<TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends ConsumerState<TodoEditorSheet> {
  final _save = DaeDebouncer();
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  final TextEditingController _note = TextEditingController();
  final TextEditingController _groupName = TextEditingController();
  TodoPriority _priority = TodoPriority.normal;
  String? _uuid;

  @override
  void dispose() {
    _save.flush();
    _save.cancel();
    _title.dispose();
    _note.dispose();
    _groupName.dispose();
    super.dispose();
  }

  void _onChange(String _) => _save.schedule(_persist);

  Future<void> _persist() async {
    final repo = ref.read(todosRepositoryProvider);
    final title = _title.text;
    final note = _note.text;
    final groupName = _groupName.text.trim();
    if (title.trim().isEmpty && note.trim().isEmpty) return;
    if (_uuid == null) {
      final created = await repo.create(
        title: title,
        notes: note,
        groupName: groupName,
        priority: _priority,
      );
      if (!mounted) return;
      setState(() => _uuid = created);
    } else {
      await repo.update(
        _uuid!,
        title: title,
        notes: Value(note),
        groupName: groupName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s3, Ds.s4, Ds.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DsSectionHeader(
              text: 'Tugas baru',
              trailing: DsButton.ghost(
                label: 'Selesai',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: Ds.s4),
            TextField(
              controller: _title,
              onChanged: _onChange,
              textCapitalization: TextCapitalization.sentences,
              style: DsType.display(
                size: Ds.displayM,
                color: context.dae.onSurface,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Apa yang perlu dikerjakan?',
              ),
            ),
            const SizedBox(height: Ds.s4),
            DsField(
              label: 'Grup',
              child: TextField(
                controller: _groupName,
                maxLength: 80,
                onChanged: _onChange,
                decoration: const InputDecoration(
                  hintText: 'Contoh: Kuliah, Kerja, Pribadi',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: Ds.s3),
            DsField(
              label: 'Prioritas',
              child: DsPriorityPicker(
                value: _priority,
                onChanged: (p) => setState(() => _priority = p),
              ),
            ),
            const SizedBox(height: Ds.s3),
            DsText.caption(_uuid == null ? 'menyimpan otomatis' : 'tersimpan'),
          ],
        ),
      ),
    );
  }
}

/// Full todo detail: instant optimistic completion, autosaved title/note,
/// priority, due date + reminder time, and the linking surface.
class TodoDetailScreen extends ConsumerStatefulWidget {
  const TodoDetailScreen({super.key, required this.uuid});

  final String uuid;

  @override
  ConsumerState<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends ConsumerState<TodoDetailScreen> {
  final _save = DaeDebouncer();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _groupName = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _save.flush();
    _save.cancel();
    _title.dispose();
    _note.dispose();
    _groupName.dispose();
    super.dispose();
  }

  void _onChange(String _) => _save.schedule(_persist);

  Future<void> _persist() async {
    if (ref.read(todoByUuidProvider(widget.uuid)).value?.canEdit == false) {
      return;
    }
    final repo = ref.read(todosRepositoryProvider);
    await repo.update(
      widget.uuid,
      title: _title.text,
      notes: Value(_note.text),
      groupName: _groupName.text.trim(),
    );
  }

  Future<void> _pickDue(DateTime? current) async {
    if (ref.read(todoByUuidProvider(widget.uuid)).value?.canEdit == false) {
      return;
    }
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    final base = current;
    final due = DateTime(
      picked.year,
      picked.month,
      picked.day,
      base?.hour ?? 9,
      base?.minute ?? 0,
    );
    await ref
        .read(todosRepositoryProvider)
        .update(widget.uuid, dueAt: Value(due));
  }

  Future<void> _pickReminder(DateTime? current) async {
    if (ref.read(todoByUuidProvider(widget.uuid)).value?.canEdit == false) {
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (time == null) return;
    final when = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Through the reminders feature so the row, `remind_at`, and the local
    // notification all move together (docs/HANDOFF.md §NOTES-TODOS 3).
    final saved = ref.read(todoByUuidProvider(widget.uuid)).value;
    final title = _title.text.trim().isNotEmpty
        ? _title.text.trim()
        : (saved?.title ?? 'Tugas');
    await ref
        .read(reminderActionsProvider)
        .scheduleForTodo(todoUuid: widget.uuid, title: title, when: when);
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final todo = ref.watch(todoByUuidProvider(widget.uuid)).value;
    final canEdit = todo?.canEdit ?? true;

    if (!_seeded && todo != null) {
      _title.text = todo.title;
      _note.text = todo.notes ?? '';
      _groupName.text = todo.groupName ?? '';
      _seeded = true;
    }

    if (todo == null && !_seeded) {
      return Scaffold(
        backgroundColor: dae.background,
        body: Center(child: DsText.caption('membuka dari perangkat…')),
      );
    }

    final done = todo?.done ?? false;

    return Scaffold(
      backgroundColor: dae.background,
      body: SafeArea(
        child: Column(
          children: [
            _TodoHeader(
              done: done,
              canEdit: canEdit,
              onShare: () =>
                  ShareItemSheet.show(context, type: 'todo', uuid: widget.uuid),
              onToggle: () {
                // Optimistic: local write lands immediately, the drift stream
                // repaints the check, the outbox syncs in the background.
                ref.read(todosRepositoryProvider).toggle(widget.uuid);
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s2, Ds.s4, Ds.s8),
                children: [
                  if (!canEdit)
                    DsText.caption('Hanya melihat · akses diatur pemilik.'),
                  TextField(
                    controller: _title,
                    onChanged: _onChange,
                    readOnly: !canEdit,
                    maxLines: null,
                    style: DsType.display(
                      size: Ds.displayM,
                      color: done ? dae.onSurfaceSecondary : dae.onSurface,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Judul tugas',
                    ),
                  ),
                  const SizedBox(height: Ds.s5),
                  DsField(
                    label: 'Grup',
                    child: TextField(
                      controller: _groupName,
                      maxLength: 80,
                      onChanged: _onChange,
                      readOnly: !canEdit,
                      decoration: const InputDecoration(
                        hintText: 'Contoh: Kuliah, Kerja, Pribadi',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: Ds.s5),
                  DsField(
                    label: 'Catatan',
                    child: TextField(
                      controller: _note,
                      onChanged: _onChange,
                      readOnly: !canEdit,
                      minLines: 1,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: DsType.body(color: dae.onSurface),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Detail…',
                      ),
                    ),
                  ),
                  const SizedBox(height: Ds.s5),
                  IgnorePointer(
                    ignoring: !canEdit,
                    child: DsField(
                      label: 'Prioritas',
                      child: DsPriorityPicker(
                        value: todo?.priority ?? TodoPriority.normal,
                        onChanged: (p) => ref
                            .read(todosRepositoryProvider)
                            .update(widget.uuid, priority: p),
                      ),
                    ),
                  ),
                  const SizedBox(height: Ds.s4),
                  IgnorePointer(
                    ignoring: !canEdit,
                    child: DsField(
                      label: 'Waktu',
                      child: Column(
                        children: [
                          _DateActionRow(
                            icon: Icons.event_outlined,
                            label: 'Tenggat',
                            value: todo?.dueAt,
                            onPick: () => _pickDue(todo?.dueAt),
                          ),
                          const SizedBox(height: Ds.s2),
                          _DateActionRow(
                            icon: Icons.notifications_none,
                            label: 'Pengingat',
                            value: todo?.remindAt,
                            isReminder: true,
                            onPick: () => _pickReminder(todo?.remindAt),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Ds.s6),
                  Divider(color: dae.hairline.withValues(alpha: 0.28)),
                  const SizedBox(height: Ds.s4),
                  LinkedItemsSection(type: DaeItemType.todo, uuid: widget.uuid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoHeader extends StatelessWidget {
  const _TodoHeader({
    required this.done,
    required this.canEdit,
    required this.onToggle,
    required this.onShare,
  });

  final bool done;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Ds.s2, Ds.s1, Ds.s3, Ds.s1),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Kembali',
            icon: Icon(Icons.arrow_back, color: dae.onSurface),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(child: DsEyebrow('Tugas')),
          IconButton(
            tooltip: 'Kolaborator',
            icon: Icon(Icons.person_add_alt_1, color: dae.onSurfaceSecondary),
            onPressed: onShare,
          ),
          DsButton.ghost(
            label: done ? 'Buka lagi' : 'Tandai selesai',
            onPressed: canEdit ? onToggle : null,
          ),
          DsCheckToggle(done: done, onTap: canEdit ? onToggle : null, size: 24),
        ],
      ),
    );
  }
}

class _DateActionRow extends StatelessWidget {
  const _DateActionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onPick,
    this.isReminder = false,
  });

  final IconData icon;
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final bool isReminder;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final text = value == null
        ? 'atur $label'
        : (isReminder
              ? '${DsTime.dueLabel(value!)} · ${DsTime.clock(value!)}'
              : DsTime.dueLabel(value!));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPick,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ds.radiusSm),
          border: Border.all(color: dae.hairline.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Ds.s3,
            vertical: Ds.s2,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: dae.onSurfaceSecondary),
              const SizedBox(width: Ds.s3),
              DsEyebrow(label),
              const Spacer(),
              DsText.caption(text),
            ],
          ),
        ),
      ),
    );
  }
}
