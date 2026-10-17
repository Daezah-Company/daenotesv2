import 'package:daenotes/core/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reminders_controller.dart';

/// The scheduling surface a todo hands to the reminders feature. Callable from
/// anywhere (the todo editor is owned by the NOTES agent):
///
/// ```dart
/// await ReminderSheet.present(
///   context,
///   todoUuid: todo.uuid,
///   initial: todo.remindAt ?? todo.dueAt ?? DateTime.now().add(const Duration(hours: 1)),
///   title: todo.title,
/// );
/// ```
///
/// It writes through [ReminderActions] → `RemindersRepository.schedule` +
/// `TodosRepository.update(remindAt:)`, so it queues to the sync outbox like
/// every other write and never touches HTTP directly (contract §6). Times are
/// **local wall-clock**; a `18:00` picked here stays `18:00` across DST.
///
/// Returns the new reminder uuid, or `null` if the user dismissed without
/// scheduling.
class ReminderSheet extends ConsumerStatefulWidget {
  const ReminderSheet({
    super.key,
    required this.todoUuid,
    required this.initial,
    this.title = 'Pengingat',
  });

  final String todoUuid;
  final DateTime initial;
  final String title;

  /// Present the sheet as a bottom sheet. Returns the reminder uuid or null.
  static Future<String?> present(
    BuildContext context, {
    required String todoUuid,
    required DateTime initial,
    String title = 'Pengingat',
  }) {
    return showDsSheet<String>(
      context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReminderSheet(todoUuid: todoUuid, initial: initial, title: title),
    );
  }

  @override
  ConsumerState<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends ConsumerState<ReminderSheet> {
  late DateTime _when = _floorToMinute(widget.initial);

  static DateTime _floorToMinute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  Future<void> _apply(SnoozeShortcut shortcut) async {
    setState(() => _when = _floorToMinute(shortcut.resolve(_now)));
  }

  DateTime get _now => DateTime.now();

  Future<void> _save() async {
    final uuid = await ref
        .read(reminderActionsProvider)
        .scheduleForTodo(
          todoUuid: widget.todoUuid,
          title: widget.title,
          when: _when,
        );
    if (mounted) Navigator.of(context).pop(uuid);
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dae.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Ds.radiusLg),
          ),
          border: Border(
            top: BorderSide(color: dae.hairline.withValues(alpha: 0.28)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Ds.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DsEyebrow('Pengingat baru', accent: Ds.threadRose),
                const SizedBox(height: Ds.s3),
                DsText.body(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Ds.s4),
                // Wall-clock readout — mono, the sanctioned utility face.
                AnimatedSwitcher(
                  duration: DsMotion.standard,
                  switchInCurve: DsMotion.enter,
                  switchOutCurve: DsMotion.exit,
                  child: Row(
                    key: ValueKey(_when),
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      DsText.section(_dayWord(_when)),
                      const SizedBox(width: Ds.s3),
                      DsText.timestamp(DsTime.clock(_when)),
                    ],
                  ),
                ),
                const SizedBox(height: Ds.s4),
                Wrap(
                  spacing: Ds.s2,
                  runSpacing: Ds.s2,
                  children: [
                    for (final s in _shortcuts)
                      _ShortcutChip(
                        label: s.label,
                        selected: _floorToMinute(s.resolve(_now)) == _when,
                        onTap: () => _apply(s),
                      ),
                  ],
                ),
                const SizedBox(height: Ds.s4),
                Row(
                  children: [
                    _NudgeButton(
                      label: '−1 jam',
                      onTap: () => setState(
                        () => _when = _when.subtract(const Duration(hours: 1)),
                      ),
                    ),
                    const SizedBox(width: Ds.s2),
                    _NudgeButton(
                      label: '+1 jam',
                      onTap: () => setState(
                        () => _when = _when.add(const Duration(hours: 1)),
                      ),
                    ),
                    const SizedBox(width: Ds.s2),
                    _NudgeButton(
                      label: '+1 hari',
                      onTap: () => setState(
                        () => _when = _when.add(const Duration(days: 1)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Ds.s4),
                Row(
                  children: [
                    Expanded(
                      child: DsButton.ghost(
                        label: 'Batal',
                        onPressed: () => Navigator.of(context).pop(),
                        expanded: true,
                      ),
                    ),
                    const SizedBox(width: Ds.s2),
                    Expanded(
                      child: DsButton.filled(
                        label: 'Simpan',
                        onPressed: _when.isAfter(_now) ? _save : null,
                        expanded: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _dayWord(DateTime d) {
    final today = DateTime(d.year, d.month, d.day);
    final now = DateTime.now();
    final n = DateTime(now.year, now.month, now.day);
    final days = today.difference(n).inDays;
    if (days == 0) return 'Hari ini';
    if (days == 1) return 'Besok';
    return '${d.day}/${d.month}';
  }

  static final List<SnoozeShortcut> _shortcuts = [
    SnoozeShortcut(
      label: '1 jam lagi',
      resolver: (now) => now.add(const Duration(hours: 1)),
    ),
    SnoozeShortcut(
      label: 'Nanti malam',
      resolver: (now) {
        final tonight = DateTime(now.year, now.month, now.day, 20, 0);
        return tonight.isAfter(now)
            ? tonight
            : tonight.add(const Duration(days: 1));
      },
    ),
    SnoozeShortcut(
      label: 'Besok pagi',
      resolver: (now) => DateTime(
        now.year,
        now.month,
        now.day,
        7,
        0,
      ).add(const Duration(days: 1)),
    ),
  ];
}

/// A named wall-clock shortcut that recomputes from a passed `now`.
class SnoozeShortcut {
  const SnoozeShortcut({required this.label, required this.resolver});

  final String label;
  final SnoozeDateTime resolver;

  DateTime resolve(DateTime now) => resolver(now);
}

typedef SnoozeDateTime = DateTime Function(DateTime now);

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final border = selected
        ? Ds.threadRose
        : dae.hairline.withValues(alpha: 0.4);
    return DsPressable(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: DsMotion.standard,
          curve: DsMotion.onScreen,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ds.radiusSm),
            border: Border.all(
              color: border,
              width: selected ? 1.5 : Ds.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Ds.s3,
              vertical: Ds.s2,
            ),
            child: DsText.caption(label),
          ),
        ),
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DsButton(label: label, onPressed: onTap, expanded: true),
    );
  }
}
