import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/ds.dart';
import 'features/reminders/reminders_controller.dart';
import 'features/reminders/reminders_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DaeNotesApp()));
}

class DaeNotesApp extends ConsumerStatefulWidget {
  const DaeNotesApp({super.key});

  @override
  ConsumerState<DaeNotesApp> createState() => _DaeNotesAppState();
}

class _DaeNotesAppState extends ConsumerState<DaeNotesApp>
    with WidgetsBindingObserver {
  Future<void>? _schedulerInit;

  /// One-shot plugin boot. Cached so a resume during a slow first init does not
  /// re-request permissions.
  Future<void> _bootScheduler() =>
      _schedulerInit ??= ref.read(reminderSchedulerProvider).init();

  Future<void> _reconcileReminders() async {
    await _bootScheduler();
    await ref.read(reminderActionsProvider).reconcile();
  }

  void _syncReminders() {
    _reconcileReminders().catchError((Object error) {
      // A reminder that could not be armed must not take the app down; the
      // pending rows stay visible in the Tertunda group and retry on resume.
      debugPrint('Reminder sync failed: $error');
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReminders());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Notifications armed before a process kill are gone; the rows are the
    // source of truth, so re-diff them every time the app comes back.
    if (state == AppLifecycleState.resumed) _syncReminders();
  }

  @override
  Widget build(BuildContext context) {
    // Dark-first (contract §1); light mode reuses the same tokens, swapped.
    return MaterialApp.router(
      title: 'DaeNotes',
      debugShowCheckedModeBanner: false,
      theme: DsTheme.light(),
      darkTheme: DsTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
