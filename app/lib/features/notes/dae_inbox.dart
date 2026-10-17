import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/ds.dart';
import '../../data/providers.dart';
import '../todos/todo_editor.dart';
import 'dae_item.dart';
import 'dae_providers.dart';
import 'note_editor.dart';
import 'widgets/dae_widgets.dart';

/// The app's spine: notes and todos together in one list, each row carrying a
/// [ThreadRail] in its connection colour — an isolated item is visibly colour-
/// less. Reads only local drift streams, so it renders instantly with zero
/// network.
class DaeInboxScreen extends ConsumerStatefulWidget {
  const DaeInboxScreen({super.key});

  @override
  ConsumerState<DaeInboxScreen> createState() => _DaeInboxScreenState();
}

class _DaeInboxScreenState extends ConsumerState<DaeInboxScreen> {
  static const _filters = ['Semua', 'Catatan', 'Tugas'];
  int _filter = 0;
  String _query = '';

  bool _matches(DaeItem item) {
    if (_query.trim().isEmpty) return true;
    final n = _query.trim().toLowerCase();
    return item.displayTitle.toLowerCase().contains(n) ||
        item.excerpt.toLowerCase().contains(n);
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final notesAsync = ref.watch(notesListProvider);
    final todosAsync = ref.watch(todosListProvider);

    if (notesAsync.hasError || todosAsync.hasError) {
      return Scaffold(
        backgroundColor: dae.background,
        body: const SingleChildScrollView(child: _InboxError()),
      );
    }

    final notes = [
      for (final n in (notesAsync.value ?? const [])) DaeItem.fromNote(n),
    ];
    final todos = [
      for (final t in (todosAsync.value ?? const [])) DaeItem.fromTodo(t),
    ];

    final showNotes = _filter != 1;
    final showTodos = _filter != 2;
    final noteRows = notes.where(_matches).toList();
    final todoRows = todos.where(_matches).toList();
    final nothingAtAll = notes.isEmpty && todos.isEmpty;

    return Scaffold(
      backgroundColor: dae.background,
      body: Column(
        children: [
          _InboxToolbar(
            filters: _filters,
            currentIndex: _filter,
            onFilter: (i) => setState(() => _filter = i),
            onQuery: (v) => setState(() => _query = v),
            noteCount: notes.length,
            todoCount: todos.length,
          ),
          _CaptureBar(onNote: _captureNote, onTodo: _captureTodo),
          Expanded(
            child: nothingAtAll
                ? const SingleChildScrollView(child: _FirstRunInvitation())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Ds.s4,
                      Ds.s2,
                      Ds.s4,
                      Ds.s8,
                    ),
                    children: [
                      if (showNotes) ..._section('Catatan', noteRows),
                      if (showNotes && showTodos && noteRows.isNotEmpty)
                        const SizedBox(height: Ds.s4),
                      if (showTodos) ..._section('Tugas', todoRows),
                      if (_query.isNotEmpty &&
                          noteRows.isEmpty &&
                          todoRows.isEmpty)
                        _NoMatches(query: _query),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(String label, List<DaeItem> items) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Ds.s2),
          child: DsEyebrow(label),
        ),
        _SectionEmpty(label: label),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Ds.s2),
        child: DsEyebrow('$label · ${items.length}'),
      ),
      const SizedBox(height: Ds.s2),
      for (var i = 0; i < items.length; i++)
        DsEnter(
          index: i,
          travel: 10,
          duration: DsMotion.panel,
          child: Padding(
            key: ValueKey('row-${items[i].uuid}'),
            padding: const EdgeInsets.only(bottom: Ds.s2),
            child: _SpineRow(item: items[i]),
          ),
        ),
    ];
  }

  void _captureNote() => NoteEditorSheet.show(context);

  void _captureTodo() => TodoEditorSheet.show(context);
}

class _InboxToolbar extends StatefulWidget {
  const _InboxToolbar({
    required this.filters,
    required this.currentIndex,
    required this.onFilter,
    required this.onQuery,
    required this.noteCount,
    required this.todoCount,
  });

  final List<String> filters;
  final int currentIndex;
  final ValueChanged<int> onFilter;
  final ValueChanged<String> onQuery;
  final int noteCount;
  final int todoCount;

  @override
  State<_InboxToolbar> createState() => _InboxToolbarState();
}

class _InboxToolbarState extends State<_InboxToolbar> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s3, Ds.s4, Ds.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.only(bottom: Ds.s3),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: widget.onQuery,
                decoration: const InputDecoration(
                  hintText: 'cari di perangkat…',
                  isDense: true,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(child: DsText.displaySm('Beranda')),
                DsText.caption('${widget.noteCount + widget.todoCount} item'),
                IconButton(
                  tooltip: 'Cari',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.search, color: dae.onSurfaceSecondary),
                  onPressed: () => setState(() => _searching = true),
                ),
              ],
            ),
          DsFilterControl(
            options: widget.filters,
            currentIndex: widget.currentIndex,
            onChanged: (i) {
              widget.onFilter(i);
              if (!_searching) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

/// Always-reachable capture affordance — a note or a todo, without leaving the
/// list (this is not a Material FAB; it is a hairline row of ghost actions).
class _CaptureBar extends StatelessWidget {
  const _CaptureBar({required this.onNote, required this.onTodo});

  final VoidCallback onNote;
  final VoidCallback onTodo;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s1, Ds.s4, Ds.s3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dae.hairline.withValues(alpha: 0.28)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Ds.s3),
          child: Row(
            children: [
              Expanded(
                child: _CaptureButton(
                  label: 'Catatan',
                  icon: Icons.edit_outlined,
                  accent: DaeTypeMarks.noteColor,
                  onTap: onNote,
                ),
              ),
              const SizedBox(width: Ds.s2),
              Expanded(
                child: _CaptureButton(
                  label: 'Tugas',
                  icon: Icons.check_circle_outline,
                  accent: DaeTypeMarks.todoColor,
                  onTap: onTodo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ds.radiusSm),
          border: Border.all(color: dae.hairline.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Ds.s3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: Ds.s2),
              DsEyebrow('+ $label'),
            ],
          ),
        ),
      ),
    );
  }
}

/// One spine row. Watches its own thread so the rail repaints the moment a
/// link lands — the colour IS the signal that the item is connected.
class _SpineRow extends ConsumerWidget {
  const _SpineRow({required this.item});

  final DaeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(threadForProvider(item.ref)).value;

    return DsCard(
      thread: thread,
      // The rail draws itself down the spine the moment a link lands, so the
      // colour is earned on screen rather than just appearing.
      drawOn: true,
      onTap: () => context.push(
        item.type == DaeItemType.note
            ? DaeRouteNames.notePath(item.uuid)
            : DaeRouteNames.todoPath(item.uuid),
      ),
      child: item.type == DaeItemType.note
          ? _NoteRowBody(item: item)
          : _TodoRowBody(item: item),
    );
  }
}

class _NoteRowBody extends StatelessWidget {
  const _NoteRowBody({required this.item});

  final DaeItem item;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: Ds.s2),
                      child: Icon(
                        Icons.push_pin,
                        size: 13,
                        color: dae.onSurfaceSecondary,
                      ),
                    ),
                  Expanded(
                    child: DsText.bodyStrong(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (item.excerpt.isNotEmpty &&
                  item.excerpt != item.displayTitle) ...[
                const SizedBox(height: Ds.s1),
                DsText.body(
                  item.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Ds.s3),
        DsText.timestamp(DsTime.relative(item.updatedAt)),
      ],
    );
  }
}

class _TodoRowBody extends ConsumerWidget {
  const _TodoRowBody({required this.item});

  final DaeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dae = context.dae;
    final titleColor = item.done ? dae.onSurfaceSecondary : dae.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DsCheckToggle(
          done: item.done,
          onTap: () => ref
              .read(todosRepositoryProvider)
              .toggle(item.uuid), // optimistic local write
        ),
        const SizedBox(width: Ds.s3),
        Expanded(
          child: Text(
            item.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DsType.body(weight: FontWeight.w600, color: titleColor),
          ),
        ),
        const SizedBox(width: Ds.s3),
        if (item.dueAt != null)
          DsText.timestamp(DsTime.dueLabel(item.dueAt!))
        else
          DsText.timestamp(DsTime.relative(item.updatedAt)),
      ],
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final isNotes = label == 'Catatan';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Ds.s3),
      child: Text(
        isNotes
            ? 'Belum ada catatan di sini. Tangkap satu — ide tidak boleh '
                  'menghilang hanya karena belum sempat ditulis.'
            : 'Belum ada tugas yang menunggu. Tambahkan satu dan benangnya '
                  'mulai terbentuk di daftar ini.',
        style: DsType.body(color: dae.onSurfaceSecondary),
      ),
    );
  }
}

class _FirstRunInvitation extends StatelessWidget {
  const _FirstRunInvitation();

  @override
  Widget build(BuildContext context) {
    return const DsInvitation(
      eyebrow: 'Beranda',
      headline: 'belum ada yang ditautkan — belum ada apa pun',
      hint:
          'Tekan CATATAN atau TUGAS di atas untuk menangkap yang pertama. '
          'Semuanya tersimpan di perangkat ini, tanpa perlu internet. Begitu '
          'dua item tersambung, benang warnanya langsung muncul.',
    );
  }
}

class _InboxError extends StatelessWidget {
  const _InboxError();

  @override
  Widget build(BuildContext context) {
    return const DsInvitation(
      eyebrow: 'Perangkat',
      headline: 'data lokal sedang bermasalah',
      hint:
          'Tulisan terakhir tetap tersimpan di perangkat ini. Tutup lalu buka '
          'lagi — sinkronisasi akan menyambung sendiri saat jaringan kembali.',
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return DsInvitation(
      eyebrow: 'Pencarian',
      headline: 'tidak ada yang cocok',
      hint:
          'Kata "$query" belum menyentuh catatan atau tugas apa pun di '
          'perangkat ini. Coba kata lain, atau tangkap item baru.',
    );
  }
}
