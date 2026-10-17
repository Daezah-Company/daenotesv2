import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/ds.dart';
import 'data/providers.dart';
import 'data/sync/sync_engine.dart';

/// The app chrome: mono eyebrow header with wordmark + sync status, the
/// routed surface, and the bottom tab strip Beranda / Graf / Pengingat.
/// Tab labels follow the contract's tab-underline voice, not Material tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = ['Beranda', 'Graf', 'Pengingat'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dae = context.dae;
    final sync = ref.watch(syncStatusProvider).value;
    final pending = sync?.pendingCount ?? 0;

    return Scaffold(
      backgroundColor: dae.background,
      body: Column(
        children: [
          _ShellHeader(pendingCount: pending, phase: sync?.phase),
          Expanded(child: navigationShell),
          DsTabBar(
            labels: _tabs,
            currentIndex: navigationShell.currentIndex,
            onChanged: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({required this.pendingCount, this.phase});

  final int pendingCount;
  final SyncPhase? phase;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Ds.s4, vertical: Ds.s2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dae.hairline.withValues(alpha: 0.28)),
          ),
        ),
        child: Row(
          children: [
            // Wordmark: mono eyebrow + Bricolage name, per the layout sketch.
            const DsEyebrow('DaeNotes'),
            const Spacer(),
            _SyncDot(pendingCount: pendingCount, phase: phase),
          ],
        ),
      ),
    );
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.pendingCount, this.phase});

  final int pendingCount;
  final SyncPhase? phase;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final color = switch (phase) {
      SyncPhase.error => Ds.threadRose,
      SyncPhase.syncing => Ds.threadSlate,
      _ when pendingCount > 0 => Ds.threadAmber,
      _ => null,
    };
    return Tooltip(
      message: phase == SyncPhase.error
          ? 'Sinkronisasi gagal — mencoba lagi'
          : pendingCount > 0
          ? '$pendingCount perubahan menunggu kirim'
          : 'Sudah tersinkron',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Ds.s2),
        child: DsPulse(
          active: phase == SyncPhase.syncing,
          child: AnimatedContainer(
            duration: DsMotion.standard,
            curve: DsMotion.onScreen,
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color ?? Colors.transparent,
              border: Border.all(color: color ?? dae.onSurfaceSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
