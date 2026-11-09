import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/providers.dart';
import 'dae_item.dart';
import 'widgets/dae_widgets.dart';

enum _ItemAction { archive, restore, delete }

Future<void> showDaeItemActions({
  required BuildContext context,
  required WidgetRef ref,
  required DaeItem item,
}) async {
  final notes = ref.read(notesRepositoryProvider);
  final todos = ref.read(todosRepositoryProvider);
  final userId = ref.read(authControllerProvider).asData?.value?.userId;
  final canDelete = item.ownerUserId == null || item.ownerUserId == userId;
  final canEdit = item.canEdit;
  final archived = item.archivedAt != null;
  final action = await showDsSheet<_ItemAction>(
    context,
    isScrollControlled: false,
    builder: (sheetContext) => _ItemActionsSheet(
      item: item,
      archived: archived,
      canDelete: canDelete,
      canEdit: canEdit,
    ),
  );
  if (!context.mounted || action == null) return;

  if (action == _ItemAction.delete) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus item?'),
        content: Text(
          '“${item.displayTitle}” akan dihapus dari perangkat dan disinkronkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (item.type == DaeItemType.note) {
      await notes.delete(item.uuid);
    } else {
      await todos.delete(item.uuid);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Item dihapus')));
    }
    return;
  }

  if (action == _ItemAction.archive) {
    if (item.type == DaeItemType.note) {
      await notes.archive(item.uuid);
    } else {
      await todos.archive(item.uuid);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Item dipindahkan ke Arsip'),
        action: SnackBarAction(
          label: 'BATAL',
          onPressed: () {
            if (item.type == DaeItemType.note) {
              notes.restore(item.uuid);
            } else {
              todos.restore(item.uuid);
            }
          },
        ),
      ),
    );
  } else {
    if (item.type == DaeItemType.note) {
      await notes.restore(item.uuid);
    } else {
      await todos.restore(item.uuid);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item dipulihkan ke Beranda')),
      );
    }
  }
}

class _ItemActionsSheet extends StatelessWidget {
  const _ItemActionsSheet({
    required this.item,
    required this.archived,
    required this.canDelete,
    required this.canEdit,
  });

  final DaeItem item;
  final bool archived;
  final bool canDelete;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final noun = item.type == DaeItemType.note ? 'Catatan' : 'Tugas';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s4, Ds.s4, Ds.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DsSectionHeader(
              text: 'Tindakan $noun',
              trailing: IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            const SizedBox(height: Ds.s1),
            DsText.caption(item.displayTitle),
            const SizedBox(height: Ds.s3),
            if (!canDelete)
              DsText.caption(
                canEdit ? 'Item dibagikan oleh pemilik.' : 'Akses hanya lihat.',
              ),
            if (canEdit)
              ListTile(
                leading: Icon(
                  archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  color: dae.onSurface,
                ),
                title: Text(archived ? 'Pulihkan ke Beranda' : 'Arsipkan'),
                onTap: () => Navigator.pop(
                  context,
                  archived ? _ItemAction.restore : _ItemAction.archive,
                ),
              ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline, color: dae.onSurface),
                title: const Text('Hapus'),
                onTap: () => Navigator.pop(context, _ItemAction.delete),
              ),
          ],
        ),
      ),
    );
  }
}
