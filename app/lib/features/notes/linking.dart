import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import 'dae_item.dart';
import 'dae_providers.dart';
import 'widgets/dae_widgets.dart';

/// Opens the offline link picker for [from].
Future<void> showDaeLinkPicker(BuildContext context, DaeItemRef from) {
  return showDsSheet<void>(
    context,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: LinkPickerSheet(from: from),
    ),
  );
}

/// Live connections of one item, rendered as a stack of thread-railed rows.
/// Empty state is an invitation, not a shrug.
class LinkedItemsSection extends ConsumerWidget {
  const LinkedItemsSection({super.key, required this.type, required this.uuid});

  final DaeItemType type;
  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dae = context.dae;
    final self = DaeItemRef(type, uuid);
    final links = ref.watch(linksForProvider(self)).value ?? const [];
    final index = ref.watch(itemIndexProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsSectionHeader(
          text: 'Tautan',
          trailing: links.isEmpty
              ? null
              : DsButton.ghost(
                  label: 'Taut lagi',
                  onPressed: () => showDaeLinkPicker(context, self),
                ),
        ),
        const SizedBox(height: Ds.s3),
        if (links.isEmpty)
          DsInvitation(
            eyebrow: 'Benang',
            headline: 'belum ada yang ditautkan',
            hint:
                'Sambungkan ke catatan atau tugas lain. Begitu tersambung, '
                'warnanya langsung muncul di daftar dan di graph.',
            action: DsButton.filled(
              label: 'Tautkan item',
              icon: Icons.add,
              onPressed: () => showDaeLinkPicker(context, self),
            ),
          )
        else
          for (var i = 0; i < links.length; i++)
            DsEnter(
              index: i,
              travel: 8,
              duration: DsMotion.panel,
              child: _NeighborRow(
                link: links[i],
                from: self,
                neighbor: index[daeOtherEndpoint(type, uuid, links[i]).uuid],
                onUnlink: () =>
                    ref.read(linksRepositoryProvider).unlink(links[i].uuid),
                hairline: dae.hairline,
              ),
            ),
      ],
    );
  }
}

class _NeighborRow extends StatelessWidget {
  const _NeighborRow({
    required this.link,
    required this.from,
    required this.neighbor,
    required this.onUnlink,
    required this.hairline,
  });

  final Link link;
  final DaeItemRef from;
  final DaeItem? neighbor;
  final VoidCallback onUnlink;
  final Color hairline;

  @override
  Widget build(BuildContext context) {
    final other = daeOtherEndpoint(from.type, from.uuid, link);
    final thread = Ds.threadColor(from.type, other.type);
    final title = neighbor?.displayTitle ?? 'Item tersimpan';

    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ds.radius),
          border: Border.all(color: hairline.withValues(alpha: 0.28)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Ds.radius),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ThreadRail(thread: thread),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Ds.s3,
                      vertical: Ds.s2,
                    ),
                    child: Row(
                      children: [
                        DsTypeMark(other.type),
                        const SizedBox(width: Ds.s3),
                        Expanded(
                          child: DsText.body(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Putus tautan',
                          icon: Icon(
                            Icons.link_off,
                            size: 18,
                            color: context.dae.onSurface,
                          ),
                          onPressed: onUnlink,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fully offline connect/disconnect surface: searches every local item, offers
/// only connectable ones (never self, never an already-linked pair — the
/// server's UNIQUE rule mirrored here so a tap can't queue a doomed write), and
/// reports what LinksRepository did.
class LinkPickerSheet extends ConsumerStatefulWidget {
  const LinkPickerSheet({super.key, required this.from});

  final DaeItemRef from;

  @override
  ConsumerState<LinkPickerSheet> createState() => _LinkPickerSheetState();
}

class _LinkPickerSheetState extends ConsumerState<LinkPickerSheet> {
  final _search = TextEditingController();
  String _query = '';
  String? _flash;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _connect(DaeItem item) async {
    final repo = ref.read(linksRepositoryProvider);
    // LinksRepository.link dedupes an existing pair and returns the live link
    // uuid; the candidate then drops out of the list as the thread stream
    // updates, so a second tap can never create a duplicate edge.
    await repo.link(
      sourceType: widget.from.type,
      sourceUuid: widget.from.uuid,
      targetType: item.type,
      targetUuid: item.uuid,
    );
    if (!mounted) return;
    setState(() => _flash = 'tertaut: ${item.displayTitle}');
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(
      linkCandidatesProvider(DaePickerArgs(from: widget.from, query: _query)),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s4, Ds.s4, Ds.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DsSectionHeader(
                text: 'Tautkan ke',
                trailing: DsButton.ghost(
                  label: 'Selesai',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: Ds.s3),
              TextField(
                controller: _search,
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'cari catatan atau tugas…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
              // The confirmation opens the layout instead of snapping it, so
              // the list below slides rather than jumps.
              AnimatedSize(
                duration: DsMotion.panel,
                curve: DsMotion.enter,
                alignment: Alignment.topCenter,
                child: _flash == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: Ds.s3),
                        child: DsText.caption(_flash!),
                      ),
              ),
              if (_flash == null) const SizedBox(height: Ds.s3),
              Expanded(
                child: candidates.isEmpty
                    ? DsInvitation(
                        eyebrow: 'Pencarian',
                        headline: 'tidak ada yang cocok',
                        hint: _query.trim().isEmpty
                            ? 'Semua item lain sudah tertaut di sini. '
                                  'Tangkap item baru dulu untuk memperluas '
                                  'benangnya.'
                            : 'Coba kata lain, atau buat item baru — semua '
                                  'sudah tersimpan di perangkat, tanpa jaringan.',
                      )
                    : ListView.separated(
                        itemCount: candidates.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Ds.s2),
                        itemBuilder: (context, i) {
                          final item = candidates[i];
                          final thread = Ds.threadColor(
                            widget.from.type,
                            item.type,
                          );
                          return DsCard(
                            thread: thread,
                            onTap: () => _connect(item),
                            child: Row(
                              children: [
                                DsTypeMark(item.type),
                                const SizedBox(width: Ds.s3),
                                Expanded(
                                  child: DsText.body(
                                    item.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DsText.timestamp(
                                  DsTime.relative(item.updatedAt),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
