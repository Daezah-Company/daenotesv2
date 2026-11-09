import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'app_router.dart';
import 'core/dae_splash_reveal.dart';
import 'core/ds.dart';
import 'data/db/database.dart';
import 'data/preferences/app_preferences.dart';
import 'data/providers.dart';
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

  bool get _hasSession =>
      (ref.read(authControllerProvider).asData?.value?.userId ?? 0) > 0;

  Future<void> _setWidgetDatabase(String name) async {
    try {
      await const MethodChannel('daenotes/settings')
          .invokeMethod<void>('setWidgetDatabase', {'name': name});
    } on Object catch (error) {
      debugPrint('Widget account binding failed: $error');
    }
  }

  void _bindAccountFeatures() {
    final session = ref.read(authControllerProvider).asData?.value;
    if (session == null || session.userId <= 0) {
      unawaited(_setWidgetDatabase(''));
      return;
    }
    final tokens = ref.read(tokenStorageProvider);
    final name = AppDatabase.databaseNameForAccount(
      userId: session.userId,
      legacyOwnerId: tokens.legacyDatabaseOwnerId,
    );
    unawaited(_setWidgetDatabase(name));
    _syncReminders();
  }

  Future<void> _reconcileReminders() async {
    if (!_hasSession) return;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindAccountFeatures());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_hasSession) return;
    // Notifications armed before a process kill are gone; the rows are the
    // source of truth, so re-diff them every time the app comes back.
    if (state == AppLifecycleState.resumed) {
      _syncReminders();

      // The Android home-screen widget writes through SQLite while Flutter may
      // remain alive in the background. Drift cannot observe that second
      // connection, so invalidate its query streams when the app resumes.
      final db = ref.read(databaseProvider);
      db.notifyUpdates({
        for (final table in db.allTables) TableUpdate.onTable(table),
      });
      ref.read(syncEngineProvider).syncIfPending().catchError((Object error) {
        debugPrint('Widget capture sync failed: $error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (next.isLoading) {
        unawaited(_setWidgetDatabase(''));
        return;
      }
      _bindAccountFeatures();
    });
    final preferences = ref.watch(appPreferencesProvider);
    // Dark-first (contract §1); light mode reuses the same tokens, swapped.
    return MaterialApp.router(
      title: 'DaeNotes',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          DaeSplashReveal(child: child ?? const SizedBox.shrink()),
      theme: DsTheme.light(),
      darkTheme: DsTheme.dark(),
      themeMode: preferences.themeMode,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
