import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/providers.dart';
import 'dae_providers.dart';
import 'dae_save.dart';
import 'linking.dart';
import 'widgets/dae_widgets.dart';

/// Quick-capture note sheet: title + body, autosaved with a debounce. The
/// note row is created lazily on the first keystroke so an abandoned sheet
/// leaves no empty item behind.
class NoteEditorSheet extends ConsumerStatefulWidget {
  const NoteEditorSheet({super.key, this.initialTitle = ''});

  final String initialTitle;

  static Future<void> show(BuildContext context, {String initialTitle = ''}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.dae.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusLg)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: NoteEditorSheet(initialTitle: initialTitle),
      ),
    );
  }

  @override
  ConsumerState<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends ConsumerState<NoteEditorSheet> {
  final _save = DaeDebouncer();
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  final TextEditingController _body = TextEditingController();
  String? _uuid;

  @override
  void dispose() {
    _save.flush();
    _save.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onChange(String _) {
    _save.schedule(_persist);
  }

  Future<void> _persist() async {
    final repo = ref.read(notesRepositoryProvider);
    final title = _title.text;
    final body = _body.text;
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    if (_uuid == null) {
      final created = await repo.create(title: title, body: body);
      if (!mounted) return;
      setState(() => _uuid = created);
    } else {
      await repo.update(_uuid!, title: title, body: body);
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
              text: 'Catatan baru',
              trailing: DsButton.ghost(
                label: 'Selesai',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: Ds.s4),
            _TitleField(controller: _title, onChanged: _onChange),
            const SizedBox(height: Ds.s3),
            _BodyField(controller: _body, onChanged: _onChange),
            const SizedBox(height: Ds.s3),
            DsText.caption(_uuid == null ? 'menyimpan otomatis' : 'tersimpan'),
          ],
        ),
      ),
    );
  }
}

/// Full note detail/editor: autosaves against `update`, exposes pin/archive,
/// and hosts the linking surface — the product's namesake feature.
class NoteDetailScreen extends ConsumerStatefulWidget {
  const NoteDetailScreen({super.key, required this.uuid});

  final String uuid;

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  final _save = DaeDebouncer();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _save.flush();
    _save.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onChange(String _) => _save.schedule(_persist);

  Future<void> _persist() async {
    final repo = ref.read(notesRepositoryProvider);
    await repo.update(widget.uuid, title: _title.text, body: _body.text);
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final note = ref.watch(noteByUuidProvider(widget.uuid)).value;

    if (!_seeded && note != null) {
      _title.text = note.title;
      _body.text = note.body;
      _seeded = true;
    }

    if (note == null && !_seeded) {
      return Scaffold(
        backgroundColor: dae.background,
        body: const Center(child: _LoadingLabel()),
      );
    }

    return Scaffold(
      backgroundColor: dae.background,
      body: SafeArea(
        child: Column(
          children: [
            _DetailHeader(
              eyebrow: 'Catatan',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PinToggle(
                    pinned: note?.pinned ?? false,
                    onToggle: () {
                      final repo = ref.read(notesRepositoryProvider);
                      repo.setPinned(widget.uuid, !(note?.pinned ?? false));
                    },
                  ),
                  if (note != null && note.archivedAt == null)
                    IconButton(
                      tooltip: 'Arsipkan',
                      icon: Icon(
                        Icons.archive_outlined,
                        color: dae.onSurfaceSecondary,
                      ),
                      onPressed: () {
                        ref.read(notesRepositoryProvider).archive(widget.uuid);
                        Navigator.of(context).maybePop();
                      },
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s2, Ds.s4, Ds.s8),
                children: [
                  _TitleField(controller: _title, onChanged: _onChange),
                  const SizedBox(height: Ds.s3),
                  _BodyField(controller: _body, onChanged: _onChange),
                  const SizedBox(height: Ds.s6),
                  Divider(color: dae.hairline.withValues(alpha: 0.28)),
                  const SizedBox(height: Ds.s4),
                  LinkedItemsSection(type: DaeItemType.note, uuid: widget.uuid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared borderless title field used by both the sheet and the detail screen.
class _TitleField extends StatelessWidget {
  const _TitleField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.sentences,
      style: DsType.display(size: Ds.displayM, color: dae.onSurface),
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: 'Judul',
        hintStyle: DsType.display(
          size: Ds.displayM,
          color: dae.onSurfaceSecondary,
        ),
      ),
    );
  }
}

class _BodyField extends StatelessWidget {
  const _BodyField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: 1,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: DsType.body(color: dae.onSurface),
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: 'Tulis sesuatu…',
        hintStyle: DsType.body(color: dae.onSurfaceSecondary),
      ),
    );
  }
}

class _PinToggle extends StatelessWidget {
  const _PinToggle({required this.pinned, required this.onToggle});

  final bool pinned;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return IconButton(
      tooltip: pinned ? 'Buka semat' : 'Semat',
      icon: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        color: pinned ? dae.onSurface : dae.onSurfaceSecondary,
      ),
      onPressed: onToggle,
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.eyebrow, required this.trailing});

  final String eyebrow;
  final Widget trailing;

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
          Expanded(child: DsEyebrow(eyebrow)),
          trailing,
        ],
      ),
    );
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel();

  @override
  Widget build(BuildContext context) {
    return DsText.caption('membuka dari perangkat…');
  }
}
