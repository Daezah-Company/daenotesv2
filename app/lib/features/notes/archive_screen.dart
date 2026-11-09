import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/ds.dart';
import '../../data/providers.dart';
import 'dae_item.dart';
import 'dae_item_actions.dart';
import 'dae_providers.dart';

class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dae = context.dae;
    final notes = ref.watch(archivedNotesProvider);
    final todos = ref.watch(archivedTodosProvider);

    if (notes.hasError || todos.hasError) {
      return Scaffold(
        backgroundColor: dae.background,
        appBar: _ArchiveAppBar(onBack: () => context.pop()),
        body: Center(child: DsText.body('Arsip tidak dapat dimuat.')),
      );
    }

    final items =
        <DaeItem>[
          for (final note in notes.value ?? const []) DaeItem.fromNote(note),
          for (final todo in todos.value ?? const []) DaeItem.fromTodo(todo),
        ]..sort(
          (a, b) => (b.archivedAt ?? b.updatedAt).compareTo(
            a.archivedAt ?? a.updatedAt,
          ),
        );

    return Scaffold(
      backgroundColor: dae.background,
      appBar: _ArchiveAppBar(onBack: () => context.pop()),
      body: notes.isLoading && todos.isLoading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const _ArchiveEmpty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s3, Ds.s4, Ds.s8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: Ds.s2),
              itemBuilder: (context, index) =>
                  _ArchivedItemCard(item: items[index]),
            ),
    );
  }
}

class _ArchiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ArchiveAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return AppBar(
      leading: IconButton(
        tooltip: 'Kembali',
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
      ),
      title: DsText.displaySm('Arsip'),
      backgroundColor: dae.background,
      surfaceTintColor: Colors.transparent,
    );
  }
}

class _ArchiveEmpty extends StatelessWidget {
  const _ArchiveEmpty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Ds.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.archive_outlined, size: 34, color: context.dae.onSurface),
          const SizedBox(height: Ds.s3),
          DsText.displaySm('Arsip masih kosong'),
          const SizedBox(height: Ds.s2),
          DsText.body(
            'Catatan dan tugas yang diarsipkan akan muncul di sini. Buka menu item, lalu pilih Pulihkan untuk mengembalikannya ke Beranda.',
            align: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ArchivedItemCard extends ConsumerWidget {
  const _ArchivedItemCard({required this.item});

  final DaeItem item;

  void _open(BuildContext context) {
    context.push(
      item.type == DaeItemType.note
          ? DaeRouteNames.notePath(item.uuid)
          : DaeRouteNames.todoPath(item.uuid),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dae = context.dae;
    final isNote = item.type == DaeItemType.note;
    return DsCard(
      onTap: () => _open(context),
      onLongPress: () =>
          showDaeItemActions(context: context, ref: ref, item: item),
      child: Row(
        children: [
          Icon(
            isNote ? Icons.sticky_note_2_outlined : Icons.check_circle_outline,
            size: 19,
            color: dae.onSurfaceSecondary,
          ),
          const SizedBox(width: Ds.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DsText.bodyStrong(
                  item.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.excerpt.isNotEmpty &&
                    item.excerpt != item.displayTitle) ...[
                  const SizedBox(height: Ds.s1),
                  DsText.body(
                    item.excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: Ds.s1),
                DsText.caption(
                  isNote ? 'CATATAN · DIARSIPKAN' : 'TUGAS · DIARSIPKAN',
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Pulihkan ke Beranda',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.unarchive_outlined),
            onPressed: () async {
              if (isNote) {
                await ref.read(notesRepositoryProvider).restore(item.uuid);
              } else {
                await ref.read(todosRepositoryProvider).restore(item.uuid);
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Item dipulihkan ke Beranda')),
              );
            },
          ),
          IconButton(
            tooltip: 'Tindakan lainnya',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.more_horiz),
            onPressed: () =>
                showDaeItemActions(context: context, ref: ref, item: item),
          ),
        ],
      ),
    );
  }
}
