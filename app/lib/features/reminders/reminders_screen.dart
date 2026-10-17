import 'package:daenotes/core/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reminder_grouping.dart';
import 'reminders_controller.dart';
import 'reminders_providers.dart';

/// The reminders route body (`DaeRouteNames.reminders`). Live from the drift
/// watch stream, grouped by wall-clock time into Hari ini / Besok / Nanti /
/// Tertunda, each row carrying its target item and due context. Renders fully
/// offline; every action writes through the repositories.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  @override
  void initState() {
    super.initState();
    // On first appearance, pull the platform schedule back in line with the
    // local rows (idempotent). The main agent also calls this on app resume;
    // see docs/HANDOFF.md §REMINDERS.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reminderActionsProvider).reconcile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final upcoming = ref.watch(upcomingRemindersProvider);

    return Scaffold(
      backgroundColor: dae.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DsEyebrow('Pengingat'),
            const SizedBox(width: Ds.s2),
            if (upcoming.value?.isNotEmpty ?? false)
              DsText.timestamp(
                '${upcoming.value!.length}',
                key: const ValueKey('reminder_count'),
              ),
          ],
        ),
      ),
      body: upcoming.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Ds.s5),
            child: DsText.body(
              'Gagal memuat pengingat. $e',
              align: TextAlign.center,
            ),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) return const _EmptyInvitation();
          return _GroupedList(rows: rows);
        },
      ),
    );
  }
}

/// Grouped, sectioned list. Rows arrive pre-sorted by bucket rank then time, so
/// a single pass emits each section header when the bucket changes.
class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.rows});

  final List<UpcomingReminder> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <Widget>[];
    ReminderBucket? current;
    for (final row in rows) {
      if (row.bucket != current) {
        current = row.bucket;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s5, Ds.s4, Ds.s2),
            child: DsEyebrow(
              bucketLabel(row.bucket),
              // Tertunda reads as a status (rose); the rest stay bichrome.
              accent: row.bucket == ReminderBucket.tertunda
                  ? Ds.threadRose
                  : null,
            ),
          ),
        );
      }
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Ds.s4,
            vertical: Ds.s1,
          ),
          child: _ReminderRow(row: row),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: Ds.s6),
      children: items,
    );
  }
}

class _ReminderRow extends ConsumerWidget {
  const _ReminderRow({required this.row});

  final UpcomingReminder row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row.reminder;
    final overdue = row.bucket == ReminderBucket.tertunda;

    return DsCard(
      // Rose thread = reminder-bearing item (contract §5).
      thread: Ds.threadRose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DsText.bodyStrong(
                      row.targetTitle ?? r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Ds.s1),
                    if (row.dueContext != null) ...[
                      DsText.caption(row.dueContext!),
                      const SizedBox(height: Ds.s1),
                    ],
                    Row(
                      children: [
                        DsText.timestamp(overdue ? 'terlewat' : 'dentang'),
                        const SizedBox(width: Ds.s2),
                        DsText.timestamp(DsTime.clock(r.scheduledAt)),
                        const SizedBox(width: Ds.s2),
                        Flexible(
                          child: DsText.timestamp(
                            '· ${DsTime.relative(r.scheduledAt)}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Ds.s2),
              DsTypeMark(r.itemType),
            ],
          ),
          const SizedBox(height: Ds.s3),
          Row(
            children: [
              Expanded(
                child: DsButton.ghost(
                  label: 'Tunda',
                  onPressed: () => _openSnooze(context, ref),
                ),
              ),
              const SizedBox(width: Ds.s2),
              Expanded(
                child: DsButton.ghost(
                  label: 'Selesai',
                  onPressed: () => _markDone(context, ref, r.uuid),
                ),
              ),
              const SizedBox(width: Ds.s2),
              DsButton.destructive(
                label: 'Batal',
                onPressed: () => _cancel(context, ref, r.uuid),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _markDone(
    BuildContext context,
    WidgetRef ref,
    String uuid,
  ) async {
    await ref.read(reminderActionsProvider).markDone(uuid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: context.dae.elevated,
        content: DsText.caption('Ditandai selesai'),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, String uuid) async {
    final actions = ref.read(reminderActionsProvider);
    await actions.cancelReminder(uuid);
    if (!context.mounted) return;
    final dae = context.dae;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: dae.elevated,
        duration: const Duration(seconds: 4),
        content: DsText.caption('Pengingat dibatalkan'),
        action: SnackBarAction(
          label: 'URUNGKAN',
          textColor: Ds.threadRose,
          onPressed: () => actions.undoCancel(),
        ),
      ),
    );
  }

  Future<void> _openSnooze(BuildContext context, WidgetRef ref) async {
    final r = row.reminder;
    final step = await showModalBottomSheet<SnoozeStep>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SnoozeSheet(),
    );
    if (step == null) return;
    await ref.read(reminderActionsProvider).snooze(r.uuid, step);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.dae.elevated,
          content: DsText.caption('Ditunda — ${snoozeStepLabel(step)}'),
        ),
      );
    }
  }
}

class _SnoozeSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dae.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Ds.radiusLg),
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
              const DsEyebrow('Tunda sampai'),
              const SizedBox(height: Ds.s3),
              for (final step in SnoozeStep.values) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: DsText.body(snoozeStepLabel(step)),
                  onTap: () => Navigator.of(context).pop(step),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The empty state is an invitation, not an apology (contract §5 writing):
/// name the fastest path to schedule a first reminder.
class _EmptyInvitation extends StatelessWidget {
  const _EmptyInvitation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Ds.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThreadRail(
              thread: Ds.threadRose,
              width: 4,
              drawOn: !context.reduceMotion,
            ),
            const SizedBox(height: Ds.s4),
            DsText.section('Jadwalkan yang pertama'),
            const SizedBox(height: Ds.s2),
            DsText.body(
              'Buka todo mana pun lalu ketuk Pengingat. Pengingat muncul di sini '
              'tepat saat jatuh tempo, tetap berjalan tanpa jaringan.',
              align: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
