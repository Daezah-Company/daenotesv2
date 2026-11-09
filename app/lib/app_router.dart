import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import 'core/ds.dart';
import 'core/dae_loader.dart';
import 'data/providers.dart';
import 'features/auth/auth_screen.dart';
import 'features/graph/graph_screen.dart';
import 'features/notes/archive_screen.dart';
import 'features/notes/dae_inbox.dart';
import 'features/notes/note_editor.dart';
import 'features/reminders/reminders_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/todos/todo_editor.dart';

/// Canonical route names. Feature agents register subroutes against these —
/// detail screens go under [noteDetail]/[todoDetail], never new top levels.
abstract final class DaeRouteNames {
  static const inbox = 'inbox';
  static const graph = 'graph';
  static const reminders = 'reminders';
  static const noteDetail = 'noteDetail';
  static const todoDetail = 'todoDetail';
  static const login = 'login';
  static const register = 'register';
  static const archive = 'archive';
  static const sessionCheck = 'sessionCheck';

  static String notePath(String uuid) => '/note/$uuid';
  static String todoPath(String uuid) => '/todo/$uuid';
}

/// The guarded router. Watching [authControllerProvider] rebuilds it whenever
/// the session changes, so the redirect below always sees a fresh session.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  final signedIn = auth.value != null;
  final deciding = auth.isLoading || auth.isRefreshing;

  return GoRouter(
    initialLocation: '/inbox',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onAuthScreen = loc == '/login' || loc == '/register';
      if (deciding) {
        // Keep the credential form visible while a user submits it. At app
        // startup (or logout), hold protected pages behind a real session
        // gate instead of briefly mounting the dashboard and its sync engine.
        if (onAuthScreen || loc == '/session-check') return null;
        return '/session-check?from=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (!signedIn && !onAuthScreen) return '/login';
      if (signedIn && onAuthScreen) return '/inbox';
      if (loc == '/session-check') {
        final destination = _safeDestination(state.uri.queryParameters['from']);
        return signedIn ? destination ?? '/inbox' : '/login';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/session-check',
        name: DaeRouteNames.sessionCheck,
        builder: (context, state) => const _SessionCheckScreen(),
      ),
      GoRoute(
        path: '/login',
        name: DaeRouteNames.login,
        pageBuilder: (context, state) => _daePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        name: DaeRouteNames.register,
        pageBuilder: (context, state) =>
            _daePage(state, const RegisterScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inbox',
                name: DaeRouteNames.inbox,
                builder: (context, state) => DaeInboxScreen(
                  capture: state.uri.queryParameters['capture'],
                ),
              ),
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/graph',
                name: DaeRouteNames.graph,
                // `/graph?focus=<uuid>` centres that node (deep link from any
                // other surface).
                builder: (context, state) => GraphScreen(
                  onOpenItem: (type, uuid) => context.push(
                    type == DaeItemType.note
                        ? DaeRouteNames.notePath(uuid)
                        : DaeRouteNames.todoPath(uuid),
                  ),
                  focusUuid: state.uri.queryParameters['focus'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reminders',
                name: DaeRouteNames.reminders,
                builder: (context, state) => const RemindersScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/archive',
        name: DaeRouteNames.archive,
        pageBuilder: (context, state) => _daePage(state, const ArchiveScreen()),
      ),
      GoRoute(
        path: '/note/:uuid',
        name: DaeRouteNames.noteDetail,
        pageBuilder: (context, state) => _daePage(
          state,
          NoteDetailScreen(uuid: state.pathParameters['uuid']!),
        ),
      ),
      GoRoute(
        path: '/todo/:uuid',
        name: DaeRouteNames.todoDetail,
        pageBuilder: (context, state) => _daePage(
          state,
          TodoDetailScreen(uuid: state.pathParameters['uuid']!),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: DsText.caption('Rute tidak dikenal: ${state.uri}')),
    ),
  );
});

/// DaeNotes' route transition: the new page drifts in from the left while the
/// page underneath settles back and dims. Kept short so navigation still feels
/// immediate, and the shell's tab branches deliberately stay an `IndexedStack`
/// — branch switches must not throw away scroll or graph state.
CustomTransitionPage<void> _daePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: DsMotion.page,
    reverseTransitionDuration: DsMotion.pageExit,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        DsRouteTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        ),
  );
}

String? _safeDestination(String? value) {
  if (value == null || !value.startsWith('/') || value.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.path == '/login' ||
      uri.path == '/register' ||
      uri.path == '/session-check') {
    return null;
  }
  return uri.toString();
}

class _SessionCheckScreen extends StatelessWidget {
  const _SessionCheckScreen();

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Scaffold(
      backgroundColor: dae.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 68,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  DaeLoader(
                    size: 68,
                    strokeWidth: 2,
                    color: dae.onSurface,
                  ),
                  const DaeMark(size: 44),
                ],
              ),
            ),
            const SizedBox(height: Ds.s4),
            const SizedBox(height: Ds.s3),
            DsText.caption('MEMERIKSA SESI'),
          ],
        ),
      ),
    );
  }
}
