import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/providers.dart';
import '../notes/widgets/dae_widgets.dart';

class ShareItemSheet extends ConsumerStatefulWidget {
  const ShareItemSheet({super.key, required this.type, required this.uuid});

  final String type;
  final String uuid;

  static Future<void> show(
    BuildContext context, {
    required String type,
    required String uuid,
  }) => showDsSheet<void>(
    context,
    builder: (_) => ShareItemSheet(type: type, uuid: uuid),
  );

  @override
  ConsumerState<ShareItemSheet> createState() => _ShareItemSheetState();
}

class _ShareItemSheetState extends ConsumerState<ShareItemSheet> {
  final _email = TextEditingController();
  List<Map<String, dynamic>> _people = const [];
  Map<String, dynamic>? _owner;
  String? _myPermission;
  String _invitePermission = 'editor';
  int? _updatingUserId;
  bool _canManage = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(apiClientProvider)
          .collaborators(widget.type, widget.uuid);
      if (mounted) {
        setState(() {
          _people = (data['collaborators'] as List? ?? const [])
              .map((row) => (row as Map).cast<String, dynamic>())
              .toList();
          _owner = (data['owner'] as Map?)?.cast<String, dynamic>();
          _myPermission = data['my_permission'] as String?;
          _canManage = data['can_manage'] == true;
        });
      }
    } on DioException catch (error) {
      if (mounted) _message(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _share() async {
    final email = _email.text.trim();
    if (email.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .shareItem(
            widget.type,
            widget.uuid,
            email,
            permission: _invitePermission,
          );
      _email.clear();
      await _load();
      if (mounted) _message('Akses kolaborasi ditambahkan.');
    } on DioException catch (error) {
      if (mounted) _message(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setPermission(int userId, String permission) async {
    if (_updatingUserId != null) return;
    setState(() => _updatingUserId = userId);
    try {
      await ref
          .read(apiClientProvider)
          .updateSharePermission(widget.type, widget.uuid, userId, permission);
      await _load();
      if (mounted) {
        _message(
          permission == 'editor'
              ? 'Akses diubah: boleh mengedit.'
              : 'Akses diubah: hanya melihat.',
        );
      }
    } on DioException catch (error) {
      if (mounted) _message(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _updatingUserId = null);
    }
  }

  Future<void> _revoke(int userId) async {
    try {
      await ref
          .read(apiClientProvider)
          .revokeShare(widget.type, widget.uuid, userId);
      await _load();
    } on DioException catch (error) {
      if (mounted) _message(_errorMessage(error));
    }
  }

  String _errorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['errors'] is Map) {
      final errors = data['errors'] as Map;
      final first = errors.isEmpty ? null : errors.values.first;
      if (first is List && first.isNotEmpty) return '${first.first}';
    }
    if (error.response?.statusCode == 404) {
      return 'Item belum tersinkron atau akun tidak ditemukan.';
    }
    return 'Gagal mengubah kolaborator. Periksa koneksi lalu coba lagi.';
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Ds.s4,
          Ds.s3,
          Ds.s4,
          Ds.s5 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DsSectionHeader(
              text: 'Kolaborator',
              trailing: DsButton.ghost(
                label: 'Selesai',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: Ds.s3),
            if (_canManage)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _share(),
                      decoration: const InputDecoration(
                        hintText: 'Email akun DaeNotes',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: Ds.s2),
                  DropdownButton<String>(
                    value: _invitePermission,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'editor', child: Text('Edit')),
                      DropdownMenuItem(value: 'viewer', child: Text('Lihat')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _invitePermission = value);
                            }
                          },
                  ),
                  const SizedBox(width: Ds.s1),
                  DsButton.filled(
                    label: _saving ? 'Tunggu' : 'Tambah',
                    onPressed: _saving ? null : _share,
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DsText.caption('DIBAGIKAN OLEH'),
                  const SizedBox(height: Ds.s1),
                  DsText.body('${_owner?['name'] ?? 'Pemilik item'}'),
                  if (_owner?['email'] != null)
                    DsText.caption('${_owner!['email']}'),
                  const SizedBox(height: Ds.s2),
                  DsText.caption(
                    _myPermission == 'viewer'
                        ? 'Akses hanya lihat · undangan dikelola pemilik.'
                        : 'Akses edit · undangan dikelola pemilik.',
                  ),
                ],
              ),
            const SizedBox(height: Ds.s3),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Ds.s3),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_canManage && _people.isEmpty)
              DsText.caption('Belum ada orang yang berbagi item ini.')
            else if (_canManage)
              ..._people.map((person) {
                final userId = (person['user_id'] as num).toInt();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.person_outline,
                    color: dae.onSurfaceSecondary,
                  ),
                  title: DsText.body('${person['name'] ?? ''}'),
                  subtitle: DsText.caption('${person['email'] ?? ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<String>(
                        value: person['permission'] == 'viewer'
                            ? 'viewer'
                            : 'editor',
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: 'editor',
                            child: Text('Bisa edit'),
                          ),
                          DropdownMenuItem(
                            value: 'viewer',
                            child: Text('Lihat saja'),
                          ),
                        ],
                        onChanged: _updatingUserId == null
                            ? (permission) {
                                if (permission != null &&
                                    permission != person['permission']) {
                                  _setPermission(userId, permission);
                                }
                              }
                            : null,
                      ),
                      IconButton(
                        tooltip: 'Hapus akses',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: _updatingUserId == null
                            ? () => _revoke(userId)
                            : null,
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: Ds.s2),
            if (_canManage)
              DsText.caption(
                'Bisa edit mengizinkan perubahan isi. Lihat saja hanya dapat membaca. Pemilik tetap satu-satunya yang dapat menghapus item.',
              ),
          ],
        ),
      ),
    );
  }
}
