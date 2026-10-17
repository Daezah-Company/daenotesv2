import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/providers.dart';
import 'dae_item.dart';

/// Feature-local providers. They read only through the composition root
/// (`data/providers.dart`) — the UI never touches drift or the HTTP client.

/// Active notes, pinned first then by recency (drift stream, local-first).
final notesListProvider = StreamProvider<List<Note>>(
  (ref) => ref.watch(notesRepositoryProvider).watchNotes(),
);

/// Active todos, undone first then by recency.
final todosListProvider = StreamProvider<List<Todo>>(
  (ref) => ref.watch(todosRepositoryProvider).watchTodos(),
);

/// The thread colour carried by an item's spine rail: its first live
/// connection, or null when isolated. Drives the inbox incentive.
final threadForProvider = StreamProvider.family<Color?, DaeItemRef>(
  (ref, key) =>
      ref.watch(linksRepositoryProvider).watchThreadFor(key.type, key.uuid),
);

/// All live links touching an item (either direction).
final linksForProvider = StreamProvider.family<List<Link>, DaeItemRef>(
  (ref, key) =>
      ref.watch(linksRepositoryProvider).watchLinksFor(key.type, key.uuid),
);

final noteByUuidProvider = StreamProvider.family<Note?, String>(
  (ref, uuid) => ref.watch(notesRepositoryProvider).watchNote(uuid),
);

final todoByUuidProvider = StreamProvider.family<Todo?, String>(
  (ref, uuid) => ref.watch(todosRepositoryProvider).watchTodo(uuid),
);

/// Every active item as a flat [DaeItem], for the link picker search and for
/// resolving neighbour titles. Fully offline — reads the two local streams.
final allItemsProvider = Provider<List<DaeItem>>((ref) {
  final notes = ref.watch(notesListProvider).value ?? const <Note>[];
  final todos = ref.watch(todosListProvider).value ?? const <Todo>[];
  return [
    for (final n in notes) DaeItem.fromNote(n),
    for (final t in todos) DaeItem.fromTodo(t),
  ];
});

/// uuid -> item lookup so a link's other endpoint can be titled without an
/// extra query.
final itemIndexProvider = Provider<Map<String, DaeItem>>(
  (ref) => {for (final i in ref.watch(allItemsProvider)) i.uuid: i},
);

/// Candidates for the link picker from [from]: matches [query], excludes the
/// item itself (server rule: no self-links, enforced client-side too) and
/// anything already connected (no duplicate pairs).
final linkCandidatesProvider = Provider.family<List<DaeItem>, DaePickerArgs>((
  ref,
  args,
) {
  final from = args.from;
  final linked = ref.watch(linksForProvider(from));
  final linkedIds = <String>{};
  for (final l in (linked.value ?? const <Link>[])) {
    linkedIds.add(daeOtherEndpoint(from.type, from.uuid, l).uuid);
  }
  final needle = args.query.trim().toLowerCase();
  final all = ref.watch(allItemsProvider);
  final out = <DaeItem>[];
  for (final item in all) {
    if (item.type == from.type && item.uuid == from.uuid) continue;
    if (linkedIds.contains(item.uuid)) continue;
    if (needle.isNotEmpty &&
        !item.displayTitle.toLowerCase().contains(needle) &&
        !item.excerpt.toLowerCase().contains(needle)) {
      continue;
    }
    out.add(item);
  }
  return out;
});

/// Immutable args for [linkCandidatesProvider]; equality keeps Riverpod's
/// family cache stable across rebuilds while the query text is unchanged.
@immutable
class DaePickerArgs {
  const DaePickerArgs({required this.from, required this.query});
  final DaeItemRef from;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is DaePickerArgs && other.from == from && other.query == query;

  @override
  int get hashCode => Object.hash(from, query);
}
