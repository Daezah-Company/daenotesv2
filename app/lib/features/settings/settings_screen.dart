import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/providers.dart';
import '../../data/preferences/app_preferences.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loggingOut = false;

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Sesi akun akan dihapus dari perangkat. Catatan lokal tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !mounted) return;

    setState(() => _loggingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } on Object {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat keluar. Coba lagi.')),
      );
    }
  }

  Future<void> _openNotificationSettings(BuildContext context) async {
    try {
      await const MethodChannel('daenotes/settings')
          .invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan notifikasi tidak dapat dibuka.'),
        ),
      );
    } on MissingPluginException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan ini hanya tersedia di Android.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final preferences = ref.watch(appPreferencesProvider);
    final controller = ref.read(appPreferencesProvider.notifier);
    final session = ref.watch(authControllerProvider).asData?.value;
    return Scaffold(
      backgroundColor: dae.background,
      appBar: AppBar(
        title: DsText.displaySm('Pengaturan'),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s3, Ds.s4, Ds.s8),
        children: [
          const DsEyebrow('TAMPILAN'),
          const SizedBox(height: Ds.s2),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Ds.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DsText.body('Tema'),
                  const SizedBox(height: Ds.s2),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Gelap'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Terang'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Sistem'),
                      ),
                    ],
                    selected: {preferences.themeMode},
                    onSelectionChanged: (value) =>
                        controller.setThemeMode(value.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Ds.s5),
          const DsEyebrow('UMPAN BALIK'),
          const SizedBox(height: Ds.s2),
          Card(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  title: DsText.body('Getaran sentuh'),
                  subtitle: DsText.caption('Haptic ringan saat berinteraksi'),
                  value: preferences.haptics,
                  onChanged: (value) async {
                    await controller.setHaptics(value);
                    await controller.tapFeedback();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  title: DsText.body('Suara antarmuka'),
                  subtitle: DsText.caption('Bunyi singkat saat menangkap item'),
                  value: preferences.uiSounds,
                  onChanged: controller.setUiSounds,
                ),
              ],
            ),
          ),
          const SizedBox(height: Ds.s5),
          const DsEyebrow('NOTIFIKASI'),
          const SizedBox(height: Ds.s2),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: DsText.body('Pengingat'),
              subtitle: DsText.caption(
                'Suara dan ikon notifikasi mengikuti pengaturan kanal DaeNotes di Android.',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openNotificationSettings(context),
            ),
          ),
          const SizedBox(height: Ds.s5),
          const DsEyebrow('AKUN'),
          const SizedBox(height: Ds.s2),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: DsText.body('Keluar dari akun'),
              subtitle: DsText.caption(
                session?.email ?? 'Sesi akun di perangkat ini',
              ),
              trailing: _loggingOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _loggingOut ? null : _confirmLogout,
            ),
          ),
        ],
      ),
    );
  }
}
